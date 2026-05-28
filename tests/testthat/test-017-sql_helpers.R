## Tests for sql_helpers.R -------------------------------------------------------

# ── oa_works_abstract_sql() ────────────────────────────────────────────────────

test_that("oa_works_abstract_sql() returns a non-empty character scalar", {
  sql <- oa_works_abstract_sql()
  expect_type(sql, "character")
  expect_length(sql, 1L)
  expect_gt(nchar(sql), 0L)
})

test_that("oa_works_abstract_sql() expression contains the double JSON cast", {
  sql <- oa_works_abstract_sql()
  # Must normalise via ::JSON::MAP so the expression handles STRUCT inputs
  expect_match(sql, "::JSON::MAP\\(VARCHAR, BIGINT\\[\\]\\)", fixed = FALSE)
})

test_that("oa_works_abstract_sql() expression evaluates to NULL for NULL input", {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  abstract_sql <- oa_works_abstract_sql()
  result <- DBI::dbGetQuery(
    con,
    sprintf("SELECT (%s) AS abstract FROM (SELECT NULL AS abstract_inverted_index)", abstract_sql)
  )
  expect_true(is.na(result$abstract))
})

test_that("oa_works_abstract_sql() reconstructs abstract from MAP input", {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  abstract_sql <- oa_works_abstract_sql()
  # MAP(VARCHAR, BIGINT[]) input: {"Hello": [0], "world": [1]}
  result <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT (%s) AS abstract
       FROM (SELECT MAP {'Hello': [0], 'world': [1]} AS abstract_inverted_index)",
      abstract_sql
    )
  )
  expect_equal(result$abstract, "Hello world")
})

test_that("oa_works_abstract_sql() reconstructs abstract from STRUCT input", {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  abstract_sql <- oa_works_abstract_sql()
  # STRUCT input — what DuckDB infers when no duplicate keys are present
  result <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT (%s) AS abstract
       FROM (SELECT {'Hello': [0], 'world': [1]} AS abstract_inverted_index)",
      abstract_sql
    )
  )
  expect_equal(result$abstract, "Hello world")
})

test_that("oa_works_abstract_sql() reconstructs abstract from VARCHAR (raw JSON) input", {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  abstract_sql <- oa_works_abstract_sql()
  result <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT (%s) AS abstract
       FROM (SELECT '{\"Hello\": [0], \"world\": [1]}'::VARCHAR AS abstract_inverted_index)",
      abstract_sql
    )
  )
  expect_equal(result$abstract, "Hello world")
})

test_that("oa_works_abstract_sql() sorts positions correctly across multiple words", {
  skip_if_not_installed("duckdb")
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  abstract_sql <- oa_works_abstract_sql()
  # "quick" appears at positions 1 and 3; "brown" at 0 and 2
  result <- DBI::dbGetQuery(
    con,
    sprintf(
      "SELECT (%s) AS abstract
       FROM (SELECT MAP {'brown': [0, 2], 'quick': [1, 3]} AS abstract_inverted_index)",
      abstract_sql
    )
  )
  expect_equal(result$abstract, "brown quick brown quick")
})

# ── oa_works_citation_sql() ────────────────────────────────────────────────────

test_that("oa_works_citation_sql() returns a non-empty character scalar", {
  sql <- oa_works_citation_sql()
  expect_type(sql, "character")
  expect_length(sql, 1L)
  expect_gt(nchar(sql), 0L)
})

test_that("oa_works_citation_sql() contains authorships and publication_year", {
  sql <- oa_works_citation_sql()
  expect_match(sql, "authorships")
  expect_match(sql, "publication_year")
  expect_match(sql, "n\\.d\\.")
})

# ── oa_normalize_duckdb_type() ────────────────────────────────────────────────

test_that("oa_normalize_duckdb_type() uppercases SQL keywords", {
  expect_equal(oa_normalize_duckdb_type("varchar"),  "VARCHAR")
  expect_equal(oa_normalize_duckdb_type("struct(id varchar, count bigint)"),
               "STRUCT(id VARCHAR, count BIGINT)")
  expect_equal(oa_normalize_duckdb_type("map(varchar, bigint[])"),
               "MAP(VARCHAR, BIGINT[])")
})

test_that("oa_normalize_duckdb_type() preserves field identifier case", {
  # 'display_name' is not a keyword — must stay lowercase
  expect_equal(
    oa_normalize_duckdb_type("struct(display_name varchar)"),
    "STRUCT(display_name VARCHAR)"
  )
})
