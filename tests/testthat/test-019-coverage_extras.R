# Tests targeting previously uncovered code paths in:
#   - pro_validate_credentials.R
#   - sample_parquet_n.R

# --- pro_validate_credentials ----------------------------------------------

test_that("pro_validate_credentials returns FALSE for an empty key", {
  # NULL key: pro_rate_limit_status() returns FALSE without making an API call.
  expect_message(
    res <- pro_validate_credentials(api_key = NULL),
    "Testing:"
  )
  expect_false(res)
})

test_that("pro_validate_credentials with show_credentials prints the key", {
  expect_message(
    pro_validate_credentials(api_key = "abc123", show_credentials = TRUE),
    "abc123"
  )
})

# --- sample_parquet_n ------------------------------------------------------

test_that("sample_parquet_n validates its inputs", {
  expect_error(sample_parquet_n(path = NA_character_, n = 5),
               "non-missing character scalar")
  expect_error(sample_parquet_n(path = "x", n = NA),
               "non-missing numeric")
  expect_error(sample_parquet_n(path = "x", n = 0),
               "positive integer")
  expect_error(sample_parquet_n(path = "x", n = 5, seed = NA),
               "non-missing numeric")
  expect_error(sample_parquet_n(path = "x", n = 5, select = character()),
               "non-empty character vector")
})

test_that("sample_parquet_n samples from a temporary parquet file", {
  skip_if_not_installed("arrow")
  pq <- tempfile(fileext = ".parquet")
  on.exit(unlink(pq), add = TRUE)
  arrow::write_parquet(data.frame(id = 1:50, x = letters[1:50 %% 26 + 1]), pq)

  res <- sample_parquet_n(path = pq, n = 10L, seed = 42L)
  expect_s3_class(res, "data.frame")
  expect_lte(nrow(res), 10L)
  expect_setequal(names(res), c("id", "x"))

  sub <- sample_parquet_n(path = pq, n = 5L, seed = 1L, select = "id")
  expect_identical(names(sub), "id")
})

test_that("sample_parquet_n reuses a supplied DBI connection", {
  skip_if_not_installed("arrow")
  pq <- tempfile(fileext = ".parquet")
  on.exit(unlink(pq), add = TRUE)
  arrow::write_parquet(data.frame(id = 1:20), pq)

  con <- DBI::dbConnect(.pro_duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  res <- sample_parquet_n(path = pq, n = 5L, con = con)
  expect_s3_class(res, "data.frame")
  # connection should still be usable
  expect_true(DBI::dbIsValid(con))
})
