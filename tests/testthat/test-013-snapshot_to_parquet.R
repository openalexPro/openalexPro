library(testthat)

# ── snapshot_to_parquet() stub ─────────────────────────────────────────────

testthat::test_that("snapshot_to_parquet() errors with 'moved to openalexSnapshot'", {
  expect_error(
    snapshot_to_parquet(),
    "moved to the openalexSnapshot package"
  )
  expect_error(
    snapshot_to_parquet(root_dir = "/some/dir"),
    "moved to the openalexSnapshot package"
  )
})
