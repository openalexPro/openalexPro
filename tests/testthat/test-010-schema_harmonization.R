test_that("schema harmonization prevents read errors from type conflicts", {
  # This test uses fixtures with three different schemas for the same field:

# - File 1: apc_paid = null (inferred as NULL/VARCHAR)
  # - File 2: apc_paid = struct with 3 fields {value, currency, value_usd}
  # - File 3: apc_paid = struct with 4 fields {value, currency, value_usd, provenance}
  #
  # Without unified schema inference, each file would get a different Parquet
  # schema, and reading them together would fail with errors like:
# "NotImplemented: Unsupported cast from string to struct"

  # Setup: copy fixtures to temp directory
  input_jsonl <- file.path(tempdir(), "schema_conflict_jsonl")
  if (dir.exists(input_jsonl)) unlink(input_jsonl, recursive = TRUE)
  dir.create(input_jsonl, recursive = TRUE)

  # fixtures are in tests/fixtures, not tests/testthat/fixtures
  fixture_dir <- testthat::test_path("..", "fixtures", "schema_conflict_jsonl")
  file.copy(
    list.files(fixture_dir, full.names = TRUE),
    input_jsonl
  )

  output_parquet <- file.path(tempdir(), "schema_conflict_parquet")
  if (dir.exists(output_parquet)) unlink(output_parquet, recursive = TRUE)

  # Convert with unified schema inference (the new default behavior)
  result <- suppressWarnings(pro_request_jsonl_parquet(
    input_jsonl = input_jsonl,
    output = output_parquet,
    overwrite = TRUE,
    verbose = FALSE,
  ))

  expect_true(dir.exists(output_parquet))

  # The key test: reading the combined parquet should NOT error
  expect_no_error({
    ds <- arrow::open_dataset(output_parquet)
    df <- dplyr::collect(ds)
  })

  # Verify we got all 3 records (one per file)
  expect_equal(nrow(df), 3)

  # Verify the data is present
  expect_true("id" %in% names(df))
  expect_true("title" %in% names(df))
  expect_true("apc_paid" %in% names(df))

  # Cleanup
  unlink(input_jsonl, recursive = TRUE)
  unlink(output_parquet, recursive = TRUE)
})

test_that("schema harmonization handles struct with different fields across files", {
  # This test specifically checks that structs with different fields
  # in different files are unified correctly

  input_jsonl <- file.path(tempdir(), "struct_fields_jsonl")
  if (dir.exists(input_jsonl)) unlink(input_jsonl, recursive = TRUE)
  dir.create(input_jsonl, recursive = TRUE)

  # File 1: metadata has fields {count, source}
  writeLines(
    '{"id":"W1","title":"Article 1","page":"1","metadata":{"count":10,"source":"crossref"}}',
    file.path(input_jsonl, "results_page_1.json")
  )

  # File 2: metadata has fields {count, author} - different field!
  writeLines(
    '{"id":"W2","title":"Article 2","page":"2","metadata":{"count":20,"author":"Smith"}}',
    file.path(input_jsonl, "results_page_2.json")
  )

  # File 3: metadata has fields {count, source, author, extra} - superset
  writeLines(
    '{"id":"W3","title":"Article 3","page":"3","metadata":{"count":30,"source":"pubmed","author":"Jones","extra":"info"}}',
    file.path(input_jsonl, "results_page_3.json")
  )

  output_parquet <- file.path(tempdir(), "struct_fields_parquet")
  if (dir.exists(output_parquet)) unlink(output_parquet, recursive = TRUE)

  result <- suppressWarnings(pro_request_jsonl_parquet(
    input_jsonl = input_jsonl,
    output = output_parquet,
    overwrite = TRUE,
    verbose = FALSE,
  ))

  # Reading should not error - unified schema should include all fields
  expect_no_error({
    ds <- arrow::open_dataset(output_parquet)
    df <- dplyr::collect(ds)
  })

  expect_equal(nrow(df), 3)

  # Cleanup
  unlink(input_jsonl, recursive = TRUE)
  unlink(output_parquet, recursive = TRUE)
})

test_that("schema harmonization handles null vs struct conflicts", {
  # This test checks the common case where a field is null in some records
  # but a struct in others (like apc_paid in OpenAlex)

  input_jsonl <- file.path(tempdir(), "null_struct_jsonl")
  if (dir.exists(input_jsonl)) unlink(input_jsonl, recursive = TRUE)
  dir.create(input_jsonl, recursive = TRUE)

  # File 1: apc_paid is null
  writeLines(
    '{"id":"W1","title":"No APC","page":"1","apc_paid":null}',
    file.path(input_jsonl, "results_page_1.json")
  )

  # File 2: apc_paid is a struct
  writeLines(
    '{"id":"W2","title":"With APC","page":"2","apc_paid":{"value":1000,"currency":"USD"}}',
    file.path(input_jsonl, "results_page_2.json")
  )

  # File 3: apc_paid is a struct with more fields
  writeLines(
    '{"id":"W3","title":"With full APC","page":"3","apc_paid":{"value":2000,"currency":"EUR","value_usd":2200}}',
    file.path(input_jsonl, "results_page_3.json")
  )

  output_parquet <- file.path(tempdir(), "null_struct_parquet")
  if (dir.exists(output_parquet)) unlink(output_parquet, recursive = TRUE)

  result <- suppressWarnings(pro_request_jsonl_parquet(
    input_jsonl = input_jsonl,
    output = output_parquet,
    overwrite = TRUE,
    verbose = FALSE,
  ))

  expect_no_error({
    ds <- arrow::open_dataset(output_parquet)
    df <- dplyr::collect(ds)
  })

  expect_equal(nrow(df), 3)

  # Cleanup
  unlink(input_jsonl, recursive = TRUE)
  unlink(output_parquet, recursive = TRUE)
})

test_that("schema harmonization handles nested struct variations", {
  # Test deeply nested structs with varying schemas

  input_jsonl <- file.path(tempdir(), "nested_struct_jsonl")
  if (dir.exists(input_jsonl)) unlink(input_jsonl, recursive = TRUE)
  dir.create(input_jsonl, recursive = TRUE)

  # File 1: primary_location with source as null
  writeLines(
    '{"id":"W1","title":"Article 1","page":"1","primary_location":{"is_oa":true,"source":null}}',
    file.path(input_jsonl, "results_page_1.json")
  )

  # File 2: primary_location with source as struct
  writeLines(
    '{"id":"W2","title":"Article 2","page":"2","primary_location":{"is_oa":false,"source":{"id":"S1","name":"Journal A"}}}',
    file.path(input_jsonl, "results_page_2.json")
  )

  # File 3: primary_location with source as struct with extra fields
  writeLines(
    '{"id":"W3","title":"Article 3","page":"3","primary_location":{"is_oa":true,"source":{"id":"S2","name":"Journal B","issn":"1234-5678"}}}',
    file.path(input_jsonl, "results_page_3.json")
  )

  output_parquet <- file.path(tempdir(), "nested_struct_parquet")
  if (dir.exists(output_parquet)) unlink(output_parquet, recursive = TRUE)

  result <- suppressWarnings(pro_request_jsonl_parquet(
    input_jsonl = input_jsonl,
    output = output_parquet,
    overwrite = TRUE,
    verbose = FALSE,
  ))

  expect_no_error({
    ds <- arrow::open_dataset(output_parquet)
    df <- dplyr::collect(ds)
  })

  expect_equal(nrow(df), 3)

  # Cleanup
  unlink(input_jsonl, recursive = TRUE)
  unlink(output_parquet, recursive = TRUE)
})

test_that("a query with no results converts to a zero-row dataset", {
  # `"results": []` gives DuckDB nothing to infer a struct from; the columns
  # come from the baseline of the entity named in `_query.json`.
  input_json <- withr::local_tempdir()
  output <- file.path(withr::local_tempdir(), "parquet")
  file.copy(
    testthat::test_path("..", "fixtures", "keypaper_json", "results_page_2.json"),
    file.path(input_json, "results_page_1.json")
  )
  jsonlite::write_json(
    list(query_url = "https://api.openalex.org/", oqo = list(get_rows = "works")),
    file.path(input_json, "_query.json"), auto_unbox = TRUE
  )

  pro_request_parquet(input_json, output, progress = FALSE, verbose = FALSE)

  ds <- arrow::open_dataset(output)
  expect_equal(nrow(ds), 0L)
  expect_true(all(c("id", "doi", "title", "abstract", "citation", "page") %in% names(ds)))
})
