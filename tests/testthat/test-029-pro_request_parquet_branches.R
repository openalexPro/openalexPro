library(testthat)

# Less common paths of pro_request_parquet(): argument checks, verbose output,
# add_columns, single records, empty results, failures, the sequential retry
# after a parallel run and input that cannot be deleted. All offline, on the
# keypaper fixture or tiny JSON files in a temporary directory.

keypaper_copy <- function(env = parent.frame()) {
  d <- file.path(withr::local_tempdir(.local_envir = env), "json")
  dir.create(d)
  file.copy(
    list.files(test_path("..", "fixtures", "keypaper_json"), full.names = TRUE),
    d
  )
  d
}

read_pq <- function(dir) {
  as.data.frame(arrow::open_dataset(dir, format = "parquet"))
}

test_that("pro_request_parquet requires input_json and output", {
  expect_error(pro_request_parquet(output = "x"), "No `input_json` specified!")
  expect_error(pro_request_parquet(input_json = "x"), "No `output` specified!")
})

test_that("pro_request_parquet stops when there are no page files", {
  out <- file.path(withr::local_tempdir(), "pq")
  expect_error(
    pro_request_parquet(withr::local_tempdir(), out, progress = FALSE, verbose = FALSE),
    "No JSON files found in `input_json`!"
  )
})

test_that("pro_request_parquet replaces an existing output only with overwrite = TRUE", {
  input <- keypaper_copy()
  out <- file.path(dirname(input), "pq")
  dir.create(out)
  writeLines("old", file.path(out, "old.txt"))
  expect_error(
    pro_request_parquet(input, out, progress = FALSE, verbose = FALSE),
    "exists.\nEither specify `overwrite = TRUE`, `resume = TRUE`"
  )

  msgs <- capture_messages(
    pro_request_parquet(input, out, overwrite = TRUE, progress = FALSE,
                        verbose = TRUE, sample_size = 0,
                        add_columns = list(project = "keypaper", run = 7))
  )
  expect_match(msgs, "Inferring schema from 2 sampled file\\(s\\)", all = FALSE)
  expect_match(msgs, "Applied baseline schema for entity 'works'", all = FALSE)
  expect_false(file.exists(file.path(out, "old.txt")))
  df <- read_pq(out)
  expect_true(all(df$project == "keypaper"))
  expect_true(all(df$run == "7")) # added as text
  expect_true(all(c("abstract", "citation", "page") %in% names(df)))
})

test_that("pro_request_parquet with schema = 'none' keeps the inferred types", {
  input <- keypaper_copy()
  out <- file.path(dirname(input), "pq")
  msgs <- capture_messages(
    pro_request_parquet(input, out, schema = "none", progress = FALSE, verbose = TRUE)
  )
  expect_false(any(grepl("Applied baseline schema", msgs)))
  expect_gt(nrow(read_pq(out)), 0L)
})

test_that("pro_request_parquet converts single records (no results array)", {
  input <- file.path(withr::local_tempdir(), "json")
  dir.create(input)
  writeLines('{"id": "https://openalex.org/W1", "title": "One"}',
             file.path(input, "single_1.json"))
  writeLines('{"id": "https://openalex.org/W2", "title": "Two"}',
             file.path(input, "single_2.json"))
  out <- file.path(dirname(input), "pq")
  pro_request_parquet(input, out, progress = FALSE, verbose = FALSE)
  df <- read_pq(out)
  expect_setequal(df$title, c("One", "Two"))
  expect_setequal(df$page, c("1", "2"))
})

test_that("empty results get the columns of the queried entity's baseline", {
  input <- file.path(withr::local_tempdir(), "json")
  dir.create(input)
  writeLines('{"meta": {"count": 0, "next_cursor": null}, "results": []}',
             file.path(input, "results_page_1.json"))
  jsonlite::write_json(
    list(query_url = "https://api.openalex.org/authors?filter=x:y"),
    file.path(input, "_query.json"), auto_unbox = TRUE
  )
  out <- file.path(dirname(input), "pq")
  msgs <- capture_messages(
    pro_request_parquet(input, out, progress = FALSE, verbose = TRUE)
  )
  # DuckDB cannot unnest an empty array, so the runtime inference fails
  expect_match(msgs, "Schema inference failed", all = FALSE)
  expect_match(msgs, "using the baseline schema for entity 'authors'", all = FALSE)
  expect_true(file.exists(file.path(out, "_query.json")))
})

test_that(".prr_query_entity finds no entity in a root-endpoint (OQL) URL", {
  d <- withr::local_tempdir()
  jsonlite::write_json(list(query_url = "https://api.openalex.org/?oql=get%20works"),
                       file.path(d, "_query.json"), auto_unbox = TRUE)
  expect_null(.prr_query_entity(file.path(d, "results_page_1.json")))
  jsonlite::write_json(list(oqo = list(get_rows = "sources")),
                       file.path(d, "_query.json"), auto_unbox = TRUE)
  expect_equal(.prr_query_entity(file.path(d, "results_page_1.json")), "sources")
})

test_that("a page that fails to convert is reported and its input kept", {
  input <- keypaper_copy()
  out <- file.path(dirname(input), "pq")
  # A non-empty directory where the `.part` sidecar of page 2 goes makes its
  # COPY fail (and is not removed by the clean-up of the sidecar)
  part <- file.path(out, "results_page_2.parquet.part")
  dir.create(part, recursive = TRUE)
  writeLines("x", file.path(part, "blocker"))
  msgs <- character(0)
  expect_warning(
    withCallingHandlers(
      pro_request_parquet(input, out, progress = FALSE, verbose = TRUE,
                          on_error = "warn", delete_input = TRUE, resume = TRUE),
      message = function(m) {
        msgs <<- c(msgs, conditionMessage(m))
        invokeRestart("muffleMessage")
      }
    ),
    "1 of 2 JSON file\\(s\\) failed to convert \\(1 succeeded\\).*results_page_2.json"
  )
  expect_match(msgs, "Failed to convert results_page_2.json", all = FALSE)
  expect_true(dir.exists(input)) # not deleted: it holds the failed page
  expect_true(file.exists(file.path(out, "00_in.progress")))
  expect_true(file.exists(file.path(out, "results_page_1.parquet")))
  expect_false(file.exists(file.path(out, "results_page_2.parquet")))
})

test_that(".prr_report_failures shows at most 10 files", {
  jsons <- as.list(sprintf("/x/results_page_%d.json", 1:12))
  statuses <- as.list(rep("Out of Memory\nmore detail", 12))
  w <- expect_warning(
    .prr_report_failures(1:12, jsons, statuses, "/out", 12L, "warn"),
    "12 of 12 JSON file\\(s\\) failed"
  )
  msg <- conditionMessage(w)
  expect_match(msg, "results_page_10.json: Out of Memory\n", fixed = TRUE)
  expect_match(msg, "... and 2 more", fixed = TRUE)
  expect_false(grepl("more detail", msg, fixed = TRUE))
  expect_null(.prr_report_failures(1:12, jsons, statuses, "/out", 12L, "ignore"))
})

test_that("files failing in a parallel run are retried sequentially", {
  input <- keypaper_copy()
  out <- file.path(dirname(input), "pq")

  # Run "parallel" in this process: the multisession plan becomes sequential.
  real_plan <- future::plan
  local_mocked_bindings(
    plan = function(strategy = NULL, ...) {
      if (inherits(strategy, "multisession")) {
        return(real_plan(future::sequential, substitute = FALSE))
      }
      real_plan(strategy, ..., substitute = FALSE)
    },
    .package = "future"
  )
  real_convert <- .prr_convert_one
  calls <- list()
  local_mocked_bindings(.prr_convert_one = function(fn, ...) {
    args <- list(...)
    calls[[length(calls) + 1L]] <<- list(fn = basename(fn), memory_limit = args$memory_limit,
                                         threads = args$threads)
    # page 2 runs out of memory with the per-worker budget
    if (basename(fn) == "results_page_2.json" && identical(args$threads, 1L)) {
      return("Out of Memory Error")
    }
    real_convert(fn, ...)
  })

  suppressMessages(expect_message(
    pro_request_parquet(input, out, workers = 2, progress = FALSE, verbose = TRUE,
                        memory_limit = "1GB", retry_memory_limit = "2GB"),
    "Retrying 1 failed file\\(s\\) sequentially."
  ))
  fns <- vapply(calls, `[[`, "", "fn")
  expect_equal(fns, c("results_page_1.json", "results_page_2.json", "results_page_2.json"))
  expect_equal(calls[[3]]$memory_limit, "2GB")
  expect_null(calls[[3]]$threads)
  expect_equal(calls[[1]]$memory_limit, "1GB")
  expect_setequal(list.files(out, "\\.parquet$"),
                  c("results_page_1.parquet", "results_page_2.parquet"))
  expect_false(file.exists(file.path(out, "00_in.progress")))
})

test_that("pro_request_parquet warns when delete_input cannot delete the input", {
  skip_on_os("windows")
  skip_if(identical(Sys.info()[["effective_user"]], "root"), "root can delete anything")
  input <- keypaper_copy()
  out <- file.path(withr::local_tempdir(), "pq")
  # unlink(force = TRUE) can empty `input_json`, but not remove it from a
  # read-only parent directory
  Sys.chmod(dirname(input), "555")
  withr::defer(Sys.chmod(dirname(input), "755"))
  expect_warning(
    pro_request_parquet(input, out, progress = FALSE, verbose = FALSE, delete_input = TRUE),
    "Could not delete `input_json` \\(.*json\\); 0 file\\(s\\) left behind"
  )
  expect_true(dir.exists(input))
  expect_length(list.files(out, "\\.parquet$"), 2L) # the conversion itself succeeded
})
