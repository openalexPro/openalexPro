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

# ── oa_schema() ───────────────────────────────────────────────────────────────

test_that("oa_schema(update = FALSE) returns bundled schema data frame", {
  df <- oa_schema(entity = "works", update = FALSE)
  expect_s3_class(df, "data.frame")
  expect_true(all(c("col_name", "col_type") %in% names(df)))
  expect_gt(nrow(df), 10L)
})

test_that("oa_schema(update = FALSE) returns NULL for unknown entity", {
  expect_null(oa_schema(entity = "nonexistent_xyz", update = FALSE))
})

test_that("oa_schema(update = FALSE) requires entity argument", {
  expect_error(oa_schema(update = FALSE), "entity")
})

test_that("oa_schema(update = TRUE) requires parquet_dir", {
  expect_error(oa_schema(update = TRUE), "parquet_dir")
})

test_that("oa_schema(update = TRUE) errors on non-existent parquet_dir", {
  expect_error(
    oa_schema(update = TRUE, parquet_dir = "/nonexistent/path/xyz"),
    "does not exist"
  )
})

test_that("oa_schema(update = TRUE) reads schema from parquet files and caches", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  # Build a minimal fake parquet corpus: parquet_dir/myentity/part_000.parquet
  pq_root  <- tempfile("oa_schema_pq_root")
  pq_dir   <- file.path(pq_root, "myentity")
  dir.create(pq_dir, recursive = TRUE)
  on.exit(unlink(pq_root, recursive = TRUE), add = TRUE)

  arrow::write_parquet(
    data.frame(id = "W1", title = "Test", stringsAsFactors = FALSE),
    file.path(pq_dir, "part_000.parquet")
  )

  # Redirect user cache so real cache is not polluted
  tmp_cache <- tempfile("oa_schema_cache")
  on.exit(unlink(tmp_cache, recursive = TRUE), add = TRUE)

  withr::with_envvar(
    c(R_USER_CACHE_DIR = tmp_cache),
    {
      result <- oa_schema(
        update      = TRUE,
        parquet_dir = pq_root,
        entities    = "myentity",
        overwrite   = TRUE,
        verbose     = FALSE
      )
      expect_type(result, "character")
      cached_csv <- file.path(result, "myentity.csv")
      expect_true(file.exists(cached_csv))
      df <- utils::read.csv(cached_csv, stringsAsFactors = FALSE)
      expect_true(all(c("col_name", "col_type") %in% names(df)))
      expect_true("id" %in% df$col_name)
    }
  )
})

test_that("oa_schema(update = TRUE) skips existing when overwrite = FALSE", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")

  pq_root <- tempfile("oa_schema_skip_pq")
  pq_dir  <- file.path(pq_root, "skipentity")
  dir.create(pq_dir, recursive = TRUE)
  on.exit(unlink(pq_root, recursive = TRUE), add = TRUE)
  arrow::write_parquet(
    data.frame(id = "W1", stringsAsFactors = FALSE),
    file.path(pq_dir, "part_000.parquet")
  )

  tmp_cache <- tempfile("oa_schema_skip_cache")
  on.exit(unlink(tmp_cache, recursive = TRUE), add = TRUE)

  msgs <- character(0L)
  withr::with_envvar(
    c(R_USER_CACHE_DIR = tmp_cache),
    {
      oa_schema(update = TRUE, parquet_dir = pq_root, entities = "skipentity",
                overwrite = TRUE, verbose = FALSE)
      withCallingHandlers(
        oa_schema(update = TRUE, parquet_dir = pq_root, entities = "skipentity",
                  overwrite = FALSE, verbose = TRUE),
        message = function(m) {
          msgs <<- c(msgs, conditionMessage(m))
          invokeRestart("muffleMessage")
        }
      )
    }
  )
  expect_true(any(grepl("already cached", msgs)))
})

# ── Integration: pro_request_parquet with schema = "auto" ────────────────────

test_that("pro_request_parquet applies baseline types for JSON columns", {
  skip_if_not_installed("duckdb")

  # Build a minimal synthetic API page that has null issn -> DuckDB infers JSON
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
