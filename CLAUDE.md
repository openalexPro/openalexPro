# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## What This Package Does

**openalexPro** is an R package for large-scale, on-disk bibliographic
data retrieval from the [OpenAlex](https://openalex.org) API. Unlike the
simpler `openalexR`, it processes data page-by-page rather than loading
everything into RAM, enabling retrieval of millions of records without
memory exhaustion.

## Common Commands

``` r

devtools::load_all()      # Load package
devtools::document()      # Regenerate roxygen2 docs and NAMESPACE
devtools::test()          # Run all tests
devtools::check()         # Full R CMD CHECK
```

### Live API Tests

``` r

Sys.setenv(OPENALEXPRO_LIVE_TESTS = "true")
options(openalexPro.apikey = "<your-key>")
devtools::test(filter = "900")
```

### Re-recording VCR Cassettes

``` r

Sys.setenv(OPENALEXPRO_RECORD_CASSETTES = "true")
source("inst/scripts/record_cassettes.R")
```

## Architecture

The package has one functional area: **OpenAlex API access**.

Snapshot conversion, corpus indexing, and ID-based record lookup have
moved to the **`openalexSnapshot`** package. Calling
`snapshot_to_parquet()`, `build_corpus_index()`, or `lookup_by_id()` in
`openalexPro` raises an informative error pointing to
`openalexSnapshot`.

### OpenAlex API (cloud)

Functions that query the live OpenAlex REST API:

- [`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)
  — builds query URLs with filters, search, entity selection, ID
  chunking
- [`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
  — paginates through API results, writes JSON; accepts nested lists of
  URLs (each nesting level becomes a subdirectory). `resume = TRUE`
  refetches only the leaf queries that did not complete, using the
  `00_in.progress` sentinel each leaf carries while it is being written
- [`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)
  — converts JSON files from
  [`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
  directly to Parquet (schema inference + per-file DuckDB COPY, parallel
  via `future`). `resume = TRUE` converts only what is missing;
  `on_error` controls what happens to files that fail (see *Failure
  handling* below)
- [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
  — all-in-one: query → paginate → convert to Parquet (project folder)
- [`pro_count()`](https://openalexpro.github.io/openalexPro/reference/pro_count.md)
  — counts matching records
- [`pro_download_content()`](https://openalexpro.github.io/openalexPro/reference/pro_download_content.md)
  — downloads PDFs / TEI XML from `content.openalex.org`
- [`pro_rate_limit_status()`](https://openalexpro.github.io/openalexPro/reference/pro_rate_limit_status.md)
  — queries the `/rate-limit` endpoint
- [`pro_validate_credentials()`](https://openalexpro.github.io/openalexPro/reference/pro_validate_credentials.md)
  — checks API key validity

All HTTP calls route through `api_call()` (`R/api_call.R`), which
handles retries, error inspection, and `httr2` plumbing. Tests use VCR
cassettes in `tests/fixtures/vcr/`.

### SQL helpers

- [`oa_works_abstract_sql()`](https://openalexpro.github.io/openalexPro/reference/oa_works_abstract_sql.md)
  — DuckDB SQL expression reconstructing plain-text abstract from
  `abstract_inverted_index` MAP column
- [`oa_works_citation_sql()`](https://openalexpro.github.io/openalexPro/reference/oa_works_citation_sql.md)
  — DuckDB SQL expression building `"Author (year)"` citation string
- [`oa_normalize_duckdb_type()`](https://openalexpro.github.io/openalexPro/reference/oa_normalize_duckdb_type.md)
  — canonicalises a DuckDB type string (uppercases keywords)

### Supporting functions

- [`id_block()`](https://openalexpro.github.io/openalexPro/reference/id_block.md)
  — converts an OpenAlex ID to its block number
  (`floor(numeric_id / 10000)`)
- [`infer_json_schema()`](https://openalexpro.github.io/openalexPro/reference/infer_json_schema.md)
  — per-file schema inference with two-level caching
- [`opt_select_fields()`](https://openalexpro.github.io/openalexPro/reference/opt_select_fields.md),
  [`opt_filter_names()`](https://openalexpro.github.io/openalexPro/reference/opt_filter_names.md)
  — helpers for building API queries
- [`oa_schema()`](https://openalexpro.github.io/openalexPro/reference/oa_schema.md)
  — get or refresh the baseline entity schema used by
  `pro_request_parquet(schema = "auto")`
- `.pro_con()` / `.pro_worker_memory()` / `.pro_temp_dir()` (internal,
  `R/utils_duckdb.R`) — the configured DuckDB connection factory and its
  budget helpers

## Branching

- Work on `claude/<description>` branches from `dev`
- Merge into `dev` (never commit directly to `main`)
- `main` receives only release commits

## Debug Options

- `options(openalexPro.ratelimit_check = TRUE)` — print rate-limit
  status before every API call (via `api_call()`)

## Key Conventions

- `project_dir` is the standard output directory parameter (consistent
  across
  [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md),
  [`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md))
- OpenAlex IDs accepted in both short form (`W2741809807`) and long form
  (`https://openalex.org/W2741809807`)
- Nested query lists produce hive-partitioned parquet: depth 1 →
  `query=<name>`, depth N → `query_lN=<name>`
- VCR cassettes record/replay API calls; `api_key` is filtered to
  `<api-key>` in cassettes
- `OPENALEXPRO_LIVE_TESTS=true` + a real API key enables live API tests
  in `test-900`

### DuckDB connections

All DuckDB connections go through `.pro_con()` (`R/utils_duckdb.R`),
which sets `preserve_insertion_order`, `memory_limit`, `threads` and
`temp_directory`, and optionally loads the JSON extension.

Do not open a bare `dbConnect(duckdb::duckdb())` in a worker. DuckDB’s
defaults are a `memory_limit` of ~80% of system RAM **per instance** —
so N workers promise 0.8 × N of the machine — and a `temp_directory` of
`.tmp` *relative to the working directory*, which every worker inherits
and then corrupts by writing colliding `duckdb_temp_storage_*.tmp`
files.
[`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)
gives each worker a derived budget, `threads = 1`, and a private spill
directory under [`tempdir()`](https://rdrr.io/r/base/tempfile.html).

Physical RAM is derived from DuckDB itself — a bare connection’s
`memory_limit` is 80% of it — so there is no new dependency and no
platform-specific code.

Note also that `INSTALL json; LOAD json;` is explicit rather than left
to autoloading: `autoinstall_known_extensions` defaults to **FALSE**, so
autoloading can only load an extension that is already installed, never
fetch one. That works on a developer machine and fails on a fresh CI
runner.

### Failure handling in `pro_request_parquet()`

Per-file conversion failures are collected, retried once sequentially at
the full memory budget (per-file peak memory varies with how large and
nested a page is, so sizing the per-worker limit for the worst file
would throttle all of them), and then dispatched on `on_error`:
`"error"` (default), `"warn"`, `"ignore"`.

This was a silent-data-loss bug before 0.12.0: failures were
[`message()`](https://rdrr.io/r/base/message.html)d only when `verbose`
and the run reported success regardless, so a page that failed to
convert was simply absent from the corpus and every downstream count was
quietly wrong. Each file is written to a `.part` sidecar and renamed on
success, because a parquet footer is written last — a killed worker used
to leave a file that passed
[`file.exists()`](https://rdrr.io/r/base/files.html) but could not be
read.

### Key Design Decisions

- **On-disk processing**: Each pipeline stage writes to disk before the
  next begins. This enables resume after crashes and avoids OOM for
  large datasets.
- **One parquet file per JSON input file**: Enables parallelism, resume,
  and preserves hive partition structure.
- **`ignore_errors = true` in schema inference**: DuckDB’s `read_json`
  with `ignore_errors = true` infers `abstract_inverted_index` as
  `MAP(VARCHAR, BIGINT[])`, which correctly handles duplicate-cased keys
  (e.g. `"the"` / `"The"`) and is compatible with
  [`oa_works_abstract_sql()`](https://openalexpro.github.io/openalexPro/reference/oa_works_abstract_sql.md).

## Test Infrastructure

- **VCR cassettes** in `tests/fixtures/vcr/`: Mock HTTP responses. API
  keys filtered to `<api-key>`; `helper_vcr.R` injects `"test-api-key"`
  on CI.
- **Snapshot tests**: Custom comparators `compare_json()`,
  `compare_jsonl()`, `compare_json_ignore()` handle platform
  differences.
- **Test numbering**: `test-000-*.R` through `test-900-*.R`;
  `test-900-*` are live API tests.
