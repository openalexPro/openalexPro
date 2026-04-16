# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Load package during development
Rscript -e 'devtools::load_all()'

# Run all tests
Rscript -e 'devtools::test()'

# Run a specific test file
Rscript -e 'devtools::test(filter = "013")'   # snapshot_to_parquet
Rscript -e 'devtools::test(filter = "011")'   # build_corpus_index
Rscript -e 'devtools::test(filter = "012")'   # lookup_by_id

# Generate documentation (Rd files + NAMESPACE)
Rscript -e 'devtools::document()'

# Full check (target: 0 errors, 0 warnings, 0 notes)
Rscript -e 'devtools::check()'

# Build pkgdown site
Rscript -e 'pkgdown::build_site()'
```

## Architecture

The package has two functional areas:

### 1. OpenAlex API (cloud)

Functions that query the live OpenAlex REST API:

- `pro_query()` — builds query URLs with filters, search, entity selection, ID chunking
- `pro_request()` — paginates through API results, writes JSONL
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

## Branching

- Work on `claude/<description>` branches from `dev`
- Merge into `dev` (never commit directly to `main`)
- `main` receives only release commits

## Key Conventions

- `project_dir` is the standard output directory parameter (consistent across `pro_fetch()`, `pro_request()`, `lookup_by_id()`)
- OpenAlex IDs accepted in both short form (`W2741809807`) and long form (`https://openalex.org/W2741809807`)
- The `openalex-snapshot` binary only accepts one `--dataset` per invocation; multi-dataset calls loop in R
- VCR cassettes record/replay API calls; `api_key` is filtered to `<api-key>` in cassettes
- `OPENALEXPRO_LIVE_TESTS=true` + a real API key enables live API tests in `test-900`
