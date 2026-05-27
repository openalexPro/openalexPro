library(testthat)

# ── id_block helper (unchanged) ────────────────────────────────────────────

testthat::test_that("id_block computes correct ID blocks", {
  expect_equal(id_block("W1000000001"), 100000L)
  expect_equal(id_block("W2741809807"), 274180L)
  expect_equal(id_block("https://openalex.org/W1000000001"), 100000L)
  blocks <- id_block(c("W1000000001", "W1000000002", "W2000000001"))
  expect_equal(blocks, c(100000L, 100000L, 200000L))
  expect_equal(id_block("A123456789"), 12345L)
  expect_equal(id_block("I987654321"), 98765L)
})

# ── build_corpus_index() stub ──────────────────────────────────────────────

testthat::test_that("build_corpus_index() errors with 'moved to openalexSnapshot'", {
  expect_error(
    build_corpus_index(),
    "moved to the openalexSnapshot package"
  )
  expect_error(
    build_corpus_index(root_dir = "/some/dir"),
    "moved to the openalexSnapshot package"
  )
})
