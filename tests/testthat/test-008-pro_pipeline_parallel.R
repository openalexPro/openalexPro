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
  vcr::local_cassette("opt_filter_names")
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
  fns <- sort(list.files(output_json, "*.json", full.names = TRUE, recursive = TRUE))
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

test_that("pro_request_jsonl_R with subfolders", {
  # Convert to jsonl
  output_jsonl <- output_json |>
    pro_request_jsonl_R(
      output = output_jsonl,
      verbose = FALSE,
      progress = TRUE
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
  output_parquet <- output_jsonl |>
    pro_request_jsonl_parquet(
      output = output_parquet,
      verbose = FALSE
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
