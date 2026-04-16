library(testthat)

testthat::test_that("snapshot_to_parquet converts JSON to Parquet (one parquet per gz)", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  # Create temporary snapshot directory structure
  snapshot_dir <- file.path(tempdir(), "test_snapshot")
  parquet_dir <- file.path(tempdir(), "test_arrow")

  # Create expected directory structure: data/<dataset>/part_000/*.gz
  authors_dir <- file.path(snapshot_dir, "data", "authors", "part_000")
  dir.create(authors_dir, recursive = TRUE, showWarnings = FALSE)

  # Create test NDJSON data (one JSON object per line)
  test_authors <- c(
    '{"id":"https://openalex.org/A1","display_name":"Alice Smith","works_count":10}',
    '{"id":"https://openalex.org/A2","display_name":"Bob Jones","works_count":20}'
  )

  # Write gzipped NDJSON file
  gz_file <- file.path(authors_dir, "test.gz")
  gz_con <- gzfile(gz_file, "w")
  writeLines(test_authors, gz_con)
  close(gz_con)

  # Ensure clean output directory
  unlink(parquet_dir, recursive = TRUE)

  # Run conversion
  snapshot_to_parquet(
    snapshot_dir = snapshot_dir,
    parquet_dir = parquet_dir,
    data_sets = "authors"
  )

  # Verify output exists
  output_dir <- file.path(parquet_dir, "authors")
  expect_true(dir.exists(output_dir))

  # Should have one parquet file per gz file, preserving subdirectory structure
  parquet_files <- list.files(output_dir, pattern = "\\.parquet$", full.names = TRUE, recursive = TRUE)
  expect_equal(length(parquet_files), 1)
  expect_equal(basename(parquet_files[1]), "test.parquet")
  # Subdirectory preserved
  expect_true(grepl("part_000", parquet_files[1]))

  # Read and verify the parquet data
  result <- arrow::read_parquet(parquet_files[1])
  expect_equal(nrow(result), 2)
  expect_true("id" %in% names(result))
  expect_true("display_name" %in% names(result))
  expect_setequal(
    result$id,
    c("https://openalex.org/A1", "https://openalex.org/A2")
  )

  # Clean up
  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir, recursive = TRUE)
})

testthat::test_that("snapshot_to_parquet resumes by skipping already-converted files", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  # Create temporary directories
  snapshot_dir <- file.path(tempdir(), "test_snapshot_resume")
  parquet_dir <- file.path(tempdir(), "test_arrow_resume")

  # Create snapshot structure with TWO gz files
  sources_dir <- file.path(snapshot_dir, "data", "sources", "part_000")
  dir.create(sources_dir, recursive = TRUE, showWarnings = FALSE)

  test_data1 <- '{"id":"https://openalex.org/S1","display_name":"Journal One"}'
  gz1 <- file.path(sources_dir, "file1.gz")
  gz_con <- gzfile(gz1, "w")
  writeLines(test_data1, gz_con)
  close(gz_con)

  test_data2 <- '{"id":"https://openalex.org/S2","display_name":"Journal Two"}'
  gz2 <- file.path(sources_dir, "file2.gz")
  gz_con <- gzfile(gz2, "w")
  writeLines(test_data2, gz_con)
  close(gz_con)

  # Pre-create output dir with one "already converted" parquet file
  # Must match the subdirectory structure (part_000/)
  output_dir <- file.path(parquet_dir, "sources")
  output_subdir <- file.path(output_dir, "part_000")
  dir.create(output_subdir, recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(
    data.frame(id = "https://openalex.org/S1", display_name = "Journal One", stringsAsFactors = FALSE),
    file.path(output_subdir, "file1.parquet")
  )

  # Run conversion - should skip file1.gz, only convert file2.gz
  expect_message(
    snapshot_to_parquet(
      snapshot_dir = snapshot_dir,
      parquet_dir = parquet_dir,
      data_sets = "sources"
    ),
    "Skipping 1 already converted"
  )

  # Should now have both parquet files (in subdirectory)
  parquet_files <- sort(list.files(output_dir, pattern = "\\.parquet$", recursive = TRUE))
  expect_equal(length(parquet_files), 2)
  expect_equal(parquet_files, c("part_000/file1.parquet", "part_000/file2.parquet"))

  # Verify file2 was actually converted correctly
  result2 <- arrow::read_parquet(file.path(output_subdir, "file2.parquet"))
  expect_equal(nrow(result2), 1)
  expect_equal(result2$display_name, "Journal Two")

  # Clean up
  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir, recursive = TRUE)
})

testthat::test_that("snapshot_to_parquet handles works with large JSON option", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  # Create temporary directories
  snapshot_dir <- file.path(tempdir(), "test_snapshot_works")
  parquet_dir <- file.path(tempdir(), "test_arrow_works")

  # Create works directory structure
  works_dir <- file.path(snapshot_dir, "data", "works", "part_000")
  dir.create(works_dir, recursive = TRUE, showWarnings = FALSE)

  # Create test works data
  test_works <- c(
    '{"id":"https://openalex.org/W1","doi":"https://doi.org/10.1000/test1","title":"Paper 1"}',
    '{"id":"https://openalex.org/W2","doi":"https://doi.org/10.1000/test2","title":"Paper 2"}'
  )

  gz_file <- file.path(works_dir, "test.gz")
  gz_con <- gzfile(gz_file, "w")
  writeLines(test_works, gz_con)
  close(gz_con)

  # Ensure clean output directory
  unlink(parquet_dir, recursive = TRUE)

  # Run conversion for works (should use maximum_object_size)
  expect_message(
    snapshot_to_parquet(
      snapshot_dir = snapshot_dir,
      parquet_dir = parquet_dir,
      data_sets = "works"
    ),
    "Processing works"
  )

  # Verify output
  output_dir <- file.path(parquet_dir, "works")
  expect_true(dir.exists(output_dir))

  parquet_files <- list.files(output_dir, pattern = "\\.parquet$", full.names = TRUE, recursive = TRUE)
  expect_equal(length(parquet_files), 1)

  result <- arrow::read_parquet(parquet_files[1])
  expect_equal(nrow(result), 2)
  expect_true("id" %in% names(result))
  expect_true("doi" %in% names(result))

  # Clean up
  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir, recursive = TRUE)
})

testthat::test_that("snapshot_to_parquet handles schema unification across files", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  # Create temporary directories
  snapshot_dir <- file.path(tempdir(), "test_snapshot_schema")
  parquet_dir <- file.path(tempdir(), "test_arrow_schema")

  # Create directory structure with files having different columns
  ds_dir <- file.path(snapshot_dir, "data", "topics", "part_000")
  dir.create(ds_dir, recursive = TRUE, showWarnings = FALSE)

  # File 1 has columns: id, name
  test1 <- '{"id":"https://openalex.org/T1","name":"Topic A"}'
  gz1 <- file.path(ds_dir, "part1.gz")
  gz_con <- gzfile(gz1, "w")
  writeLines(test1, gz_con)
  close(gz_con)

  # File 2 has columns: id, name, description (extra column)
  test2 <- '{"id":"https://openalex.org/T2","name":"Topic B","description":"Desc B"}'
  gz2 <- file.path(ds_dir, "part2.gz")
  gz_con <- gzfile(gz2, "w")
  writeLines(test2, gz_con)
  close(gz_con)

  # Ensure clean output
  unlink(parquet_dir, recursive = TRUE)

  # Run conversion — schema unification should handle mismatched columns
  snapshot_to_parquet(
    snapshot_dir = snapshot_dir,
    parquet_dir = parquet_dir,
    data_sets = "topics"
  )

  # Both files should be converted
  output_dir <- file.path(parquet_dir, "topics")
  parquet_files <- sort(list.files(output_dir, pattern = "\\.parquet$", full.names = TRUE, recursive = TRUE))
  expect_equal(length(parquet_files), 2)

  # Both should have all 3 columns (unified schema)
  r1 <- arrow::read_parquet(parquet_files[1])
  r2 <- arrow::read_parquet(parquet_files[2])
  expect_true("description" %in% names(r1))
  expect_true("description" %in% names(r2))

  # Clean up
  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir, recursive = TRUE)
})

testthat::test_that("snapshot_to_parquet skips all when fully converted", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  snapshot_dir <- file.path(tempdir(), "test_snapshot_done")
  parquet_dir <- file.path(tempdir(), "test_arrow_done")

  # Create snapshot structure
  ds_dir <- file.path(snapshot_dir, "data", "funders", "part_000")
  dir.create(ds_dir, recursive = TRUE, showWarnings = FALSE)

  test_data <- '{"id":"https://openalex.org/F1","display_name":"Funder One"}'
  gz_file <- file.path(ds_dir, "data.gz")
  gz_con <- gzfile(gz_file, "w")
  writeLines(test_data, gz_con)
  close(gz_con)

  # Pre-create the output parquet in the matching subdirectory
  output_subdir <- file.path(parquet_dir, "funders", "part_000")
  dir.create(output_subdir, recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(
    data.frame(id = "https://openalex.org/F1", display_name = "Funder One", stringsAsFactors = FALSE),
    file.path(output_subdir, "data.parquet")
  )

  # Should report all files converted
  expect_message(
    snapshot_to_parquet(
      snapshot_dir = snapshot_dir,
      parquet_dir = parquet_dir,
      data_sets = "funders"
    ),
    "All files already converted"
  )

  # Clean up
  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir, recursive = TRUE)
})

testthat::test_that("snapshot_to_parquet creates per-file and unified schema cache", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  snapshot_dir <- file.path(tempdir(), "test_snapshot_cache")
  parquet_dir  <- file.path(tempdir(), "test_arrow_cache")
  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)

  ds_dir <- file.path(snapshot_dir, "data", "authors", "part_000")
  dir.create(ds_dir, recursive = TRUE, showWarnings = FALSE)

  gz1 <- file.path(ds_dir, "file1.gz")
  gz_con <- gzfile(gz1, "w")
  writeLines('{"id":"A1","display_name":"Alice"}', gz_con)
  close(gz_con)

  gz2 <- file.path(ds_dir, "file2.gz")
  gz_con <- gzfile(gz2, "w")
  writeLines('{"id":"A2","display_name":"Bob"}', gz_con)
  close(gz_con)

  snapshot_to_parquet(
    snapshot_dir = snapshot_dir,
    parquet_dir  = parquet_dir,
    data_sets    = "authors"
  )

  cache_dir <- file.path(parquet_dir, ".authors_metadata", "schemata")
  expect_true(dir.exists(cache_dir))

  # Per-file schema CSVs (one per gz file, named <update_date>_<part_name>.csv)
  all_csvs      <- list.files(cache_dir, pattern = "\\.csv$")
  per_file_csvs <- all_csvs[all_csvs != "unified_schema.csv"]
  expect_equal(length(per_file_csvs), 2L)

  # Unified schema CSV
  expect_true(file.exists(file.path(cache_dir, "unified_schema.csv")))

  unified <- read.csv(file.path(cache_dir, "unified_schema.csv"), stringsAsFactors = FALSE)
  expect_true("col_name" %in% names(unified))
  expect_true("col_type" %in% names(unified))
  expect_true("id" %in% unified$col_name)

  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)
})

testthat::test_that("snapshot_to_parquet reuses unified schema cache on re-run", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  snapshot_dir <- file.path(tempdir(), "test_snapshot_cache2")
  parquet_dir  <- file.path(tempdir(), "test_arrow_cache2")
  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)

  ds_dir <- file.path(snapshot_dir, "data", "authors", "part_000")
  dir.create(ds_dir, recursive = TRUE, showWarnings = FALSE)

  gz1 <- file.path(ds_dir, "file1.gz")
  gz_con <- gzfile(gz1, "w")
  writeLines('{"id":"A1","display_name":"Alice"}', gz_con)
  close(gz_con)

  # First run: creates cache
  snapshot_to_parquet(
    snapshot_dir = snapshot_dir,
    parquet_dir  = parquet_dir,
    data_sets    = "authors"
  )

  cache_dir    <- file.path(parquet_dir, ".authors_metadata", "schemata")
  unified_csv  <- file.path(cache_dir, "unified_schema.csv")
  expect_true(file.exists(unified_csv))

  # Delete parquet files but keep schema cache
  parquet_files_dir <- file.path(parquet_dir, "authors", "part_000")
  unlink(parquet_files_dir, recursive = TRUE)

  # Second run: should load schema from cache (message contains "Loaded cached")
  expect_message(
    snapshot_to_parquet(
      snapshot_dir = snapshot_dir,
      parquet_dir  = parquet_dir,
      data_sets    = "authors"
    ),
    "Loaded cached unified schema"
  )

  # Parquet file should be recreated correctly
  pq_files <- list.files(
    file.path(parquet_dir, "authors"),
    pattern = "\\.parquet$",
    recursive = TRUE
  )
  expect_equal(length(pq_files), 1L)

  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)
})

testthat::test_that("snapshot_to_parquet stores works abstract_inverted_index as VARCHAR", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("jsonlite")

  snapshot_dir <- file.path(tempdir(), "test_snapshot_aii")
  parquet_dir  <- file.path(tempdir(), "test_arrow_aii")
  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)

  works_dir <- file.path(snapshot_dir, "data", "works", "part_000")
  dir.create(works_dir, recursive = TRUE, showWarnings = FALSE)

  # abstract_inverted_index with "as" and "As" as distinct JSON keys —
  # DuckDB cannot store this as STRUCT (case-folds field names), so we
  # expect it to be stored as a VARCHAR (raw JSON string) instead.
  test_works <- c(
    '{"id":"W1","title":"Paper 1","abstract_inverted_index":{"The":[0],"as":[1],"As":[2]}}',
    '{"id":"W2","title":"Paper 2","abstract_inverted_index":{"test":[0]}}'
  )
  gz_file <- file.path(works_dir, "test.gz")
  gz_con <- gzfile(gz_file, "w")
  writeLines(test_works, gz_con)
  close(gz_con)

  # Conversion should succeed (no error from duplicate JSON keys)
  expect_no_error(
    snapshot_to_parquet(
      snapshot_dir = snapshot_dir,
      parquet_dir  = parquet_dir,
      data_sets    = "works"
    )
  )

  pq_files <- list.files(
    file.path(parquet_dir, "works"),
    pattern = "\\.parquet$",
    full.names = TRUE,
    recursive = TRUE
  )
  expect_equal(length(pq_files), 1L)

  result <- arrow::read_parquet(pq_files[1])

  # Column must be present
  expect_true("abstract_inverted_index" %in% names(result))

  # Column must be stored as character (VARCHAR)
  expect_true(is.character(result$abstract_inverted_index))

  # Round-trip: case-sensitive keys "as" and "As" must be preserved
  parsed <- jsonlite::fromJSON(result$abstract_inverted_index[1])
  expect_true("as" %in% names(parsed))
  expect_true("As" %in% names(parsed))

  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir,  recursive = TRUE)
})

testthat::test_that("snapshot_to_parquet preserves hive partition directory structure", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  # This tests the real snapshot structure where multiple hive partitions
  # contain identically-named files (e.g., part_000.gz)
  snapshot_dir <- file.path(tempdir(), "test_snapshot_hive")
  parquet_dir <- file.path(tempdir(), "test_arrow_hive")
  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir, recursive = TRUE)

  # Create two hive partitions with same-named gz files
  dir1 <- file.path(snapshot_dir, "data", "works", "updated_date=2024-01-01")
  dir2 <- file.path(snapshot_dir, "data", "works", "updated_date=2024-01-02")
  dir.create(dir1, recursive = TRUE, showWarnings = FALSE)
  dir.create(dir2, recursive = TRUE, showWarnings = FALSE)

  # Both partitions have a file named part_000.gz (different data)
  gz1 <- file.path(dir1, "part_000.gz")
  gz_con <- gzfile(gz1, "w")
  writeLines('{"id":"https://openalex.org/W1","title":"Paper Jan"}', gz_con)
  close(gz_con)

  gz2 <- file.path(dir2, "part_000.gz")
  gz_con <- gzfile(gz2, "w")
  writeLines('{"id":"https://openalex.org/W2","title":"Paper Feb"}', gz_con)
  close(gz_con)

  # Run conversion
  snapshot_to_parquet(
    snapshot_dir = snapshot_dir,
    parquet_dir = parquet_dir,
    data_sets = "works"
  )

  # Both files should be converted without collision
  output_dir <- file.path(parquet_dir, "works")
  parquet_files <- sort(list.files(output_dir, pattern = "\\.parquet$", recursive = TRUE))
  expect_equal(length(parquet_files), 2)

  # Hive partition directories should be preserved
  expect_true(any(grepl("updated_date=2024-01-01", parquet_files)))
  expect_true(any(grepl("updated_date=2024-01-02", parquet_files)))

  # Both parquet files should contain the correct data
  pq_full <- list.files(output_dir, pattern = "\\.parquet$", recursive = TRUE, full.names = TRUE)
  all_rows <- do.call(rbind, lapply(pq_full, arrow::read_parquet))
  expect_equal(nrow(all_rows), 2)
  expect_setequal(all_rows$title, c("Paper Jan", "Paper Feb"))

  # Clean up
  unlink(snapshot_dir, recursive = TRUE)
  unlink(parquet_dir, recursive = TRUE)
})
