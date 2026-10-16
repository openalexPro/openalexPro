library(testthat)
library(arrow)
library(dplyr)

# parallel retieval ------------------------------------------------------------

output_json <- file.path(tempdir(), "parallel_work")
output_jsonl <- file.path(tempdir(), "parallel_work_jsonl")
output_parquet <- file.path(tempdir(), "parallel_work_parquet")

unlink(output_json, recursive = TRUE, force = TRUE)
unlink(output_jsonl, recursive = TRUE, force = TRUE)
unlink(output_parquet, recursive = TRUE, force = TRUE)

dois <- readRDS(
  testthat::test_path(
    "..",
    "fixtures",
    "dois.rds"
  )
)

build_parallel_req <- function(dois) {
  pro_query(
    entity = "works",
    doi = dois
  )
}

test_that("pro_query with multiple ids", {
  req <- build_parallel_req(dois)

  # Define the API request
  expect_snapshot(
    {
      names(req)
      req
    }
  )
})


test_that("pro_request with url list  and parallel", {
  req <- build_parallel_req(dois)
  vcr::local_cassette("pro_request_parallel")

  # Define the API request
  output_json <- pro_request(
    query_url = req,
    output = output_json,
    verbose = FALSE,
    progress = TRUE
  )

  # Check that the output file contains the expected data
  # Sort to ensure consistent ordering across platforms
  fns <- sort(list.files(output_json, "^results_page_[0-9]+\\.json$", full.names = TRUE, recursive = TRUE))
  expect_snapshot(
    {
      basename(fns)
    }
  )
  for (fn in fns) {
    expect_snapshot_file(
      fn,
      name = paste0("json", "_", basename(dirname(fn)), "_", basename(fn)),
      compare = compare_json
    )
  }
})

test_that("pro_request_jsonl with subfolders", {
  # Convert to jsonl
  output_jsonl <- suppressWarnings(
    output_json |>
      pro_request_jsonl(
        output = output_jsonl,
        verbose = FALSE,
        progress = TRUE
      )
  )

  # Check that the output file contains the expected data
  # Sort to ensure consistent ordering across platforms
  fns <- sort(list.files(output_jsonl, "*.json", full.names = TRUE, recursive = TRUE))
  expect_snapshot(
    {
      basename(fns)
    }
  )
  for (fn in fns) {
    expect_snapshot_file(
      fn,
      name = paste0("jsonl", "_", basename(dirname(fn)), "_", basename(fn)),
      compare = compare_jsonl
    )
  }
})


test_that("pro_request_jsonl_parquet with subfolders", {
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

  # Check that the output file contains the expected data
  # Sort to ensure consistent ordering across platforms
  fns <- sort(list.files(output_jsonl, "*.json", full.names = TRUE, recursive = TRUE))
  expect_snapshot(
    {
      basename(fns)
      p <- arrow::open_dataset(output_parquet)
      p
      p |>
        dplyr::select(page) |>
        dplyr::distinct() |>
        dplyr::arrange(page) |>
        dplyr::collect()
    }
  )
  # for (fn in fns) {
  #   expect_snapshot_file(
  #     fn,
  #     name = paste0("jsonl", "_", basename(dirname(fn)), "_", basename(fn))
  #   )
  # }
})

unlink(output_json, recursive = TRUE, force = TRUE)
unlink(output_jsonl, recursive = TRUE, force = TRUE)
unlink(output_parquet, recursive = TRUE, force = TRUE)

test_that("a list of queries makes no extra count requests", {
  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    httr2::response(
      200,
      headers = list("content-type" = "application/json"),
      body = charToRaw(
        '{"meta":{"count":1,"per_page":200,"next_cursor":null},"results":[{"id":"W1"}]}'
      )
    )
  })
  out <- file.path(withr::local_tempdir(), "json")
  pro_request(
    list(a = "https://api.openalex.org/works?filter=doi:1",
         b = "https://api.openalex.org/works?filter=doi:2"),
    output = out, progress = TRUE
  )
  expect_equal(calls, 2L)
  expect_true(file.exists(file.path(out, "a", "results_page_1.json")))
})

mock_leaves <- function(calls, fail = "doi:bad") {
  function(req) {
    calls$urls <- c(calls$urls, req$url)
    if (!is.null(fail) && grepl(fail, utils::URLdecode(req$url), fixed = TRUE)) {
      return(httr2::response(
        404, headers = list("content-type" = "application/json"),
        body = charToRaw('{"error":"Not found","message":"Work bad not found"}')
      ))
    }
    httr2::response(
      200, headers = list("content-type" = "application/json"),
      body = charToRaw('{"meta":{"count":1,"per_page":200,"next_cursor":null},"results":[{"id":"W1"}]}')
    )
  }
}

test_that("a failing query does not stop the others; resume refetches only it", {
  calls <- new.env()
  httr2::local_mocked_responses(mock_leaves(calls))
  out <- file.path(withr::local_tempdir(), "json")
  queries <- list(
    good = "https://api.openalex.org/works?filter=doi:good",
    bad = "https://api.openalex.org/works?filter=doi:bad"
  )
  err <- expect_error(
    pro_request(queries, output = out, progress = FALSE),
    "1 of 2 queries failed \\(1 completed\\)"
  )
  expect_match(conditionMessage(err), "bad: .*404")
  expect_match(conditionMessage(err), "resume = TRUE")
  expect_true(file.exists(file.path(out, "good", "results_page_1.json")))
  expect_false(file.exists(file.path(out, "good", "00_in.progress")))
  expect_true(file.exists(file.path(out, "bad", "00_in.progress")))

  # the problem is fixed: resume fetches only the failed query
  calls$urls <- NULL
  httr2::local_mocked_responses(mock_leaves(calls, fail = NULL))
  pro_request(queries, output = out, progress = FALSE, resume = TRUE)
  expect_length(calls$urls, 1L)
  expect_match(utils::URLdecode(calls$urls), "doi:bad", fixed = TRUE)
  expect_true(file.exists(file.path(out, "bad", "results_page_1.json")))
})
