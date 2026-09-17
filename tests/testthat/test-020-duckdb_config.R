# DuckDB connection configuration and per-file conversion failure handling.
#
# The failure-handling tests are the important ones: until 0.12.0 a JSON file
# that failed to convert was only message()d when `verbose`, and the run still
# reported success -- so the page was silently missing from the corpus and
# every downstream count was quietly wrong.

# -- byte parsing / formatting -----------------------------------------------

test_that(".pro_parse_bytes understands DuckDB's size strings", {
  expect_equal(.pro_parse_bytes("1024"), 1024)
  expect_equal(.pro_parse_bytes("1KiB"), 1024)
  expect_equal(.pro_parse_bytes("1 MiB"), 1024^2)
  expect_equal(.pro_parse_bytes("28.7 GiB"), 28.7 * 1024^3)
  expect_equal(.pro_parse_bytes("2GB"), 2 * 1024^3)
  expect_true(is.na(.pro_parse_bytes("not a size")))
  expect_true(is.na(.pro_parse_bytes("")))
})

test_that(".pro_fmt_bytes returns NULL rather than guessing", {
  # NULL means "emit no SET", so an undetectable RAM size degrades to DuckDB's
  # own default instead of to an arbitrary number.
  expect_null(.pro_fmt_bytes(NULL))
  expect_null(.pro_fmt_bytes(NA_real_))
  expect_null(.pro_fmt_bytes(0))
  expect_null(.pro_fmt_bytes(-1))
  expect_match(.pro_fmt_bytes(2 * 1024^3), "^2048MB$")
})

test_that(".pro_total_ram_bytes is plausible and cached", {
  ram <- .pro_total_ram_bytes()
  skip_if(is.na(ram), "could not determine RAM")
  expect_gt(ram, 1024^3)          # more than 1 GB
  expect_lt(ram, 1024^5)          # less than 1 PB
  expect_identical(.pro_total_ram_bytes(), ram)
})

test_that(".pro_worker_memory divides the budget between workers", {
  skip_if(is.na(.pro_total_ram_bytes()), "could not determine RAM")
  one  <- .pro_parse_bytes(.pro_worker_memory(1L))
  four <- .pro_parse_bytes(.pro_worker_memory(4L))
  expect_gt(one, four)
  expect_equal(four, one / 4, tolerance = 0.02)
  # never below the 1 GB floor, however many workers are asked for
  expect_gte(.pro_parse_bytes(.pro_worker_memory(10000L)), 1024^2)
})

# -- the connection factory --------------------------------------------------

test_that(".pro_con applies every setting it is given", {
  tmp <- withr::local_tempdir()
  con <- .pro_con(
    memory_limit = "1GB", temp_dir = file.path(tmp, "spill"),
    threads = 2L, preserve_order = TRUE
  )
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  get1 <- function(k) {
    DBI::dbGetQuery(con, sprintf("SELECT current_setting('%s') AS v", k))$v[[1L]]
  }
  # DuckDB reports the limit back in binary units, and reads "1GB" as 10^9,
  # so compare bytes rather than the formatted string.
  expect_equal(.pro_parse_bytes(get1("memory_limit")), 1e9, tolerance = 0.01)
  expect_equal(as.integer(get1("threads")), 2L)
  expect_true(as.logical(get1("preserve_insertion_order")))
  expect_match(get1("temp_directory"), "spill")
  expect_true(dir.exists(file.path(tmp, "spill")))
})

test_that(".pro_con defaults preserve_insertion_order to FALSE", {
  con <- .pro_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  v <- DBI::dbGetQuery(
    con, "SELECT current_setting('preserve_insertion_order') AS v"
  )$v[[1L]]
  expect_false(as.logical(v))
})

test_that(".pro_temp_dir is private per task and never the relative .tmp", {
  a <- .pro_temp_dir("file_a.parquet")
  b <- .pro_temp_dir("file_b.parquet")
  expect_false(identical(a, b))
  expect_true(startsWith(a, tempdir()))
  expect_false(basename(dirname(a)) == ".tmp")
})

# -- conversion failure handling ---------------------------------------------

make_json_dir <- function(dir, n_good = 2L, n_bad = 1L) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  for (i in seq_len(n_good)) {
    writeLines(
      sprintf('{"results":[{"id":"W%d","title":"t%d"}],"meta":{"count":1}}', i, i),
      file.path(dir, sprintf("results_page_%d.json", i))
    )
  }
  for (i in seq_len(n_bad)) {
    # Truncated JSON: read_json cannot parse it, so the COPY errors.
    writeLines(
      '{"results":[{"id":"Wbad","title":',
      file.path(dir, sprintf("results_page_%d.json", 100L + i))
    )
  }
  dir
}

test_that("a failing file errors by default and names the file", {
  tmp <- withr::local_tempdir()
  input <- make_json_dir(file.path(tmp, "json"))
  out <- file.path(tmp, "parquet")
  expect_error(
    pro_request_parquet(
      input_json = input, output = out,
      verbose = FALSE, progress = FALSE, enrich = FALSE
    ),
    "failed to convert"
  )
})

test_that("on_error = 'warn' completes, and the good files are still there", {
  tmp <- withr::local_tempdir()
  input <- make_json_dir(file.path(tmp, "json"), n_good = 2L, n_bad = 1L)
  out <- file.path(tmp, "parquet")
  expect_warning(
    pro_request_parquet(
      input_json = input, output = out, on_error = "warn",
      verbose = FALSE, progress = FALSE, enrich = FALSE
    ),
    "failed to convert"
  )
  written <- list.files(out, pattern = "\\.parquet$", recursive = TRUE)
  expect_length(written, 2L)
})

test_that("on_error = 'ignore' is silent", {
  tmp <- withr::local_tempdir()
  input <- make_json_dir(file.path(tmp, "json"))
  out <- file.path(tmp, "parquet")
  expect_no_warning(
    expect_no_error(
      pro_request_parquet(
        input_json = input, output = out, on_error = "ignore",
        verbose = FALSE, progress = FALSE, enrich = FALSE
      )
    )
  )
})

test_that("a failed file leaves no .part behind and no truncated parquet", {
  tmp <- withr::local_tempdir()
  input <- make_json_dir(file.path(tmp, "json"))
  out <- file.path(tmp, "parquet")
  suppressWarnings(pro_request_parquet(
    input_json = input, output = out, on_error = "warn",
    verbose = FALSE, progress = FALSE, enrich = FALSE
  ))
  expect_length(list.files(out, pattern = "\\.part$", recursive = TRUE), 0L)
  # every parquet that does exist must be readable
  for (f in list.files(out, pattern = "\\.parquet$", recursive = TRUE,
                       full.names = TRUE)) {
    expect_s3_class(arrow::read_parquet(f), "data.frame")
  }
})

test_that("the 00_in.progress sentinel survives a partial run", {
  tmp <- withr::local_tempdir()
  input <- make_json_dir(file.path(tmp, "json"))
  out <- file.path(tmp, "parquet")
  suppressWarnings(pro_request_parquet(
    input_json = input, output = out, on_error = "warn",
    verbose = FALSE, progress = FALSE, enrich = FALSE
  ))
  expect_true(file.exists(file.path(out, "00_in.progress")))
})

test_that("a fully successful run clears the sentinel", {
  tmp <- withr::local_tempdir()
  input <- make_json_dir(file.path(tmp, "json"), n_good = 2L, n_bad = 0L)
  out <- file.path(tmp, "parquet")
  pro_request_parquet(
    input_json = input, output = out,
    verbose = FALSE, progress = FALSE, enrich = FALSE
  )
  expect_false(file.exists(file.path(out, "00_in.progress")))
})

test_that("resume converts only what is missing", {
  tmp <- withr::local_tempdir()
  input <- make_json_dir(file.path(tmp, "json"), n_good = 3L, n_bad = 0L)
  out <- file.path(tmp, "parquet")
  pro_request_parquet(
    input_json = input, output = out,
    verbose = FALSE, progress = FALSE, enrich = FALSE
  )
  written <- list.files(out, pattern = "\\.parquet$", recursive = TRUE,
                        full.names = TRUE)
  expect_length(written, 3L)

  # Remove one and mark the rest by mtime; a resume must rewrite only the
  # missing file.
  unlink(written[[1L]])
  Sys.setFileTime(written[[2L]], Sys.time() - 600)
  before <- file.mtime(written[[2L]])

  pro_request_parquet(
    input_json = input, output = out, resume = TRUE,
    verbose = FALSE, progress = FALSE, enrich = FALSE
  )
  expect_true(file.exists(written[[1L]]))
  expect_equal(file.mtime(written[[2L]]), before)
})

test_that("an existing output without resume or overwrite still errors", {
  tmp <- withr::local_tempdir()
  input <- make_json_dir(file.path(tmp, "json"), n_good = 1L, n_bad = 0L)
  out <- file.path(tmp, "parquet")
  pro_request_parquet(
    input_json = input, output = out,
    verbose = FALSE, progress = FALSE, enrich = FALSE
  )
  expect_error(
    pro_request_parquet(
      input_json = input, output = out,
      verbose = FALSE, progress = FALSE, enrich = FALSE
    ),
    "exists"
  )
})
