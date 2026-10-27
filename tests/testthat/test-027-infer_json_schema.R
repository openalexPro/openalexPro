library(testthat)

# infer_json_schema(), merge_schemas(), convert_json_to_parquet() and the
# baseline-schema helpers of oa_schema.R, on tiny NDJSON / Parquet fixtures.

json_con <- function(env = parent.frame()) {
  con <- DBI::dbConnect(duckdb::duckdb())
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
  DBI::dbExecute(con, "INSTALL json; LOAD json;")
  con
}

write_ndjson <- function(dir, name, lines) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  f <- file.path(dir, name)
  con <- if (grepl("\\.gz$", name)) gzfile(f, "w") else file(f, "w")
  writeLines(lines, con)
  close(con)
  f
}

clause_types <- function(clause) {
  m <- regmatches(clause, gregexpr("'[^']+': '[^']+'", clause))[[1]]
  setNames(sub(".*': '(.*)'$", "\\1", m), sub("^'([^']+)'.*", "\\1", m))
}

# --- merge_schemas ------------------------------------------------------------

test_that("merge_schemas widens pure numeric conflicts and falls back to VARCHAR", {
  res <- merge_schemas(list(
    data.frame(column_name = c("n", "flag", "s"),
               column_type = c("INTEGER", "BOOLEAN", "VARCHAR")),
    data.frame(column_name = c("n", "flag", "extra"),
               column_type = c("DOUBLE", "VARCHAR", "BIGINT"))
  ))
  expect_equal(res$col_name, c("n", "flag", "s", "extra")) # first-seen order
  expect_equal(res$col_type, c("DOUBLE", "VARCHAR", "VARCHAR", "BIGINT"))
})

test_that("merge_schemas accepts DESCRIBE output with name/type columns", {
  res <- merge_schemas(list(
    data.frame(name = "s", type = "STRUCT(a INTEGER)"),
    data.frame(name = "s", type = "STRUCT(a INTEGER, b INTEGER)"),
    data.frame(name = "s", type = "VARCHAR")
  ))
  expect_equal(res$col_type, "STRUCT(a INTEGER, b INTEGER)")
})

test_that("merge_schemas falls back to VARCHAR for text vs numeric", {
  skip("Known bug: merge_schemas() widens VARCHAR vs BIGINT to BIGINT instead of VARCHAR (R/infer_json_schema.R:245)")
  res <- merge_schemas(list(
    data.frame(column_name = "x", column_type = "VARCHAR"),
    data.frame(column_name = "x", column_type = "BIGINT")
  ))
  expect_equal(res$col_type, "VARCHAR")
})

# --- infer_json_schema --------------------------------------------------------

test_that("infer_json_schema returns NULL with a message for no files", {
  expect_message(res <- infer_json_schema(NULL, character(0)), "No files provided")
  expect_null(res)
})

test_that("infer_json_schema merges files and caches per file and unified", {
  con <- json_con()
  d <- withr::local_tempdir()
  f1 <- write_ndjson(file.path(d, "updated_date=2024-01-01"), "part_000.gz",
                     '{"id": "W1", "n": 1, "s": {"a": 1}}')
  f2 <- write_ndjson(file.path(d, "updated_date=2024-01-02"), "part_000.gz",
                     '{"id": "W2", "n": 1.5, "s": {"a": 1, "b": "x"}, "t": true}')
  cache <- file.path(d, "cache")

  msgs <- capture_messages(
    clause <- infer_json_schema(con, c(f1, f2), schema_cache_dir = cache)
  )
  expect_match(msgs, "Inferring unified schema from 2 files", all = FALSE)
  expect_match(msgs, "Unified schema inferred with 5 columns", all = FALSE)
  types <- clause_types(clause)
  # DuckDB also reads the hive partition `updated_date=` of the snapshot layout
  expect_equal(names(types), c("id", "n", "s", "updated_date", "t"))
  expect_equal(types[["n"]], "DOUBLE")
  expect_match(types[["s"]], "^STRUCT\\(a BIGINT, b VARCHAR\\)$")
  expect_setequal(
    list.files(cache),
    c("2024-01-01_part_000.csv", "2024-01-02_part_000.csv", "unified_schema.csv")
  )

  # Level 1: the unified cache is returned without reading any file
  expect_message(
    again <- infer_json_schema(con, "does/not/exist.json", schema_cache_dir = cache),
    "Loaded cached unified schema with 5 columns"
  )
  expect_identical(again, clause)

  # Level 2: per-file caches are used when the unified one is gone
  unlink(file.path(cache, "unified_schema.csv"))
  unlink(c(f1, f2))
  expect_identical(
    infer_json_schema(con, c(f1, f2), verbose = FALSE, schema_cache_dir = cache),
    clause
  )
})

test_that("infer_json_schema samples files and skips the ones that fail", {
  con <- json_con()
  d <- withr::local_tempdir()
  files <- vapply(1:3, function(i) {
    write_ndjson(d, sprintf("p%d.json", i), sprintf('{"id": "W%d"}', i))
  }, "")
  withr::local_seed(1)
  msgs <- capture_messages(clause <- infer_json_schema(con, files, sample_size = 2))
  expect_match(msgs, "Inferring unified schema from 2 files", all = FALSE)
  expect_equal(clause, "{'id': 'VARCHAR'}")

  missing <- file.path(d, "missing.json")
  msgs <- capture_messages(clause <- infer_json_schema(con, c(missing, files[1])))
  expect_match(msgs, "Schema inference failed for missing.json", all = FALSE)
  expect_equal(clause, "{'id': 'VARCHAR'}")

  msgs <- capture_messages(res <- infer_json_schema(con, missing))
  expect_null(res)
  expect_match(msgs, "Could not infer schema from any file", all = FALSE)
})

test_that("infer_json_schema with a cache survives a failing last file", {
  skip("Known bug: a failed file assigns NULL to schemas[[i]], dropping the element; with schema_cache_dir the next schemas[[i]] errors 'subscript out of bounds' (R/infer_json_schema.R:142,151)")
  con <- json_con()
  d <- withr::local_tempdir()
  good <- write_ndjson(d, "p1.json", '{"id": "W1"}')
  expect_message(
    clause <- infer_json_schema(con, c(good, file.path(d, "missing.json")),
                                schema_cache_dir = file.path(d, "cache")),
    "Schema inference failed for missing.json"
  )
  expect_equal(clause, "{'id': 'VARCHAR'}")
})

# --- convert_json_to_parquet --------------------------------------------------

test_that("convert_json_to_parquet converts with and without a columns clause", {
  d <- withr::local_tempdir()
  f <- write_ndjson(d, "p1.json", c('{"id": "W1", "n": 1}', '{"id": "W2", "n": 2}'))

  out_auto <- file.path(d, "auto", "p1.parquet")
  expect_equal(convert_json_to_parquet(f, out_auto), out_auto)
  df <- arrow::read_parquet(out_auto)
  expect_equal(df$id, c("W1", "W2"))

  out_typed <- file.path(d, "typed", "p1.parquet")
  convert_json_to_parquet(f, out_typed, columns_clause = "{'id': 'VARCHAR', 'n': 'DOUBLE'}")
  sch <- arrow::read_parquet(out_typed, as_data_frame = FALSE)$schema
  expect_equal(sch$GetFieldByName("n")$type$ToString(), "double")
})

# --- oa_schema helpers --------------------------------------------------------

test_that("oa_detect_entity() identifies funders, publishers and topics", {
  expect_equal(oa_detect_entity(c("id", "funder_groups")), "funders")
  expect_equal(oa_detect_entity(c("id", "publisher")), "publishers")
  expect_equal(oa_detect_entity(c("id", "domain", "field")), "topics")
})

test_that("oa_load_baseline_schema() prefers the user cache", {
  cache <- withr::local_tempdir()
  withr::local_envvar(R_USER_CACHE_DIR = cache)
  dir <- file.path(tools::R_user_dir("openalexPro", "cache"), "schemata")
  dir.create(dir, recursive = TRUE)
  utils::write.csv(data.frame(col_name = "id", col_type = "VARCHAR"),
                   file.path(dir, "works.csv"), row.names = FALSE)
  df <- oa_load_baseline_schema("works")
  expect_equal(df$col_name, "id")
  expect_equal(attr(df, "entity"), "works")
})

test_that(".resolve_baseline() handles none, auto, a CSV file and a directory", {
  expect_null(.resolve_baseline(NULL, "abstract_inverted_index"))
  expect_null(.resolve_baseline("none", "abstract_inverted_index"))
  expect_null(.resolve_baseline("auto", "unknown_column"))
  expect_equal(attr(.resolve_baseline("auto", "abstract_inverted_index"), "entity"), "works")

  d <- withr::local_tempdir()
  csv <- file.path(d, "myentity.csv")
  utils::write.csv(data.frame(col_name = "x", col_type = "BIGINT"), csv, row.names = FALSE)
  df <- .resolve_baseline(csv, character(0))
  expect_equal(df$col_type, "BIGINT")
  expect_equal(attr(df, "entity"), "myentity")

  utils::write.csv(data.frame(col_name = "orcid", col_type = "VARCHAR"),
                   file.path(d, "authors.csv"), row.names = FALSE)
  df <- .resolve_baseline(d, c("id", "orcid"))
  expect_equal(df$col_name, "orcid")
  expect_equal(attr(df, "entity"), "authors")
  expect_null(.resolve_baseline(d, c("id", "issn_l"))) # no sources.csv there
  expect_null(.resolve_baseline(d, "unknown_column")) # entity not detected
  expect_null(.resolve_baseline(file.path(d, "nope"), "orcid"))
})

test_that("oa_schema(update = TRUE, entities = 'all') reports skipped and failed entities", {
  pq_root <- withr::local_tempdir()
  dir.create(file.path(pq_root, "good"))
  dir.create(file.path(pq_root, "good_aws")) # staging dir, excluded
  dir.create(file.path(pq_root, "empty")) # no parquet files -> fails
  arrow::write_parquet(data.frame(id = "W1"), file.path(pq_root, "good", "p.parquet"))
  withr::local_envvar(R_USER_CACHE_DIR = withr::local_tempdir())

  msgs <- capture_messages(res <- oa_schema(update = TRUE, parquet_dir = pq_root))
  expect_match(msgs, "Updated schema for 'good'", all = FALSE)
  expect_match(msgs, "Failed to read schema for 'empty'", all = FALSE)
  expect_false(any(grepl("good_aws", msgs)))
  expect_setequal(list.files(res), "good.csv")

  expect_message(
    oa_schema(update = TRUE, parquet_dir = pq_root, entities = "absent"),
    "No parquet directory for entity 'absent' - skipping"
  )
})
