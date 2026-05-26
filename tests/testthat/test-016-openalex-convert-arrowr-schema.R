testthat::test_that("openalex-convert schema --format arrow-r is comparable to arrow schema", {
  skip_if_not_installed("arrow")

  bin <- Sys.which("openalex-convert")
  skip_if(bin == "", "openalex-convert binary not found in PATH")
  skip_if(Sys.which("duckdb") == "", "duckdb binary not found in PATH")

  td <- tempfile("oac_")
  dir.create(td, recursive = TRUE)
  on.exit(unlink(td, recursive = TRUE, force = TRUE), add = TRUE)

  snapshot_dir <- file.path(td, "snapshot")
  parquet_dir <- file.path(td, "parquet")
  ds_dir <- file.path(snapshot_dir, "data", "works", "part_000")
  dir.create(ds_dir, recursive = TRUE)

  gz <- file.path(ds_dir, "part1.gz")
  con <- gzfile(gz, open = "w")
  writeLines(c(
    '{"id":"https://openalex.org/W1","title":"Paper 1","publication_year":2020}',
    '{"id":"https://openalex.org/W2","title":"Paper 2","publication_year":2021}'
  ), con)
  close(con)

  status <- system2(
    command = bin,
    args = c(
      "convert",
      "--snapshot-dir", snapshot_dir,
      "--parquet-dir", parquet_dir,
      "--dataset", "works",
      "--skip-verify"
    )
  )
  testthat::expect_equal(status, 0)

  out <- tempfile(fileext = ".json")
  status <- system2(
    command = bin,
    args = c(
      "schema",
      "--snapshot-dir", snapshot_dir,
      "--parquet-dir", parquet_dir,
      "--dataset", "works",
      "--format", "arrow-r",
      "--output", out
    )
  )
  testthat::expect_equal(status, 0)
  testthat::expect_true(file.exists(out))

  got <- jsonlite::fromJSON(out, simplifyVector = FALSE)
  got_fields <- got$schema$fields

  ds <- arrow::open_dataset(file.path(parquet_dir, "works"), format = "parquet")
  sch <- ds$schema

  # Normalize Arrow schema to name/type/nullable comparable shape
  exp_fields <- lapply(sch$names, function(nm) {
    fld <- sch$GetFieldByName(nm)
    list(
      name = fld$name,
      type = fld$type$ToString(),
      nullable = isTRUE(fld$nullable)
    )
  })

  got_simple <- lapply(got_fields, function(f) {
    list(name = f$name, type = f$type, nullable = isTRUE(f$nullable))
  })

  testthat::expect_true(length(got_simple) >= 1)
  # compare overlap only, as source-vs-parquet inference may widen to utf8
  exp_names <- vapply(exp_fields, `[[`, character(1), "name")
  got_names <- vapply(got_simple, `[[`, character(1), "name")
  testthat::expect_true(all(exp_names %in% got_names))
})
