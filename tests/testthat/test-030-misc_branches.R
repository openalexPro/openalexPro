library(testthat)

# Remaining offline branches: the deprecated two-step JSONL pipeline,
# pro_download_content() errors, compatibility_report(), id_block(),
# jq_execute(add_columns) and verbose compaction.

keypaper_dir <- function(env = parent.frame()) {
  d <- file.path(withr::local_tempdir(.local_envir = env), "json")
  dir.create(d)
  file.copy(
    list.files(test_path("..", "fixtures", "keypaper_json"), full.names = TRUE),
    d
  )
  d
}

# --- pro_request_jsonl (deprecated) -------------------------------------------

test_that("pro_request_jsonl checks its arguments", {
  withr::local_options(lifecycle_verbosity = "quiet")
  expect_error(suppressWarnings(pro_request_jsonl(input_json = "x")),
               "No `output` output folder specified!")
  expect_error(suppressWarnings(pro_request_jsonl(output = "x")),
               "No `input_json`_dir to convert specified!")

  out <- withr::local_tempdir()
  expect_error(
    suppressWarnings(pro_request_jsonl(input_json = "x", output = out)),
    "exists.\nEither specify `overwrite = TRUE`"
  )
  empty <- withr::local_tempdir()
  expect_error(
    suppressWarnings(pro_request_jsonl(input_json = empty, output = out,
                                       overwrite = TRUE, progress = FALSE)),
    "No JSON files found in `input_json`!"
  )
  writeLines("{}", file.path(empty, "results_page_1.json"))
  writeLines("{}", file.path(empty, "single_2.json"))
  expect_error(
    suppressWarnings(pro_request_jsonl(input_json = empty, output = out,
                                       overwrite = TRUE, progress = FALSE)),
    "All JSON files must be of the same type!"
  )
})

test_that("pro_request_jsonl converts verbosely, drops empty pages and deletes input", {
  input <- keypaper_dir()
  # results_page_2.json of the fixture holds no records: its (almost) empty
  # JSONL file is removed
  out <- file.path(dirname(input), "jsonl")
  msgs <- capture_messages(suppressWarnings(
    pro_request_jsonl(input, out, verbose = TRUE, progress = FALSE, delete_input = TRUE)
  ))
  expect_match(msgs, "Preparing 1 of 2 : ", all = FALSE)
  expect_match(msgs, "^Done", all = FALSE)
  expect_equal(list.files(out), "results_page_1.json")
  expect_false(dir.exists(input))
  expect_false(file.exists(file.path(out, "00_in.progress")))
})

# --- pro_request_jsonl_parquet (deprecated) -----------------------------------

test_that("pro_request_jsonl_parquet checks its arguments", {
  expect_error(suppressWarnings(pro_request_jsonl_parquet(output = "x")),
               "No `input_jsonl` to convert specified!")
  expect_error(suppressWarnings(pro_request_jsonl_parquet(input_jsonl = "x")),
               "No output to convert to specified!")
  out <- withr::local_tempdir()
  expect_error(
    suppressWarnings(pro_request_jsonl_parquet(input_jsonl = "x", output = out)),
    "exists.\nEither specify `overwrite = TRUE`"
  )
  empty <- withr::local_tempdir()
  expect_error(
    suppressWarnings(pro_request_jsonl_parquet(empty, out, overwrite = TRUE)),
    "No JSON files found in `input_jsonl`!"
  )
  writeLines('{"id": "W1"}', file.path(empty, "results_page_1.json"))
  writeLines('{"id": "W2"}', file.path(empty, "single_2.json"))
  expect_error(
    suppressWarnings(pro_request_jsonl_parquet(empty, out, overwrite = TRUE)),
    "All JSON files must be of the same type!"
  )
})

test_that("pro_request_jsonl_parquet replaces output, reads all rows and deletes input", {
  input <- file.path(withr::local_tempdir(), "jsonl")
  dir.create(input)
  writeLines(c('{"id": "W1", "n": 1}', '{"id": "W2", "n": 2}'),
             file.path(input, "results_page_1.json"))
  out <- file.path(dirname(input), "pq")
  dir.create(out)
  writeLines("old", file.path(out, "old.txt"))
  suppressWarnings(
    pro_request_jsonl_parquet(input, out, overwrite = TRUE, verbose = FALSE,
                              sample_size = 0, delete_input = TRUE)
  )
  expect_false(file.exists(file.path(out, "old.txt")))
  expect_equal(arrow::read_parquet(file.path(out, "results_page_1.parquet"))$id,
               c("W1", "W2"))
  expect_false(dir.exists(input))
})

# --- pro_download_content -----------------------------------------------------

test_that("pro_download_content checks api_key and ids", {
  expect_error(
    pro_download_content("W1", api_key = 1, output = withr::local_tempdir()),
    "`api_key` must be NULL or a length-1 character string"
  )
  expect_error(
    pro_download_content(character(0), output = withr::local_tempdir()),
    "'ids' must be a non-empty character vector"
  )
  expect_error(
    pro_download_content(NA_character_, output = withr::local_tempdir()),
    "'ids' must be a non-empty character vector"
  )
})

test_that("pro_download_content reports HTTP and write errors per ID", {
  httr2::local_mocked_responses(function(req) {
    if (grepl("W403", req$url, fixed = TRUE)) {
      return(httr2::response(403, headers = list("content-type" = "application/json"),
                             body = charToRaw('{"error":"forbidden"}')))
    }
    httr2::response(200, headers = list("content-type" = "application/pdf"),
                    body = as.raw(c(0x25, 0x50, 0x44, 0x46)))
  })
  out <- withr::local_tempdir()
  dir.create(file.path(out, "Wdir.pdf")) # a directory: the PDF cannot be written
  msgs <- capture_messages(suppressWarnings(
    res <- pro_download_content(c("W403", "Wdir", "Wok"), output = out, api_key = "k")
  ))
  expect_equal(res$status, c("error", "error", "ok"))
  expect_equal(res$message[1], "HTTP 403")
  expect_true(nzchar(res$message[2]))
  expect_true(file.exists(file.path(out, "Wok.pdf")))
  expect_match(msgs, "2 downloads failed with errors", all = FALSE)

  out2 <- file.path(withr::local_tempdir(), "new", "dir") # created on the fly
  suppressMessages(pro_download_content("Wok", output = out2, api_key = "k"))
  expect_true(file.exists(file.path(out2, "Wok.pdf")))
})

# --- compatibility_report -----------------------------------------------------

test_that("compatibility_report renders the bundled report in output_dir", {
  skip_if_not_installed("quarto")
  rendered <- NULL
  opened <- NULL
  local_mocked_bindings(
    quarto_render = function(input, quiet, ...) {
      rendered <<- list(input = input, quiet = quiet)
      writeLines("<html></html>", sub("\\.qmd$", ".html", input))
      invisible(NULL)
    },
    .package = "quarto"
  )
  local_mocked_bindings(browseURL = function(url, ...) opened <<- url, .package = "utils")
  out_dir <- file.path(withr::local_tempdir(), "report")

  res <- compatibility_report(output_dir = out_dir, open = FALSE, quiet = TRUE)
  expect_true(file.exists(file.path(out_dir, "compatibility.qmd")))
  expect_equal(rendered$input, file.path(out_dir, "compatibility.qmd"))
  expect_true(rendered$quiet)
  expect_equal(res, normalizePath(file.path(out_dir, "compatibility.html")))
  expect_null(opened)

  expect_invisible(compatibility_report(output_dir = out_dir, open = TRUE))
  expect_equal(opened, res)
})

# --- id_block -----------------------------------------------------------------

test_that("id_block computes blocks from short, long and path IDs", {
  expect_identical(
    id_block(c("W2741809807", "https://openalex.org/W1234567890",
               "https://openalex.org/domains/2", "A9999")),
    c(274180L, 123456L, 0L, 0L)
  )
})

# --- jq_execute ---------------------------------------------------------------

test_that("jq_execute adds the extra columns to every record", {
  out <- withr::local_tempfile(fileext = ".jsonl")
  jq_execute(
    input_json = test_path("..", "fixtures", "keypaper_json", "results_page_1.json"),
    output_jsonl = out,
    add_columns = list(project = "keypaper", batch = "b1")
  )
  recs <- lapply(readLines(out), jsonlite::fromJSON)
  expect_gt(length(recs), 0L)
  expect_true(all(vapply(recs, function(r) identical(r$project, "keypaper"), NA)))
  expect_true(all(vapply(recs, function(r) identical(r$batch, "b1"), NA)))
  expect_true(all(vapply(recs, function(r) is.null(r$abstract_inverted_index), NA)))
})

# --- pro_compact_parquet ------------------------------------------------------

test_that("pro_compact_parquet reports what it compacted when verbose", {
  dir <- withr::local_tempdir()
  for (i in 1:3) {
    arrow::write_parquet(data.frame(id = paste0("W", i), page = as.character(i)),
                         file.path(dir, sprintf("results_page_%d.parquet", i)))
  }
  expect_message(
    pro_compact_parquet(dir, rows = 10, verbose = TRUE),
    "Compacted 3 page file\\(s\\) into 1 file\\(s\\) of up to 10 records."
  )
  expect_equal(list.files(dir, "\\.parquet$"), "results_pages_1-3.parquet")
})
