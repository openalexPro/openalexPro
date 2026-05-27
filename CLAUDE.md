# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Package Does

**openalexPro** is an R package for large-scale, on-disk bibliographic data retrieval from the [OpenAlex](https://openalex.org) API. Unlike the simpler `openalexR`, it processes data page-by-page rather than loading everything into RAM, enabling retrieval of millions of records without memory exhaustion.

## Common Commands

```r
devtools::load_all()      # Load package
devtools::document()      # Regenerate roxygen2 docs and NAMESPACE
devtools::test()          # Run all tests
devtools::check()         # Full R CMD CHECK
```

### Live API Tests

```r
Sys.setenv(OPENALEXPRO_LIVE_TESTS = "true")
options(openalexPro.apikey = "<your-key>")
devtools::test(filter = "900")
```

### Re-recording VCR Cassettes

```r
Sys.setenv(OPENALEXPRO_RECORD_CASSETTES = "true")
source("inst/scripts/record_cassettes.R")
```

## Architecture

The package has one functional area: **OpenAlex API access**.

Snapshot conversion, corpus indexing, and ID-based record lookup have moved to the
**`openalexSnapshot`** package. Calling `snapshot_to_parquet()`, `build_corpus_index()`,
or `lookup_by_id()` in `openalexPro` raises an informative error pointing to
`openalexSnapshot`.

### OpenAlex API (cloud)

Functions that query the live OpenAlex REST API:

- `pro_query()` — builds query URLs with filters, search, entity selection, ID chunking
- `pro_request()` — paginates through API results, writes JSON; accepts nested lists of URLs (each nesting level becomes a subdirectory)
- `pro_request_parquet()` — converts JSON files from `pro_request()` directly to Parquet (schema inference + per-file DuckDB COPY, parallel via `future`)
- `pro_fetch()` — all-in-one: query → paginate → convert to Parquet (project folder)
- `pro_count()` — counts matching records
- `pro_download_content()` — downloads PDFs / TEI XML from `content.openalex.org`
- `pro_rate_limit_status()` — queries the `/rate-limit` endpoint
- `pro_validate_credentials()` — checks API key validity

All HTTP calls route through `api_call()` (`R/api_call.R`), which handles retries,
error inspection, and `httr2` plumbing. Tests use VCR cassettes in
`tests/fixtures/vcr/`.

### SQL helpers

- `oa_works_abstract_sql()` — DuckDB SQL expression reconstructing plain-text abstract from `abstract_inverted_index` MAP column
- `oa_works_citation_sql()` — DuckDB SQL expression building `"Author (year)"` citation string
- `oa_normalize_duckdb_type()` — canonicalises a DuckDB type string (uppercases keywords)

### Supporting functions

- `id_block()` — converts an OpenAlex ID to its block number (`floor(numeric_id / 10000)`)
- `infer_json_schema()` — per-file schema inference with two-level caching
- `opt_select_fields()`, `opt_filter_names()` — helpers for building API queries
- `prepare_snapshot()` — snapshot download/preparation utilities

## Branching

- Work on `claude/<description>` branches from `dev`
- Merge into `dev` (never commit directly to `main`)
- `main` receives only release commits

## Debug Options

- `options(openalexPro.ratelimit_check = TRUE)` — print rate-limit status before every API call (via `api_call()`)

## Key Conventions

- `project_dir` is the standard output directory parameter (consistent across `pro_fetch()`, `pro_request()`)
- OpenAlex IDs accepted in both short form (`W2741809807`) and long form (`https://openalex.org/W2741809807`)
- Nested query lists produce hive-partitioned parquet: depth 1 → `query=<name>`, depth N → `query_lN=<name>`
- VCR cassettes record/replay API calls; `api_key` is filtered to `<api-key>` in cassettes
- `OPENALEXPRO_LIVE_TESTS=true` + a real API key enables live API tests in `test-900`

### Key Design Decisions

- **On-disk processing**: Each pipeline stage writes to disk before the next begins. This enables resume after crashes and avoids OOM for large datasets.
- **One parquet file per JSON input file**: Enables parallelism, resume, and preserves hive partition structure.
- **`ignore_errors = true` in schema inference**: DuckDB's `read_json` with `ignore_errors = true` infers `abstract_inverted_index` as `MAP(VARCHAR, BIGINT[])`, which correctly handles duplicate-cased keys (e.g. `"the"` / `"The"`) and is compatible with `oa_works_abstract_sql()`.

## Test Infrastructure

- **VCR cassettes** in `tests/fixtures/vcr/`: Mock HTTP responses. API keys filtered to `<api-key>`; `helper_vcr.R` injects `"test-api-key"` on CI.
- **Snapshot tests**: Custom comparators `compare_json()`, `compare_jsonl()`, `compare_json_ignore()` handle platform differences.
- **Test numbering**: `test-000-*.R` through `test-900-*.R`; `test-900-*` are live API tests.
