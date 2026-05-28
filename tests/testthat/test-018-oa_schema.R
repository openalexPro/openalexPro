## Tests for oa_schema.R -------------------------------------------------------

# ── oa_detect_entity() ────────────────────────────────────────────────────────

test_that("oa_detect_entity() identifies works", {
  expect_equal(
    oa_detect_entity(c("id", "title", "abstract_inverted_index", "authorships")),
    "works"
  )
})

test_that("oa_detect_entity() identifies authors", {
  expect_equal(oa_detect_entity(c("id", "display_name", "orcid", "works_count")), "authors")
})

test_that("oa_detect_entity() identifies sources", {
  expect_equal(oa_detect_entity(c("id", "display_name", "issn_l", "is_in_doaj")), "sources")
})

test_that("oa_detect_entity() identifies institutions", {
  expect_equal(oa_detect_entity(c("id", "display_name", "ror", "country_code")), "institutions")
})

test_that("oa_detect_entity() identifies concepts", {
  expect_equal(oa_detect_entity(c("id", "display_name", "wikidata", "level")), "concepts")
})

test_that("oa_detect_entity() returns NULL for unknown columns", {
  expect_null(oa_detect_entity(c("id", "display_name", "created_date")))
})

test_that("oa_detect_entity() returns NULL for empty input", {
  expect_null(oa_detect_entity(character(0L)))
})

# ── oa_load_baseline_schema() ─────────────────────────────────────────────────

test_that("oa_load_baseline_schema() loads bundled works schema", {
  df <- oa_load_baseline_schema("works")
  expect_s3_class(df, "data.frame")
  expect_true(all(c("col_name", "col_type") %in% names(df)))
  expect_gt(nrow(df), 10L)
  # abstract_inverted_index must be MAP, not JSON
  aii_row <- df[df$col_name == "abstract_inverted_index", , drop = FALSE]
  expect_equal(nrow(aii_row), 1L)
  expect_match(aii_row$col_type, "MAP")
  # issn inside source struct must be VARCHAR[] in primary_location type
  pl_row <- df[df$col_name == "primary_location", , drop = FALSE]
  expect_equal(nrow(pl_row), 1L)
  expect_match(pl_row$col_type, "issn VARCHAR\\[\\]")
  # entity attribute is set
  expect_equal(attr(df, "entity"), "works")
})

test_that("oa_load_baseline_schema() returns NULL for unknown entity", {
  expect_null(oa_load_baseline_schema("nonexistent_entity_xyz"))
})

test_that("oa_load_baseline_schema() loads all 21 bundled entities without error", {
  entities <- c(
    "authors", "awards", "concepts", "continents", "countries", "domains",
    "fields", "funders", "institution-types", "institutions", "keywords",
    "languages", "licenses", "publishers", "sdgs", "source-types", "sources",
    "subfields", "topics", "work-types", "works"
  )
  for (e in entities) {
    df <- oa_load_baseline_schema(e)
    expect_false(is.null(df), label = paste("schema for", e, "is not NULL"))
    expect_true(
      all(c("col_name", "col_type") %in% names(df)),
      label = paste(e, "has col_name and col_type columns")
    )
  }
})

# ── oa_cache_schema() ─────────────────────────────────────────────────────────

test_that("oa_cache_schema() errors on non-existent source directory", {
  expect_error(
    oa_cache_schema("/nonexistent/path/xyz"),
    "does not exist"
  )
})

test_that("oa_cache_schema() copies CSVs to user cache directory", {
  skip_if_not(
    dir.exists("/Volumes/openalex/openalex-snapshot_metadata"),
    "openalex snapshot volume not mounted"
  )

  tmp_cache <- tempfile("oa_schema_cache_test")
  on.exit(unlink(tmp_cache, recursive = TRUE), add = TRUE)

  # Monkey-patch R_user_dir to point at tmp_cache so we don't pollute
  # the real user cache during tests.
  withr::with_envvar(
    c(R_USER_CACHE_DIR = tmp_cache),
    {
      result <- oa_cache_schema(
        source    = "/Volumes/openalex/openalex-snapshot_metadata",
        entities  = c("works", "authors"),
        overwrite = TRUE,
        verbose   = FALSE
      )
      expect_type(result, "character")
      expect_true(file.exists(file.path(result, "works.csv")))
      expect_true(file.exists(file.path(result, "authors.csv")))
    }
  )
})

test_that("oa_cache_schema() skips existing files when overwrite = FALSE", {
  # Use a fake entity name ("test-entity") that never exists in the bundled
  # schemas, so we don't pollute the real user cache for "works", "authors", etc.
  fake_entity <- "test-entity-xyz"

  tmp_src    <- tempfile("oa_fake_meta")
  fake_schema_src <- file.path(tmp_src, fake_entity, "schemata", "unified_schema.csv")
  dir.create(dirname(fake_schema_src), recursive = TRUE)
  writeLines("col_name,col_type\nid,VARCHAR\ntitle,VARCHAR", fake_schema_src)
  on.exit(unlink(tmp_src, recursive = TRUE), add = TRUE)

  # Clean up the user cache entry we're about to create
  user_dest <- file.path(
    tools::R_user_dir("openalexPro", "cache"), "schemata",
    paste0(fake_entity, ".csv")
  )
  on.exit(unlink(user_dest), add = TRUE)

  msgs <- character(0L)
  withCallingHandlers(
    {
      # First call: write to user cache
      oa_cache_schema(tmp_src, entities = fake_entity, overwrite = TRUE,  verbose = FALSE)
      # Second call: file already exists, should print skip message
      oa_cache_schema(tmp_src, entities = fake_entity, overwrite = FALSE, verbose = TRUE)
    },
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  expect_true(any(grepl("already cached", msgs)))
  # Content must not have changed (still the fake CSV we wrote)
  expect_true(file.exists(user_dest))
})

# ── Integration: pro_request_parquet with schema = "auto" ────────────────────

test_that("pro_request_parquet applies baseline types for JSON columns", {
  skip_if_not_installed("duckdb")

  # Build a minimal synthetic API page that has null issn → DuckDB infers JSON
  tmp_json <- tempfile(fileext = ".json")
  tmp_out  <- tempfile("pq_out")
  on.exit({ unlink(tmp_json); unlink(tmp_out, recursive = TRUE) }, add = TRUE)

  # Keypaper-like page: source.issn is null for both records
  json_body <- paste0(
    '{"results": [',
    '{"id": "https://openalex.org/W1", "title": "A",',
    ' "primary_location": {"source": {"id": "S1", "issn": null, "issn_l": null}}}',
    '], "meta": {"count": 1, "page": 1, "per_page": 200, "next_cursor": null}}'
  )
  writeLines(json_body, tmp_json)

  # Rename so pro_request_parquet recognises it as a "results" page
  results_json <- file.path(dirname(tmp_json), "results_page_1.json")
  file.rename(tmp_json, results_json)
  on.exit(unlink(results_json), add = TRUE)

  pro_request_parquet(
    input_json  = dirname(results_json),
    output      = tmp_out,
    schema      = "auto",
    enrich      = FALSE,
    verbose     = FALSE,
    progress    = FALSE
  )

  pq_files <- list.files(tmp_out, pattern = "\\.parquet$", recursive = TRUE,
                          full.names = TRUE)
  expect_gte(length(pq_files), 1L)

  # Inspect the schema of the written parquet
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  sch <- DBI::dbGetQuery(
    con,
    sprintf("DESCRIBE SELECT * FROM read_parquet('%s')", pq_files[[1]])
  )

  # primary_location must be STRUCT (not JSON) — baseline applied
  pl_row <- sch[sch$column_name == "primary_location", , drop = FALSE]
  expect_equal(nrow(pl_row), 1L)
  # The type should be STRUCT(...) not JSON
  expect_false(
    identical(pl_row$column_type, "JSON"),
    label = "primary_location is not raw JSON"
  )
})
