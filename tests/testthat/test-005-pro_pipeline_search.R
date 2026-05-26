library(testthat)
# library(httptest)

# Normal Search `biodiversity AND finance`-------------------------------------

output_json <- file.path(tempdir(), "search_work")
output_jsonl <- file.path(tempdir(), "search_work_jsonl")
output_parquet <- file.path(tempdir(), "search_work_parquet")

unlink(output_json, recursive = TRUE, force = TRUE)
unlink(output_jsonl, recursive = TRUE, force = TRUE)
unlink(output_parquet, recursive = TRUE, force = TRUE)

test_that("pro_request search `biodiversity AND fiance`", {
  vcr::local_cassette("pro_request_search_biodiversity_AND_fiance")
  # Define the API request
  output_json <- suppressWarnings(
    pro_query(
      entity = "works",
      title_and_abstract.search = "biodiversity AND finance",
      to_publication_date = "2010-01-01"
    )
  ) |>
    pro_request(
      pages = 1,
      output = output_json,
      verbose = FALSE,
      progress = TRUE
    )

  # Check that the output file contains the expected data (platform-agnostic)
  expect_snapshot_file(
    path = file.path(output_json, "results_page_1.json"),
    name = "json",
    compare = compare_json
  )
})

test_that("pro_request_jsonl_R search `biodiversity AND finance`", {
  # Convert to jsonl
  output_jsonl <- output_json |>
    pro_request_jsonl_R(
      output = output_jsonl,
      verbose = FALSE,
      progress = TRUE
    )

  # Check that the output file contains the expected data (platform-agnostic)
  expect_snapshot_file(
    file.path(output_jsonl, "results_page_1.json"),
    name = "jsonl",
    compare = compare_jsonl
  )
})

test_that("pro_request_jsonl_parquet search `biodiversity AND finance`", {
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
})

unlink(output_json, recursive = TRUE, force = TRUE)
unlink(output_jsonl, recursive = TRUE, force = TRUE)
unlink(output_parquet, recursive = TRUE, force = TRUE)
