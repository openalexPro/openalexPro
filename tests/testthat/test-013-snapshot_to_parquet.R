library(testthat)

# Helper: create a tiny gzipped NDJSON file
write_gz <- function(path, lines) {
  gz_con <- gzfile(path, "w")
  writeLines(lines, gz_con)
  close(gz_con)
}

# ── snapshot_to_parquet_R() tests (pure-R, always run) ─────────────────────

testthat::test_that("snapshot_to_parquet_R converts JSON to Parquet (one parquet per gz)", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  snapshot_dir <- file.path(tempdir(), "test_snapshot")
  parquet_dir  <- file.path(tempdir(), "test_arrow")
  authors_dir  <- file.path(snapshot_dir, "data", "authors", "part_000")
  dir.create(authors_dir, recursive = TRUE, showWarnings = FALSE)

  write_gz(
    file.path(authors_dir, "test.gz"),
    c(
      '{"id":"https://openalex.org/A1","display_name":"Alice Smith","works_count":10}',
      '{"id":"https://openalex.org/A2","display_name":"Bob Jones","works_count":20}'
    )
  )

  unlink(parquet_dir, recursive = TRUE)
  snapshot_to_parquet_R(snapshot_dir = snapshot_dir, parquet_dir = parquet_dir, data_sets = "authors")

  output_dir    <- file.path(parquet_dir, "authors")
  expect_true(dir.exists(output_dir))
  parquet_files <- list.files(output_dir, pattern = "\\.parquet$", full.names = TRUE, recursive = TRUE)
  expect_equal(length(parquet_files), 1)
  expect_equal(basename(parquet_files[1]), "test.parquet")
  expect_true(grepl("part_000", parquet_files[1]))

  result <- arrow::read_parquet(parquet_files[1])
  expect_equal(nrow(result), 2)
  expect_true("id" %in% names(result))
  expect_true("display_name" %in% names(result))
  expect_setequal(result$id, c("https://openalex.org/A1", "https://openalex.org/A2"))

  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)
})

testthat::test_that("snapshot_to_parquet_R resumes by skipping already-converted files", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  snapshot_dir <- file.path(tempdir(), "test_snapshot_resume")
  parquet_dir  <- file.path(tempdir(), "test_arrow_resume")
  sources_dir  <- file.path(snapshot_dir, "data", "sources", "part_000")
  dir.create(sources_dir, recursive = TRUE, showWarnings = FALSE)

  write_gz(file.path(sources_dir, "file1.gz"), '{"id":"https://openalex.org/S1","display_name":"Journal One"}')
  write_gz(file.path(sources_dir, "file2.gz"), '{"id":"https://openalex.org/S2","display_name":"Journal Two"}')

  output_subdir <- file.path(parquet_dir, "sources", "part_000")
  dir.create(output_subdir, recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(
    data.frame(id = "https://openalex.org/S1", display_name = "Journal One", stringsAsFactors = FALSE),
    file.path(output_subdir, "file1.parquet")
  )

  expect_message(
    snapshot_to_parquet_R(snapshot_dir = snapshot_dir, parquet_dir = parquet_dir, data_sets = "sources"),
    "Skipping 1 already converted"
  )

  parquet_files <- sort(list.files(file.path(parquet_dir, "sources"), pattern = "\\.parquet$", recursive = TRUE))
  expect_equal(length(parquet_files), 2)
  expect_equal(parquet_files, c("part_000/file1.parquet", "part_000/file2.parquet"))

  result2 <- arrow::read_parquet(file.path(output_subdir, "file2.parquet"))
  expect_equal(nrow(result2), 1)
  expect_equal(result2$display_name, "Journal Two")

  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)
})

testthat::test_that("snapshot_to_parquet_R handles works with large JSON option", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  snapshot_dir <- file.path(tempdir(), "test_snapshot_works")
  parquet_dir  <- file.path(tempdir(), "test_arrow_works")
  works_dir    <- file.path(snapshot_dir, "data", "works", "part_000")
  dir.create(works_dir, recursive = TRUE, showWarnings = FALSE)

  write_gz(
    file.path(works_dir, "test.gz"),
    c(
      '{"id":"https://openalex.org/W1","doi":"https://doi.org/10.1000/test1","title":"Paper 1"}',
      '{"id":"https://openalex.org/W2","doi":"https://doi.org/10.1000/test2","title":"Paper 2"}'
    )
  )
  unlink(parquet_dir, recursive = TRUE)

  expect_message(
    snapshot_to_parquet_R(snapshot_dir = snapshot_dir, parquet_dir = parquet_dir, data_sets = "works"),
    "Processing works"
  )

  output_dir    <- file.path(parquet_dir, "works")
  expect_true(dir.exists(output_dir))
  parquet_files <- list.files(output_dir, pattern = "\\.parquet$", full.names = TRUE, recursive = TRUE)
  expect_equal(length(parquet_files), 1)
  result <- arrow::read_parquet(parquet_files[1])
  expect_equal(nrow(result), 2)
  expect_true("id" %in% names(result))
  expect_true("doi" %in% names(result))

  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)
})

testthat::test_that("snapshot_to_parquet_R handles schema unification across files", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  snapshot_dir <- file.path(tempdir(), "test_snapshot_schema")
  parquet_dir  <- file.path(tempdir(), "test_arrow_schema")
  ds_dir       <- file.path(snapshot_dir, "data", "topics", "part_000")
  dir.create(ds_dir, recursive = TRUE, showWarnings = FALSE)

  write_gz(file.path(ds_dir, "part1.gz"), '{"id":"https://openalex.org/T1","name":"Topic A"}')
  write_gz(file.path(ds_dir, "part2.gz"), '{"id":"https://openalex.org/T2","name":"Topic B","description":"Desc B"}')
  unlink(parquet_dir, recursive = TRUE)

  snapshot_to_parquet_R(snapshot_dir = snapshot_dir, parquet_dir = parquet_dir, data_sets = "topics")

  output_dir    <- file.path(parquet_dir, "topics")
  parquet_files <- sort(list.files(output_dir, pattern = "\\.parquet$", full.names = TRUE, recursive = TRUE))
  expect_equal(length(parquet_files), 2)
  r1 <- arrow::read_parquet(parquet_files[1])
  r2 <- arrow::read_parquet(parquet_files[2])
  expect_true("description" %in% names(r1))
  expect_true("description" %in% names(r2))

  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)
})

testthat::test_that("snapshot_to_parquet_R skips all when fully converted", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  snapshot_dir  <- file.path(tempdir(), "test_snapshot_done")
  parquet_dir   <- file.path(tempdir(), "test_arrow_done")
  ds_dir        <- file.path(snapshot_dir, "data", "funders", "part_000")
  dir.create(ds_dir, recursive = TRUE, showWarnings = FALSE)

  write_gz(file.path(ds_dir, "data.gz"), '{"id":"https://openalex.org/F1","display_name":"Funder One"}')

  output_subdir <- file.path(parquet_dir, "funders", "part_000")
  dir.create(output_subdir, recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(
    data.frame(id = "https://openalex.org/F1", display_name = "Funder One", stringsAsFactors = FALSE),
    file.path(output_subdir, "data.parquet")
  )

  expect_message(
    snapshot_to_parquet_R(snapshot_dir = snapshot_dir, parquet_dir = parquet_dir, data_sets = "funders"),
    "All files already converted"
  )

  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)
})

testthat::test_that("snapshot_to_parquet_R creates per-file and unified schema cache", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  snapshot_dir <- file.path(tempdir(), "test_snapshot_cache")
  parquet_dir  <- file.path(tempdir(), "test_arrow_cache")
  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)

  ds_dir <- file.path(snapshot_dir, "data", "authors", "part_000")
  dir.create(ds_dir, recursive = TRUE, showWarnings = FALSE)
  write_gz(file.path(ds_dir, "file1.gz"), '{"id":"A1","display_name":"Alice"}')
  write_gz(file.path(ds_dir, "file2.gz"), '{"id":"A2","display_name":"Bob"}')

  snapshot_to_parquet_R(snapshot_dir = snapshot_dir, parquet_dir = parquet_dir, data_sets = "authors")

  cache_dir <- file.path(parquet_dir, "authors", ".schema_cache")
  expect_true(dir.exists(cache_dir))

  all_csvs      <- list.files(cache_dir, pattern = "\\.csv$")
  per_file_csvs <- all_csvs[all_csvs != "unified_schema.csv"]
  expect_equal(length(per_file_csvs), 2L)
  expect_true(file.exists(file.path(cache_dir, "unified_schema.csv")))

  unified <- read.csv(file.path(cache_dir, "unified_schema.csv"), stringsAsFactors = FALSE)
  expect_true("col_name" %in% names(unified))
  expect_true("col_type" %in% names(unified))
  expect_true("id" %in% unified$col_name)

  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)
})

testthat::test_that("snapshot_to_parquet_R reuses unified schema cache on re-run", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  snapshot_dir <- file.path(tempdir(), "test_snapshot_cache2")
  parquet_dir  <- file.path(tempdir(), "test_arrow_cache2")
  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)

  ds_dir <- file.path(snapshot_dir, "data", "authors", "part_000")
  dir.create(ds_dir, recursive = TRUE, showWarnings = FALSE)
  write_gz(file.path(ds_dir, "file1.gz"), '{"id":"A1","display_name":"Alice"}')

  snapshot_to_parquet_R(snapshot_dir = snapshot_dir, parquet_dir = parquet_dir, data_sets = "authors")

  cache_dir   <- file.path(parquet_dir, "authors", ".schema_cache")
  unified_csv <- file.path(cache_dir, "unified_schema.csv")
  expect_true(file.exists(unified_csv))

  unlink(file.path(parquet_dir, "authors", "part_000"), recursive = TRUE)

  expect_message(
    snapshot_to_parquet_R(snapshot_dir = snapshot_dir, parquet_dir = parquet_dir, data_sets = "authors"),
    "Loaded cached unified schema"
  )

  pq_files <- list.files(file.path(parquet_dir, "authors"), pattern = "\\.parquet$", recursive = TRUE)
  expect_equal(length(pq_files), 1L)

  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)
})

testthat::test_that("snapshot_to_parquet_R stores works abstract_inverted_index as VARCHAR", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("jsonlite")

  snapshot_dir <- file.path(tempdir(), "test_snapshot_aii")
  parquet_dir  <- file.path(tempdir(), "test_arrow_aii")
  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)

  works_dir <- file.path(snapshot_dir, "data", "works", "part_000")
  dir.create(works_dir, recursive = TRUE, showWarnings = FALSE)

  write_gz(
    file.path(works_dir, "test.gz"),
    c(
      '{"id":"W1","title":"Paper 1","abstract_inverted_index":{"The":[0],"as":[1],"As":[2]}}',
      '{"id":"W2","title":"Paper 2","abstract_inverted_index":{"test":[0]}}'
    )
  )

  expect_no_error(
    snapshot_to_parquet_R(snapshot_dir = snapshot_dir, parquet_dir = parquet_dir, data_sets = "works")
  )

  pq_files <- list.files(file.path(parquet_dir, "works"), pattern = "\\.parquet$", full.names = TRUE, recursive = TRUE)
  expect_equal(length(pq_files), 1L)

  result <- arrow::read_parquet(pq_files[1])
  expect_true("abstract_inverted_index" %in% names(result))
  expect_true(is.character(result$abstract_inverted_index))

  parsed <- jsonlite::fromJSON(result$abstract_inverted_index[1])
  expect_true("as" %in% names(parsed))
  expect_true("As" %in% names(parsed))

  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)
})

testthat::test_that("snapshot_to_parquet_R preserves hive partition directory structure", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  snapshot_dir <- file.path(tempdir(), "test_snapshot_hive")
  parquet_dir  <- file.path(tempdir(), "test_arrow_hive")
  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)

  dir1 <- file.path(snapshot_dir, "data", "works", "updated_date=2024-01-01")
  dir2 <- file.path(snapshot_dir, "data", "works", "updated_date=2024-01-02")
  dir.create(dir1, recursive = TRUE, showWarnings = FALSE)
  dir.create(dir2, recursive = TRUE, showWarnings = FALSE)

  write_gz(file.path(dir1, "part_000.gz"), '{"id":"https://openalex.org/W1","title":"Paper Jan"}')
  write_gz(file.path(dir2, "part_000.gz"), '{"id":"https://openalex.org/W2","title":"Paper Feb"}')

  snapshot_to_parquet_R(snapshot_dir = snapshot_dir, parquet_dir = parquet_dir, data_sets = "works")

  output_dir    <- file.path(parquet_dir, "works")
  parquet_files <- sort(list.files(output_dir, pattern = "\\.parquet$", recursive = TRUE))
  expect_equal(length(parquet_files), 2)
  expect_true(any(grepl("updated_date=2024-01-01", parquet_files)))
  expect_true(any(grepl("updated_date=2024-01-02", parquet_files)))

  pq_full   <- list.files(output_dir, pattern = "\\.parquet$", recursive = TRUE, full.names = TRUE)
  all_rows  <- do.call(rbind, lapply(pq_full, arrow::read_parquet))
  expect_equal(nrow(all_rows), 2)
  expect_setequal(all_rows$title, c("Paper Jan", "Paper Feb"))

  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)
})

# ── snapshot_to_parquet() tests (binary wrapper, skipped if binary absent) ──

testthat::test_that("snapshot_to_parquet converts JSON to Parquet (root_dir mode)", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  root_dir <- file.path(tempdir(), "test_oas_root")
  unlink(root_dir, recursive = TRUE)

  ds_dir <- file.path(root_dir, "openalex-snapshot", "data", "authors", "part_000")
  dir.create(ds_dir, recursive = TRUE, showWarnings = FALSE)
  write_gz(
    file.path(ds_dir, "test.gz"),
    c(
      '{"id":"https://openalex.org/A1","display_name":"Alice Smith","works_count":10}',
      '{"id":"https://openalex.org/A2","display_name":"Bob Jones","works_count":20}'
    )
  )

  expect_no_error(
    snapshot_to_parquet(root_dir = root_dir, data_sets = "authors")
  )

  parquet_files <- list.files(
    file.path(root_dir, "parquet", "authors"),
    pattern    = "\\.parquet$",
    recursive  = TRUE,
    full.names = TRUE
  )
  expect_true(length(parquet_files) >= 1)

  result <- do.call(rbind, lapply(parquet_files, arrow::read_parquet))
  expect_true("id" %in% names(result))
  expect_true(nrow(result) >= 2)

  unlink(root_dir, recursive = TRUE)
})

testthat::test_that("snapshot_to_parquet errors when neither root_dir nor snapshot_dir/parquet_dir provided", {
  expect_error(
    snapshot_to_parquet(),
    "Provide either"
  )
})
