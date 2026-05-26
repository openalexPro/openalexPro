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

# ── build_corpus_index_R() tests (pure-R, always run) ──────────────────────

testthat::test_that("build_corpus_index_R creates partitioned index for id column", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  corpus_dir      <- file.path(tempdir(), "test_corpus_partitioned")
  dir.create(corpus_dir, recursive = TRUE, showWarnings = FALSE)
  corpus_dir_norm <- normalizePath(corpus_dir)
  index_file      <- file.path(dirname(corpus_dir_norm), "test_corpus_partitioned_id_idx.parquet")
  unlink(index_file, recursive = TRUE)

  test_data <- data.frame(
    id = c(
      "https://openalex.org/W1000000001",
      "https://openalex.org/W1000000002",
      "https://openalex.org/W1000000003",
      "https://openalex.org/W2000000001",
      "https://openalex.org/W2000000002"
    ),
    doi = c(
      "https://doi.org/10.1000/test1",
      "https://doi.org/10.1000/test2",
      NA,
      "https://doi.org/10.1000/test4",
      NA
    ),
    title = c("Paper 1", "Paper 2", "Paper 3", "Paper 4", "Paper 5"),
    stringsAsFactors = FALSE
  )
  arrow::write_parquet(test_data, file.path(corpus_dir, "test.parquet"))

  result <- build_corpus_index_R(corpus_dir = corpus_dir)

  expect_equal(result, index_file)
  expect_true(file.exists(index_file))

  con <- DBI::dbConnect(duckdb::duckdb(), read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  index <- DBI::dbGetQuery(con, paste0("SELECT * FROM read_parquet('", index_file, "')"))

  expect_true("id"              %in% names(index))
  expect_true("id_block"        %in% names(index))
  expect_true("parquet_file"    %in% names(index))
  expect_true("file_row_number" %in% names(index))
  expect_false("doi"            %in% names(index))
  expect_equal(nrow(index), nrow(test_data))
  expect_setequal(index$id, test_data$id)
  expect_setequal(index$id_block, id_block(test_data$id))
  expect_true(all(index$file_row_number >= 0))

  unlink(corpus_dir, recursive = TRUE)
  unlink(index_file, recursive = TRUE)
})

testthat::test_that("build_corpus_index_R errors on non-existent directory", {
  expect_error(
    build_corpus_index_R(corpus_dir = "/non/existent/path"),
    "corpus_dir does not exist"
  )
})

# ── build_corpus_index() tests (binary wrapper, skipped if binary absent) ───

testthat::test_that("build_corpus_index creates index from parquet files (root_dir mode)", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  root_dir   <- file.path(tempdir(), "test_oas_index_root")
  unlink(root_dir, recursive = TRUE)
  parquet_ds <- file.path(root_dir, "parquet", "authors")
  dir.create(parquet_ds, recursive = TRUE, showWarnings = FALSE)

  test_data <- data.frame(
    id    = c("https://openalex.org/A1", "https://openalex.org/A2"),
    name  = c("Alice", "Bob"),
    stringsAsFactors = FALSE
  )
  arrow::write_parquet(test_data, file.path(parquet_ds, "test.parquet"))

  expect_no_error(
    build_corpus_index(root_dir = root_dir, data_sets = "authors")
  )

  index_file <- file.path(root_dir, "parquet", "authors_id_idx.parquet")
  expect_true(file.exists(index_file))

  unlink(root_dir, recursive = TRUE)
})

testthat::test_that("build_corpus_index errors when neither root_dir nor corpus_dir is provided", {
  expect_error(
    build_corpus_index(),
    "Provide either"
  )
})
