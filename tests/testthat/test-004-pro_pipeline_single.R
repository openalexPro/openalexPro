library(testthat)
# library(httptest)

# single work ------------------------------------------------------------

output_json <- file.path(tempdir(), "single_work")
output_jsonl <- file.path(tempdir(), "single_work_jsonl")
output_parquet <- file.path(tempdir(), "single_work_parquet")

unlink(output_json, recursive = TRUE, force = TRUE)
unlink(output_jsonl, recursive = TRUE, force = TRUE)
unlink(output_parquet, recursive = TRUE, force = TRUE)

test_that("pro_request single identifier", {
  vcr::local_cassette("pro_request_single_identifier")
  # Define the API request
  output_json <- pro_query(
    entity = "works",
    id = "W2162348455"
  ) |>
    pro_request(
      pages = 1,
      output = output_json,
      verbose = FALSE,
      progress = TRUE
    )

  # Check that the output file contains the expected data (platform-agnostic)
  expect_snapshot_file(
    file.path(output_json, "single_1.json"),
    name = "json",
    compare = compare_json
  )
})

test_that("pro_request_jsonl single identifier", {
  # Convert to jsonl
  output_jsonl <- suppressWarnings(
    output_json |>
      pro_request_jsonl(
        output = output_jsonl,
        verbose = FALSE,
        progress = TRUE
      )
  )

  # Check that the output file contains the expected data (platform-agnostic)
  expect_snapshot_file(
    file.path(output_jsonl, "single_1.json"),
    name = "jsonl",
    compare = compare_jsonl
  )
})

test_that("pro_request_jsonl_parquet single identifier", {
  # Convert to parquet
  output_parquet <- suppressWarnings(
    output_jsonl |>
      pro_request_jsonl_parquet(
        output = output_parquet,
        verbose = FALSE
      )
  )

  # Check that the output file exists
  expect_true(
    length(list.files(output_parquet, "*.parquet", recursive = TRUE)) >= 1
  )

  # Check that the output file contains the expected data structure
  x <- read_corpus(
    output_parquet,
    return_data = FALSE
  )
  expect_snapshot({
    nrow(x)
    sort(names(x))
  })

  # Check that the output file contains the expected data
  # expect_snapshot_file(file.path(output_json, "results_page_1.json"))
})

unlink(output_json, recursive = TRUE, force = TRUE)
unlink(output_jsonl, recursive = TRUE, force = TRUE)
unlink(output_parquet, recursive = TRUE, force = TRUE)

test_that("resume skips a completed single query without any request", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "json")
  dir.create(out)
  writeLines("{}", file.path(out, "results_page_1.json"))
  # An unroutable URL: reaching the network would error.
  expect_equal(
    pro_request("http://invalid.invalid/works", output = out, resume = TRUE,
                progress = FALSE),
    normalizePath(out)
  )
  expect_true(file.exists(file.path(out, "results_page_1.json")))
})

capture_urls <- function(calls) {
  function(req) {
    calls$urls <- c(calls$urls, req$url)
    httr2::response(
      200, headers = list("content-type" = "application/json"),
      body = charToRaw('{"meta":{"count":1,"per_page":50,"next_cursor":null},"results":[{"id":"W1"}]}')
    )
  }
}

test_that("per_page in the query is kept; page and cursor are replaced with a warning", {
  calls <- new.env()
  httr2::local_mocked_responses(capture_urls(calls))
  expect_warning(
    pro_request(
      "https://api.openalex.org/works?filter=type:article&per_page=50&page=2&cursor=abc",
      output = file.path(withr::local_tempdir(), "json"), progress = FALSE
    ),
    "`page`, `cursor` in the query is replaced by cursor paging"
  )
  q <- httr2::url_parse(calls$urls[[1]])$query
  expect_equal(q$per_page, "50")
  expect_equal(q$cursor, "*")
  expect_null(q$page)
})

test_that("default paging is unchanged: per_page 200 with a cursor, no warning", {
  calls <- new.env()
  httr2::local_mocked_responses(capture_urls(calls))
  expect_no_warning(pro_request(
    "https://api.openalex.org/works?filter=type:article",
    output = file.path(withr::local_tempdir(), "json"), progress = FALSE
  ))
  q <- httr2::url_parse(calls$urls[[1]])$query
  expect_equal(q$per_page, "200")
  expect_equal(q$cursor, "*")
})

test_that("semantic search is fetched without cursor paging", {
  calls <- new.env()
  httr2::local_mocked_responses(capture_urls(calls))
  pro_request(
    pro_query(entity = "works", search.semantic = "coral reef bleaching"),
    output = file.path(withr::local_tempdir(), "json"), progress = FALSE
  )
  q <- httr2::url_parse(calls$urls[[1]])$query
  expect_null(q$cursor)
  expect_equal(q$per_page, "50")
  expect_length(calls$urls, 1L)
})
