# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## What This Package Does

**openalexPro** is an R package for large-scale, on-disk bibliographic
data retrieval from the [OpenAlex](https://openalex.org) API. Unlike the
simpler `openalexR`, it processes data page-by-page rather than loading
everything into RAM, enabling retrieval of millions of records without
memory exhaustion.

The core pipeline has three stages, each saving intermediate results to
disk:

    pro_request()               → JSON pages from OpenAlex API
    pro_request_jsonl()         → JSONL (reconstructs abstracts, adds citations)
    pro_request_jsonl_parquet() → Partitioned Apache Parquet files (via DuckDB)

[`pro_fetch()`](https://rkrug.github.io/openalexPro/reference/pro_fetch.md)
is a convenience wrapper that chains all three stages.

## Common Commands

All R package development uses `devtools` (or `R CMD`):

``` r
devtools::load_all()      # Load package
devtools::document()      # Regenerate roxygen2 docs and NAMESPACE
devtools::test()          # Run all tests
devtools::check()         # Full R CMD CHECK

# Run a specific test file (match by number prefix or name)
devtools::test(filter = "003")       # runs test-003-pro_query.R
devtools::test(filter = "snapshot")  # runs test-*snapshot*.R
```

### Live API Tests

Live tests are isolated in
`tests/testthat/test-900-live_api_contracts.R` and gated:

``` r
Sys.setenv(OPENALEXPRO_LIVE_TESTS = "true")
options(openalexPro.apikey = "<your-key>")
devtools::test(filter = "900")
```

### Re-recording VCR Cassettes

``` r
Sys.setenv(OPENALEXPRO_RECORD_CASSETTES = "true")
devtools::test()
# Then sanitize the real API key from recorded cassettes:
source("inst/scripts/record_cassettes.R")
```

## Architecture

### Key Design Decisions

- **On-disk processing**: Each pipeline stage writes to disk before the
  next begins. This enables resume after crashes and avoids OOM for
  large datasets.
- **One parquet file per gzip input file**: Enables parallelism, resume,
  and preserves hive partition structure. Files are never merged —
  Arrow/DuckDB handle multi-file datasets natively.
- **`workers` parameter**: All parallel operations
  ([`pro_request()`](https://rkrug.github.io/openalexPro/reference/pro_request.md),
  [`pro_fetch()`](https://rkrug.github.io/openalexPro/reference/pro_fetch.md),
  [`snapshot_to_parquet()`](https://rkrug.github.io/openalexPro/reference/snapshot_to_parquet.md),
  [`build_corpus_index()`](https://rkrug.github.io/openalexPro/reference/build_corpus_index.md))
  accept a `workers` parameter controlling `future_lapply()`
  multisession workers. Each worker gets its own DuckDB connection.
- **`abstract_inverted_index` stored as `VARCHAR`**: DuckDB folds STRUCT
  keys to lowercase, destroying case-sensitive keys like `{"as", "As"}`.
  Stored as raw JSON string; parse with
  [`jsonlite::fromJSON()`](https://jeroen.r-universe.dev/jsonlite/reference/fromJSON.html)
  when needed.
- **Windows path normalization**: Uses path-depth counting instead of
  string comparison to avoid 8.3 short-name collisions.

### Schema Inference (`infer_json_schema.R`)

Infers a unified DuckDB schema from multiple JSON/JSONL files using a
per-file loop with two-level disk caching (per-file + merged).
Type-widening rules: STRUCT/LIST/MAP beats simpler types; widest numeric
wins; fallback is `VARCHAR`.

### HTTP Layer (`api_call.R`)

All API calls route through `api_call()`, which wraps httr2 with retry
logic, User-Agent header, and consistent error handling. Functions
accept `api_key = NULL` (unauthenticated, lower rate limits) or a
length-1 character string.

### Hive Partitioning

When a query is chunked (e.g., large ID lists split into `Chunk_1`,
`Chunk_2`, …), output parquet uses `query=Chunk_1/`, `query=Chunk_2/`
subdirectory structure.

## Test Infrastructure

- **VCR cassettes** in `tests/fixtures/vcr/`: Mock HTTP responses. API
  keys are filtered to `<api-key>` in cassettes; if `openalexPro.apikey`
  is not set, `tests/testthat/helper_vcr.R` injects `"test-api-key"` so
  CI passes.
- **Snapshot tests**: Use `expect_snapshot()` /
  `expect_snapshot_file()`. Custom comparators in `helper_vcr.R` handle
  platform differences:
  - `compare_json()` / `compare_jsonl()`: Normalizes numeric types
    across platforms
  - `compare_json_ignore()`: Ignores specified fields during comparison
- **Test numbering**: Files are numbered `test-000-*.R` through
  `test-900-*.R`; `test-900-*` are live API tests.

## Key Dependencies

| Package                   | Role                                                             |
|---------------------------|------------------------------------------------------------------|
| `arrow`                   | Read/write Parquet datasets; lazy on-disk dplyr interface        |
| `duckdb` (≥1.0)           | JSON→JSONL→Parquet conversion; schema inference via `DESCRIBE`   |
| `httr2`                   | All HTTP requests with retry/error handling                      |
| `future` / `future.apply` | Parallel processing via multisession workers                     |
| `jqr`                     | Wrapper for jq CLI — abstract reconstruction from inverted index |
| `cli` / `progressr`       | Progress bars and terminal output                                |
