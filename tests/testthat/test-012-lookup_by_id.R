library(testthat)

# ── lookup_by_id_R() tests (pure-R, always run) ────────────────────────────

testthat::test_that("lookup_by_id_R retrieves correct records by OpenAlex ID using partitioned index", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  corpus_dir      <- file.path(tempdir(), "test_corpus_lookup")
  dir.create(corpus_dir, recursive = TRUE, showWarnings = FALSE)
  corpus_dir_norm <- normalizePath(corpus_dir)
  index_file      <- file.path(dirname(corpus_dir_norm), "test_corpus_lookup_id_idx.parquet")
  unlink(index_file, recursive = TRUE)

  test_data <- data.frame(
    id = c(
      "https://openalex.org/W1000000001",
      "https://openalex.org/W1000000002",
      "https://openalex.org/W1000000003",
      "https://openalex.org/W2000000001"
    ),
    doi   = c("https://doi.org/10.1000/test1", "https://doi.org/10.1000/test2", NA, "https://doi.org/10.1000/test4"),
    title = c("Paper 1", "Paper 2", "Paper 3", "Paper 4"),
    year  = c(2020, 2021, 2022, 2023),
    stringsAsFactors = FALSE
  )
  arrow::write_parquet(test_data, file.path(corpus_dir, "test.parquet"))
  build_corpus_index_R(corpus_dir = corpus_dir)

  result <- lookup_by_id_R(index_file = index_file, ids = "https://openalex.org/W1000000001")
  expect_equal(nrow(result), 1)
  expect_equal(result$title, "Paper 1")

  result <- lookup_by_id_R(index_file = index_file, ids = "W1000000002")
  expect_equal(nrow(result), 1)
  expect_equal(result$title, "Paper 2")

  result <- lookup_by_id_R(index_file = index_file, ids = c("W1000000001", "W1000000003"))
  expect_equal(nrow(result), 2)
  expect_setequal(result$title, c("Paper 1", "Paper 3"))

  result <- lookup_by_id_R(index_file = index_file, ids = c("W1000000001", "W2000000001"))
  expect_equal(nrow(result), 2)
  expect_setequal(result$title, c("Paper 1", "Paper 4"))

  unlink(corpus_dir,  recursive = TRUE)
  unlink(index_file,  recursive = TRUE)
})

testthat::test_that("lookup_by_id_R writes to output directory when output is set", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  corpus_dir      <- file.path(tempdir(), "test_corpus_output")
  dir.create(corpus_dir, recursive = TRUE, showWarnings = FALSE)
  corpus_dir_norm <- normalizePath(corpus_dir)
  index_file      <- file.path(dirname(corpus_dir_norm), "test_corpus_output_id_idx.parquet")
  output_dir      <- file.path(tempdir(), "test_output_lookup")
  unlink(index_file,  recursive = TRUE)
  unlink(output_dir,  recursive = TRUE)

  test_data <- data.frame(
    id    = c("https://openalex.org/W1000000001", "https://openalex.org/W1000000002", "https://openalex.org/W2000000001"),
    title = c("Paper 1", "Paper 2", "Paper 3"),
    stringsAsFactors = FALSE
  )
  arrow::write_parquet(test_data, file.path(corpus_dir, "test.parquet"))
  build_corpus_index_R(corpus_dir = corpus_dir)

  result <- lookup_by_id_R(
    index_file = index_file,
    ids        = c("W1000000001", "W2000000001"),
    output     = output_dir
  )
  expect_equal(result, output_dir)
  expect_true(dir.exists(output_dir))

  parquet_files <- list.files(output_dir, pattern = "\\.parquet$")
  expect_true(length(parquet_files) >= 1)

  total_rows <- sum(sapply(parquet_files, function(f) nrow(arrow::read_parquet(file.path(output_dir, f)))))
  expect_equal(total_rows, 2)

  expect_error(
    lookup_by_id_R(index_file = index_file, ids = "W1000000001", output = output_dir),
    "Output directory already exists"
  )

  unlink(corpus_dir,  recursive = TRUE)
  unlink(index_file,  recursive = TRUE)
  unlink(output_dir,  recursive = TRUE)
})

testthat::test_that("lookup_by_id_R handles errors correctly", {
  skip_if_not_installed("arrow")

  expect_error(
    lookup_by_id_R(index_file = tempfile()),
    "'ids' must be provided"
  )

  expect_error(
    lookup_by_id_R(index_file = "/nonexistent/path", ids = "W1"),
    "Index file not found"
  )
})

# ── lookup_by_id() tests (binary wrapper, skipped if binary absent) ─────────

testthat::test_that("lookup_by_id (binary) extracts records into project_dir", {
  skip_if(Sys.which("openalex-snapshot") == "", "openalex-snapshot binary not found in PATH")
  skip_if(Sys.which("duckdb") == "",             "duckdb binary not found in PATH")
  skip_if_not_installed("arrow")

  root_dir    <- file.path(tempdir(), "test_oas_lookup_root")
  project_dir <- file.path(tempdir(), "test_oas_lookup_project")
  unlink(root_dir,    recursive = TRUE)
  unlink(project_dir, recursive = TRUE)

  # Create parquet corpus under <root>/parquet/authors/
  parquet_ds <- file.path(root_dir, "parquet", "authors")
  dir.create(parquet_ds, recursive = TRUE, showWarnings = FALSE)

  test_data <- data.frame(
    id    = c("https://openalex.org/A1", "https://openalex.org/A2", "https://openalex.org/A3"),
    name  = c("Alice", "Bob", "Carol"),
    stringsAsFactors = FALSE
  )
  arrow::write_parquet(test_data, file.path(parquet_ds, "test.parquet"))

  # Build index using the R implementation (places index at correct path for binary)
  build_corpus_index_R(corpus_dir = parquet_ds)

  # Now use the binary wrapper to extract
  result <- lookup_by_id(
    root_dir    = root_dir,
    ids         = c("https://openalex.org/A1", "https://openalex.org/A3"),
    project_dir = project_dir,
    data_sets   = "authors"
  )

  expect_equal(result, project_dir)
  expect_true(dir.exists(project_dir))
  extracted <- list.files(project_dir, pattern = "\\.parquet$", recursive = TRUE, full.names = TRUE)
  expect_true(length(extracted) >= 1)

  unlink(root_dir,    recursive = TRUE)
  unlink(project_dir, recursive = TRUE)
})

testthat::test_that("lookup_by_id errors when binary not found", {
  expect_error(
    lookup_by_id(
      root_dir    = tempdir(),
      ids         = "W1",
      project_dir = tempdir(),
      oas_bin     = "/nonexistent/openalex-snapshot"
    ),
    "binary was not found"
  )
})
