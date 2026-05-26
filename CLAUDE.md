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

# Run a specific test file
devtools::test(filter = "013")       # snapshot_to_parquet
devtools::test(filter = "011")       # build_corpus_index
devtools::test(filter = "012")       # lookup_by_id
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

The package has two functional areas:

### 1. OpenAlex API (cloud)

Functions that query the live OpenAlex REST API:

- `pro_query()` — builds query URLs with filters, search, entity selection, ID chunking
- `pro_request()` — paginates through API results, writes JSONL; accepts nested lists of URLs (each nesting level becomes a subdirectory)
- `pro_fetch()` — all-in-one: query → paginate → convert to parquet (project folder)
- `pro_count()` — counts matching records
- `pro_download_content()` — downloads PDFs / TEI XML from `content.openalex.org`
- `pro_rate_limit_status()` — queries the `/rate-limit` endpoint
- `pro_validate_credentials()` — checks API key validity

All HTTP calls route through `api_call()` (`R/api_call.R`), which handles retries,
error inspection, and `httr2` plumbing. Tests use VCR cassettes in
`tests/fixtures/vcr/`.

### 2. Local Snapshot Processing

Functions that process the OpenAlex bulk data snapshot (hundreds of GB of `.gz` NDJSON):

#### Binary wrappers (preferred — delegates to `openalex-snapshot` Rust CLI)

- `snapshot_to_parquet(root_dir, ...)` — converts JSON → parquet via `convert` command
- `build_corpus_index(root_dir, ...)` — builds ID lookup index via `index` command
- `lookup_by_id(root_dir, ids, project_dir, ...)` — extracts records via `extract` command

These require the `openalex-snapshot` binary. Resolution order for the binary path:
1. `oas_bin` argument
2. `options("openalexPro.oas_bin")`
3. `Sys.which("openalex-snapshot")` (PATH)

Internal helpers in `R/oas_binary.R`: `find_oas_binary()` and `run_oas()`.

**Root-dir layout** (used by the binary and its wrappers):
```
<root_dir>/
  openalex-snapshot/   # raw JSON .gz files
  parquet/             # converted parquet files
  parquet/<dataset>_id_idx.parquet   # lookup index
  .openalex-snapshot_metadata/       # metadata
```

#### Pure-R fallbacks (no binary required)

- `snapshot_to_parquet_R(snapshot_dir, parquet_dir, ...)` — original R + DuckDB conversion
- `build_corpus_index_R(corpus_dir, ...)` — original R + DuckDB index building
- `lookup_by_id_R(index_file, ids, ...)` — original R + DuckDB record retrieval

These are exported and useful when the binary is unavailable. They use
`future_lapply()` for parallelism and DuckDB for all heavy lifting.

#### Test pattern for snapshot functions

Each test file (`test-011`, `test-012`, `test-013`) has two sections:
- `*_R()` tests — always run (require `arrow` + `duckdb`)
- Binary wrapper tests — gated with `skip_if(Sys.which("openalex-snapshot") == "", "...")`

### Supporting functions

- `infer_json_schema()` — per-file schema inference with two-level caching (used by `snapshot_to_parquet_R()`)
- `id_block()` — converts an OpenAlex ID to its block number (`floor(numeric_id / 10000)`)
- `opt_select_fields()`, `opt_filter_names()` — helpers for building API queries
- `prepare_snapshot()` — snapshot download/preparation utilities
- `collect_leaf_queries()` — recursively flattens a nested list of URLs into `(path, url)` pairs (internal, used by `pro_request()`)

## Branching

- Work on `claude/<description>` branches from `dev`
- Merge into `dev` (never commit directly to `main`)
- `main` receives only release commits

## Debug Options

- `options(openalexPro.ratelimit_check = TRUE)` — print rate-limit status before every API call (via `api_call()`)
- `options(openalexPro.oas_bin = "/path/to/openalex-snapshot")` — override binary path for snapshot functions

## Key Conventions

- `project_dir` is the standard output directory parameter (consistent across `pro_fetch()`, `pro_request()`, `lookup_by_id()`)
- OpenAlex IDs accepted in both short form (`W2741809807`) and long form (`https://openalex.org/W2741809807`)
- The `openalex-snapshot` binary only accepts one `--dataset` per invocation; multi-dataset calls loop in R
- Nested query lists produce hive-partitioned parquet: depth 1 → `query=<name>`, depth N → `query_lN=<name>`
- VCR cassettes record/replay API calls; `api_key` is filtered to `<api-key>` in cassettes
- `OPENALEXPRO_LIVE_TESTS=true` + a real API key enables live API tests in `test-900`

### Key Design Decisions

- **On-disk processing**: Each pipeline stage writes to disk before the next begins. This enables resume after crashes and avoids OOM for large datasets.
- **One parquet file per gzip input file**: Enables parallelism, resume, and preserves hive partition structure.
- **`abstract_inverted_index` stored as `VARCHAR`**: DuckDB folds STRUCT keys to lowercase. Stored as raw JSON string; parse with `jsonlite::fromJSON()` when needed.

## Test Infrastructure

- **VCR cassettes** in `tests/fixtures/vcr/`: Mock HTTP responses. API keys filtered to `<api-key>`; `helper_vcr.R` injects `"test-api-key"` on CI.
- **Snapshot tests**: Custom comparators `compare_json()`, `compare_jsonl()`, `compare_json_ignore()` handle platform differences.
- **Test numbering**: `test-000-*.R` through `test-900-*.R`; `test-900-*` are live API tests.
