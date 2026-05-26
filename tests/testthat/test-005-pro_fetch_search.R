library(testthat)

# Normal Search `biodiversity AND finance`-------------------------------------

output_dir <- file.path(tempdir(), "project_folder")

unlink(output_dir, recursive = TRUE, force = TRUE)

test_that("pro_fetch search `biodiversity AND fiance`", {
  vcr::local_cassette("pro_fetch_search_biodiversity_AND_finance")
  # Define the API request
  output_json <- suppressWarnings(
    pro_query(
      entity = "works",
      title_and_abstract.search = "biodiversity AND finance",
      to_publication_date = "2010-01-01"
    )
  ) |>
    pro_fetch(
      pages        = 1,
      project_folder = output_dir,
      delete_input = FALSE,
      verbose      = FALSE,
      progress     = TRUE
    )

  # JSON file written by pro_request() is still present (delete_input = FALSE
  # is passed explicitly so the file survives for snapshot comparison).
  expect_true(
    file.exists(file.path(output_dir, "json", "results_page_1.json"))
  )

  # Check JSON content matches snapshot
  expect_snapshot_file(
    path = file.path(output_dir, "json", "results_page_1.json"),
    name = "json",
    compare = compare_json
  )

  # No jsonl subdirectory — pro_fetch() now goes JSON → Parquet directly.
  expect_false(dir.exists(file.path(output_dir, "jsonl")))

  # At least one parquet file produced
  expect_true(
    length(
      list.files(
        file.path(output_dir, "parquet"),
        "*.parquet",
        recursive = TRUE
      )
    ) >= 1
  )
})

# unlink(output_dir, recursive = TRUE, force = TRUE)
