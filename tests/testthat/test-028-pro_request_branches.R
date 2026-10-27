library(testthat)

# Argument checks and less common paths of pro_fetch() and pro_request(),
# offline against the paged API mock mock_cursor() (helper_mock_api.R).

url2 <- "https://api.openalex.org/works?filter=type:article&per_page=2"

# --- pro_fetch ----------------------------------------------------------------

test_that("pro_fetch rejects an API key that is not a single string", {
  expect_error(
    pro_fetch(url2, project_folder = withr::local_tempdir(), api_key = 1),
    "`api_key` must be NULL or a length-1 character string"
  )
})

test_that("pro_fetch warns about count_only and refuses count_only = TRUE", {
  expect_error(
    expect_warning(
      pro_fetch(url2, project_folder = withr::local_tempdir(), count_only = TRUE),
      "`count_only` is set"
    ),
    "not supported in `pro_fetch\\(\\)`"
  )
})

test_that("pro_fetch stops on existing subfolders unless overwrite = TRUE", {
  pf <- withr::local_tempdir()
  dir.create(file.path(pf, "json"))
  dir.create(file.path(pf, "parquet"))
  writeLines("old", file.path(pf, "json", "old.txt"))
  expect_error(
    pro_fetch(url2, project_folder = pf),
    "subdirectories already exist in .*json, parquet.*overwrite = TRUE"
  )

  calls <- list()
  local_mocked_bindings(
    pro_request = function(...) {
      calls$request <<- list(...)
      list(...)$output
    },
    pro_request_parquet = function(input_json, ...) {
      calls$parquet <<- c(list(input_json = input_json), list(...))
      invisible(list(...)$output)
    }
  )
  expect_warning(
    pro_fetch(url2, project_folder = pf, overwrite = TRUE, api_key = "",
              count_only = FALSE, workers = 3, download_workers = 2),
    "`count_only` is set"
  )
  expect_false(file.exists(file.path(pf, "json", "old.txt")))
  expect_false(dir.exists(file.path(pf, "parquet")))
  expect_null(calls$request$api_key) # "" means no key
  expect_false(calls$request$count_only)
  expect_equal(calls$request$workers, 2)
  expect_equal(calls$request$output, file.path(pf, "json"))
  expect_equal(calls$parquet$input_json, file.path(pf, "json"))
  expect_equal(calls$parquet$output, file.path(pf, "parquet"))
  expect_equal(calls$parquet$workers, 3)
})

# --- pro_request: arguments ---------------------------------------------------

test_that("pro_request rejects an API key that is not a single string", {
  expect_error(
    pro_request(url2, output = withr::local_tempdir(), api_key = c("a", "b")),
    "`api_key` must be NULL or a length-1 character string"
  )
})

test_that("pro_request announces the error log and sends no key for ''", {
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log, n = 2))
  out <- file.path(withr::local_tempdir(), "json")
  expect_message(
    pro_request(url2, output = out, api_key = "", via = "url", progress = FALSE,
                error_log = file.path(dirname(out), "err.log")),
    "error log file: .*err.log"
  )
  expect_equal(ids_in(out), c("W1", "W2"))
})

test_that("pro_request stops on an existing output unless overwrite = TRUE", {
  out <- withr::local_tempdir()
  writeLines("old", file.path(out, "old.txt"))
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log, n = 2))
  expect_error(
    pro_request(url2, output = out, via = "url", progress = FALSE),
    "exists.\nEither specify `overwrite = TRUE`"
  )
  expect_length(log$requests, 0L)

  suppressMessages(expect_message(
    pro_request(url2, output = out, via = "url", progress = FALSE,
                overwrite = TRUE, verbose = TRUE),
    "Deleting and recreating"
  ))
  expect_false(file.exists(file.path(out, "old.txt")))
  expect_equal(ids_in(out), c("W1", "W2"))
})

test_that("pro_request with a list stops on an existing output unless overwrite = TRUE", {
  out <- withr::local_tempdir()
  writeLines("old", file.path(out, "old.txt"))
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log, n = 2))
  expect_error(
    pro_request(list(a = url2), output = out, via = "url", progress = FALSE),
    "exists.\nEither specify `overwrite = TRUE`"
  )
  pro_request(list(a = url2), output = out, via = "url", progress = FALSE,
              overwrite = TRUE)
  expect_false(file.exists(file.path(out, "old.txt")))
  expect_equal(ids_in(file.path(out, "a")), c("W1", "W2"))
})

test_that("pro_request with a list and no output reports every query as failed", {
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log, n = 2))
  expect_error(
    pro_request(list(a = url2, b = url2), output = NULL, via = "url", progress = FALSE),
    "2 of 2 queries failed \\(0 completed\\).*a: No `output` specified!"
  )
  expect_length(log$requests, 0L)
})

test_that("pro_request lists at most 10 failed queries", {
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log, n = 2, fail_at = 0L))
  queries <- setNames(rep(list(url2), 12), paste0("q", 1:12))
  suppressMessages(expect_error(
    pro_request(queries, output = file.path(withr::local_tempdir(), "json"),
                via = "url", progress = FALSE),
    "12 of 12 queries failed.*q10: .*\\.\\.\\. and 2 more"
  ))
})

# --- pro_request: paging details ----------------------------------------------

test_that("pro_request treats a non-numeric cost header as zero", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(200, headers = list(
      "content-type" = "application/json",
      "x-ratelimit-credits-used" = "n/a"
    ), body = charToRaw('{"meta":{"count":1,"per_page":2,"next_cursor":null},"results":[{"id":"W1"}]}'))
  })
  out <- file.path(withr::local_tempdir(), "json")
  pro_request(url2, output = out, via = "url", progress = FALSE)
  rec <- jsonlite::read_json(file.path(out, "_query.json"))
  expect_equal(rec$requests, 1L)
  expect_equal(rec$credits, 0L)
})

test_that("pro_request verbose reports the OQL and each page", {
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log, n = 3))
  msgs <- capture_messages(
    pro_request(url2, output = file.path(withr::local_tempdir(), "oqo"),
                via = "oqo", progress = FALSE, verbose = TRUE)
  )
  expect_match(msgs, "Query \\(OQL\\): get works where type is \\(article\\)", all = FALSE)
  expect_match(msgs, "Downloading page 2", all = FALSE)
  expect_false(any(grepl("^URL: ", msgs))) # POST: no URL to show

  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log, n = 3))
  msgs <- capture_messages(
    pro_request(paste0(url2, "&api_key=secret"),
                output = file.path(withr::local_tempdir(), "url"),
                via = "url", progress = FALSE, verbose = TRUE)
  )
  expect_match(msgs, "Downloading page 2", all = FALSE)
  url_msg <- grep("^URL: ", msgs, value = TRUE)
  expect_length(url_msg, 1L)
  expect_match(url_msg, "api_key=<redacted>", fixed = TRUE)
  expect_false(grepl("secret", url_msg, fixed = TRUE))
})

test_that("pro_request completes the progress when there are fewer pages than counted", {
  # meta$count announces 10 records (5 pages), but only 2 pages come
  out <- withr::local_tempdir()
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log, n = 4, count = 10))
  suppressMessages(
    pro_request(url2, output = file.path(out, "scalar"), via = "url", progress = TRUE)
  )
  expect_equal(ids_in(file.path(out, "scalar")), paste0("W", 1:4))

  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log, n = 4, count = 10))
  suppressMessages(
    pro_request(list(a = url2), output = file.path(out, "list"), via = "url",
                progress = TRUE)
  )
  expect_equal(ids_in(file.path(out, "list", "a")), paste0("W", 1:4))
  expect_false(file.exists(file.path(out, "list", "a", "00_in.progress")))
})

test_that("pro_request with progress saves single records from a list", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(200, headers = list("content-type" = "application/json"),
                    body = charToRaw(sprintf('{"id":"%s"}', basename(httr2::url_parse(req$url)$path))))
  })
  out <- file.path(withr::local_tempdir(), "json")
  suppressMessages(pro_request(
    list(a = "https://api.openalex.org/works/W1", b = "https://api.openalex.org/works/W2"),
    output = out, via = "url", progress = TRUE
  ))
  expect_equal(jsonlite::read_json(file.path(out, "a", "single_1.json"))$id, "W1")
  expect_equal(jsonlite::read_json(file.path(out, "b", "single_1.json"))$id, "W2")
})

test_that("resume with progress skips finished leaves and catches up the bar", {
  out <- file.path(withr::local_tempdir(), "json")
  # Interrupted leaf `b` (pages 1-2 saved), finished leaf `a`
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log, fail_at = 4L, fail_if = "type:book"))
  queries <- list(
    a = "https://api.openalex.org/works?filter=type:article&per_page=2",
    b = "https://api.openalex.org/works?filter=type:book&per_page=2"
  )
  suppressMessages(expect_error(
    pro_request(queries, output = out, via = "url", progress = FALSE),
    "1 of 2 queries failed"
  ))
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log))
  msgs <- capture_messages(
    pro_request(queries, output = out, via = "url", progress = TRUE, resume = TRUE)
  )
  expect_match(msgs, "Resuming `b` at page 3", all = FALSE)
  expect_equal(page_cursors(log), "c4") # `a` untouched, `b` continues
  expect_equal(ids_in(file.path(out, "b")), paste0("W", 1:5))

  # Same for a single query with the cli progress bar
  single <- file.path(withr::local_tempdir(), "json")
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log, fail_at = 4L))
  suppressMessages(
    expect_error(pro_request(url2, output = single, via = "url", progress = FALSE), "404")
  )
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log))
  msgs <- capture_messages(
    pro_request(url2, output = single, via = "url", progress = TRUE, resume = TRUE)
  )
  expect_match(msgs, "Resuming `json` at page 3", all = FALSE)
  expect_equal(ids_in(single), paste0("W", 1:5))
})

test_that(".pr_report_cost ignores queries without cost", {
  expect_null(.pr_report_cost(list(NULL, NULL)))
  expect_message(
    total <- .pr_report_cost(list(c(requests = 2, credits = 3, usd = 0.5), NULL)),
    "2 requests, 3 credits"
  )
  expect_equal(total[["usd"]], 0.5)
})
