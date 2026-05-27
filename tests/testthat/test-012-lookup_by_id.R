library(testthat)

# ── lookup_by_id() stub ────────────────────────────────────────────────────

testthat::test_that("lookup_by_id() errors with 'moved to openalexSnapshot'", {
  expect_error(
    lookup_by_id(ids = "W1"),
    "moved to the openalexSnapshot package"
  )
  expect_error(
    lookup_by_id(root_dir = "/some/dir", ids = "W1"),
    "moved to the openalexSnapshot package"
  )
})
