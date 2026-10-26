library(testthat)
# library(httptest)

# Normal Search `biodiversity AND finance`-------------------------------------

output_json <- file.path(tempdir(), "search_work")
output_jsonl <- file.path(tempdir(), "search_work_jsonl")
output_parquet <- file.path(tempdir(), "search_work_parquet")

unlink(output_json, recursive = TRUE, force = TRUE)
unlink(output_jsonl, recursive = TRUE, force = TRUE)
unlink(output_parquet, recursive = TRUE, force = TRUE)

test_that("pro_request search count `biodiversity AND fiance`", {
  vcr::local_cassette("pro_request_search_biodiversity_AND_fiance_count")
  # Define the API request
  count <- suppressWarnings(
    pro_query(
      entity = "works",
      title_and_abstract.search = "biodiversity AND finance",
      to_publication_date = "2010-01-01"
    )
  ) |>
    pro_request(via = "url", 
      output = output_json,

      verbose = FALSE,
      count_only = TRUE
    )

  # Check that the output file contains the expected data
  expect_snapshot(
    count
  )
})


test_that("pro_request search count", {
  vcr::local_cassette("pro_request_search_biodiversity_AND_fiance_count")
  # Define the API request
  count <- suppressWarnings(
    pro_query(
      entity = "works",
      title_and_abstract.search = "biodiversity AND finance",
      to_publication_date = "2010-01-01"
    )
  ) |>
    pro_request(via = "url", 
      output = output_json,

      verbose = FALSE,
      count_only = TRUE
    )

  # Check that the output file contains the expected data structure
  expect_snapshot({
    count
  })
})

# Test count_only with list of queries -----------------------------------------

test_that("pro_request count_only with list of queries returns data.frame", {
  vcr::local_cassette("pro_request_list_count")

  # Create a list of queries
  queries <- list(
    biodiversity = suppressWarnings(
      pro_query(
        entity = "works",
        title_and_abstract.search = "biodiversity",
        to_publication_date = "2010-01-01"
      )
    ),
    finance = suppressWarnings(
      pro_query(
        entity = "works",
        title_and_abstract.search = "finance",
        to_publication_date = "2010-01-01"
      )
    )
  )

  # Get counts for the list of queries
  count <- pro_request(via = "url", 
    query_url = queries,
    output = output_json,
    verbose = FALSE,
    count_only = TRUE
  )

  # Check that the result is a data.frame
  expect_s3_class(count, "data.frame")

  # Check that it has the expected columns
  expect_named(count, c("count", "db_response_time_ms", "page", "per_page", "error", "query"))

  # Check that the query column has the correct names
  expect_equal(count$query, c("biodiversity", "finance"))

  # Check that count values are numeric
  expect_type(count$count, "integer")

  expect_snapshot(count)
})


test_that("pro_request count_only with unnamed list of queries", {
  vcr::local_cassette("pro_request_list_count")

  # Create an unnamed list of queries
  queries <- list(
    suppressWarnings(
      pro_query(
        entity = "works",
        title_and_abstract.search = "biodiversity",
        to_publication_date = "2010-01-01"
      )
    ),
    suppressWarnings(
      pro_query(
        entity = "works",
        title_and_abstract.search = "finance",
        to_publication_date = "2010-01-01"
      )
    )
  )

  # Get counts for the list of queries
  count <- pro_request(via = "url", 
    query_url = queries,
    output = output_json,
    verbose = FALSE,
    count_only = TRUE
  )

  # Check that the result is a data.frame
  expect_s3_class(count, "data.frame")

  # Check that the query column has auto-generated names
  expect_equal(count$query, c("query_1", "query_2"))
})

unlink(output_json, recursive = TRUE, force = TRUE)
unlink(output_jsonl, recursive = TRUE, force = TRUE)
unlink(output_parquet, recursive = TRUE, force = TRUE)
