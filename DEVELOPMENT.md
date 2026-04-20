# Development Notes — openalexPro

This file records architectural decisions, refactoring rationale, and session-level
development history for the `openalexPro` package. It is aimed at future contributors
(and at Claude Code in future sessions) to understand *why* things are the way they are.

---

## 2026-04-20 — Fix `overwrite` parameter in `pro_request()` list method and `pro_fetch()` (0.8.1)

**Bug:** `pro_request()` accepted an `overwrite` parameter but silently ignored
it when `query_url` was a list — the top-level output directory was never
checked or deleted, and each sub-query's `fetch_query_pages()` call received
`overwrite = FALSE` hardcoded, so re-running with an existing output caused
cryptic per-subdirectory errors rather than a clean atomic overwrite.

**Fix (`R/pro_request.R`):** Added an upfront check in the list method before
flattening queries: error if `output` exists and `overwrite = FALSE`; delete
it with `unlink(recursive = TRUE)` if `overwrite = TRUE`. Sub-function calls
keep `overwrite = FALSE` (the directory no longer exists by the time they run).

**Bug:** `pro_fetch()` delegated `overwrite` to each of the three sub-functions
(`pro_request`, `pro_request_jsonl`, `pro_request_jsonl_parquet`) individually,
so directories were deleted one at a time as the pipeline progressed. If
`overwrite = FALSE` and only `jsonl/` existed (not `json/`), the first step
would succeed silently and only fail on the second.

**Fix (`R/pro_fetch.R`):** Upfront check across all three subdirectories before
starting the pipeline: collect which of `json/`, `jsonl/`, `parquet/` exist,
error with a combined message if `overwrite = FALSE`, delete all existing ones
if `overwrite = TRUE`. Sub-functions receive `overwrite = FALSE`.

**Key files:** `R/pro_request.R`, `R/pro_fetch.R`

---

## 2026-04-16 — Wrap `openalex-snapshot` binary; add `*_R()` fallbacks (0.7.0)

**Motivation:** The companion Rust CLI `openalex-snapshot` is now more capable
than the pure-R implementations for snapshot processing (adds verification,
repair, progress monitoring, and schema comparison) and substantially faster.
Rather than maintaining two competing implementations, the R package now delegates
to the binary via `system2()` while preserving the original R code under `*_R()`
suffixed names.

**Breaking API changes:**

| Old call | New call |
|---|---|
| `snapshot_to_parquet(snapshot_dir="...", parquet_dir="...")` | `snapshot_to_parquet(root_dir="...")` |
| `build_corpus_index(corpus_dir="...")` | `build_corpus_index(root_dir="...")` |
| `lookup_by_id(index_file="...", output="...")` | `lookup_by_id(root_dir="...", project_dir="...")` |

**Root-dir layout:** the binary derives all paths from a single `--root-dir`:
`<root>/openalex-snapshot/` (raw JSON), `<root>/parquet/` (converted parquet),
`<root>/.openalex-snapshot_metadata/` (metadata). `root_dir = "."` means the
working directory.

**New helpers (`R/oas_binary.R`):**

- `find_oas_binary(oas_bin = NULL)`: resolves binary via `oas_bin` arg →
  `options("openalexPro.oas_bin")` → `Sys.which("openalex-snapshot")`. Errors
  with an actionable message if not found.
- `run_oas(args, oas_bin)`: calls `system2(binary, args)`, aborts on non-zero exit.

**Preserved pure-R fallbacks (exported):**

- `snapshot_to_parquet_R()` — original R + DuckDB conversion
- `build_corpus_index_R()` — original R + DuckDB index building
- `lookup_by_id_R()` — original R + DuckDB record retrieval

These retain the original parameter names and work without any external binary.

**Test pattern:** Each test file has two sections — one for the `*_R()` function
(always runs; requires arrow + duckdb) and one for the binary wrapper (gated with
`skip_if(Sys.which("openalex-snapshot") == "", "...")`).

**Makefile:** `inst/Makefile.snapshot` rewritten to call the binary directly via
`openalex-snapshot convert --root-dir ${ROOTDIR}` and
`openalex-snapshot index --root-dir ${ROOTDIR}` instead of `Rscript`.

**Key files:** `R/oas_binary.R` (new), `R/snapshot_to_parquet.R`,
`R/build_corpus_index.R`, `R/lookup_by_id.R`, `inst/Makefile.snapshot`,
`tests/testthat/test-013-snapshot_to_parquet.R`,
`tests/testthat/test-011-build_corpus_index.R`,
`tests/testthat/test-012-lookup_by_id.R`

---

## 2026-03-02 — Normalize `api_key` handling; add live contract tests

**Background:** API key handling diverged across functions and docs. Some code
paths assumed a key was always required, while OpenAlex still supports
unauthenticated requests with lower limits. A consistent contract was needed:
allow explicit unauthenticated mode while validating malformed inputs.

**Implementation:**

- Normalized `api_key` handling in:
  - `pro_count()`
  - `pro_request()` / `fetch_query_pages()`
  - `pro_fetch()`
  - `pro_download_content()`
  - `pro_rate_limit_status()`
  - `pro_validate_credentials()` docs
- Unified rules:
  - `api_key = NULL` or `api_key = ""` => send request without API key query param.
  - Otherwise `api_key` must be a length-1 character string.
  - Invalid types now fail fast with a clear error.
- Updated roxygen/man docs for the above functions to reflect optional
  unauthenticated mode.

**Testing:**

- Added opt-in live API contract tests:
  - `tests/testthat/helper_live.R`
  - `tests/testthat/test-900-live_api_contracts.R`
- Live tests are skipped unless both conditions are met:
  - `OPENALEXPRO_LIVE_TESTS=true`
  - `openalexPro.apikey` is set to a non-dummy value
- Patched `test-014-pro_download_content.R` to reflect new behavior when
  `api_key` is missing (no longer an immediate error; request sent without key).
- Full suite passes after this normalization.

**Cassette workflow hardening:**

- Added `inst/scripts/record_cassettes.R` to re-record and sanitize cassettes.
- Added a preflight key check via `pro_rate_limit_status()` to avoid replacing
  valid cassettes with HTTP 401 responses when credentials are invalid.
- Updated `helper_vcr.R` behavior for explicit recording mode
  (`OPENALEXPRO_RECORD_CASSETTES`).

---

## 2026-03-02 — Add `pro_rate_limit_status()`; refactor `pro_validate_credentials()`

**Background:** OpenAlex added a dedicated `/rate-limit` endpoint that returns
the caller's current daily budget, amount used, remaining balance, and
per-endpoint costs in a single JSON object. This replaces the previous
credential-check pattern (making a dummy `pro_count()` call) with a purpose-built
status function.

**Implementation:**

- New file `R/pro_rate_limit_status.R` with exported `pro_rate_limit_status()`.
- Makes a `GET https://api.openalex.org/rate-limit?api_key=<key>` request.
- Uses `httr2::req_error(is_error = function(resp) FALSE)` so httr2 never
  auto-throws — all status codes are inspected in R:
  - `200` → parse body, return list invisibly; print summary if `verbose = TRUE`.
  - `401`/`403` → message "Invalid API key …", return `FALSE` invisibly.
  - Network/connection error (caught by `tryCatch`) → message "Request failed …",
    return `NULL` invisibly.
  - Missing key (empty string) → message with setup instructions, return `FALSE`.
- *(Updated 2026-03-02)* Now goes through `api_call(get_html_response = NULL)`
  wrapped in `suppressMessages()` — see the refactor entry below for rationale.
- `@importFrom httr2` updated to drop `req_error` (now handled inside `api_call`).

**Refactor:** `pro_validate_credentials()` now calls
`pro_rate_limit_status(api_key = api_key, verbose = FALSE)` and checks
`isTRUE(is.list(result))`. The public interface (messages, `TRUE`/`FALSE` return)
is unchanged. Using the rate-limit endpoint is more semantically correct and
avoids wasting quota on a dummy count query.

**Tests:** `tests/testthat/test-015-pro_rate_limit_status.R` with two VCR
cassettes (`pro_rate_limit_status_200.yml`, `pro_rate_limit_status_401.yml`).
Covers: missing key, invalid key (401), success verbose=TRUE/FALSE, and network
error via `local_mocked_bindings`. 13 assertions, all green.

**Key files:** `R/pro_rate_limit_status.R`, `R/pro_validate_credentials.R`,
`tests/testthat/test-015-pro_rate_limit_status.R`,
`tests/fixtures/vcr/pro_rate_limit_status_200.yml`,
`tests/fixtures/vcr/pro_rate_limit_status_401.yml`

---

## 2026-03-02 — Unify API calls through `api_call()`; document XPAC

**Background:** Two functions (`pro_rate_limit_status` and `pro_download_content`)
were building their own httr2 pipelines with inline `req_retry()` and `req_error()`
calls, duplicating logic already centralised in `api_call()`. A separate set of
documentation gaps was identified around OpenAlex XPAC support.

**API call unification:**

- Both functions now call `api_call(req, ..., get_html_response = NULL)`.
  `get_html_response = NULL` tells `api_call` to return (not abort) for all
  non-200 responses; the caller then inspects the status code itself.
- `suppressMessages()` wraps the `api_call()` call so the helper's internal
  logging (`"⚠ HTTP 401 - returning response for caller inspection"`, etc.) is
  suppressed; each function emits its own user-facing messages instead.
- `pro_download_content()` gains a `User-Agent` header (was previously missing).
- `pro_download_content()` passes `max_retries = 5` (matching its previous
  `req_retry(max_tries = 5)`); `transient_responses` defaults are identical.
- `pro_rate_limit_status()`'s `tryCatch` catches `rlang::abort` thrown by
  `api_call()` on network errors, returning `NULL` as before.
- 32 tests (014 + 015) all green after the refactor.

**Key insight — `get_html_response = NULL` vs missing:**
`api_call()` uses R's `missing()` to detect whether the argument was provided.
Passing `NULL` explicitly selects "return all non-200 responses"; omitting the
argument entirely selects "abort on all non-200". This is the correct mode for
both of these callers.

**XPAC documentation:**

- Added `### XPAC — Expansion Pack Works` subsection to `vignettes/pro_query.qmd`
  under `## Additional Options`. Explains what XPAC is, how to enable it via
  `options = list(include_xpac = TRUE)`, how to filter for XPAC-only works with
  `is_xpac = TRUE`, and how to chain discovery into `pro_download_content()`.
  No code changes needed — the `options` parameter already splices arbitrary
  query parameters via `httr2::req_url_query(req, !!!q)`.
- Added XPAC example to `pro_download_content()` `@examples` roxygen block.

**Key files:** `R/pro_rate_limit_status.R`, `R/pro_download_content.R`,
`vignettes/pro_query.qmd`

---

## 2026-02-25 — Add `pro_download_content()` for PDF and TEI XML downloads

**Background:** OpenAlex added a new content endpoint (`content.openalex.org`)
that serves full-text PDFs (~60 M files) and Grobid TEI XML (~43 M files) for
works. Cost is $0.01 per file. The metadata API already supports
`has_content.pdf:true` and `has_content.grobid-xml:true` filter arguments in
`pro_query()` to discover downloadable works.

**Implementation:**
- New file `R/pro_download_content.R` with exported `pro_download_content()`.
- Accepts a character vector of work IDs (or full OpenAlex URLs, normalised).
- Downloads via `httr2::req_perform()`: PDF → `resp_body_raw()` + `writeBin()`;
  grobid-xml → `resp_body_string()` + `writeLines()`.
- Parallel via `future_lapply()` consistent with rest of package.
- Returns a data frame (`id`, `file`, `status`, `message`) — never aborts on
  partial failures.
- API key passed as `?api_key=` query parameter (same as all other functions).
- Tests use `httr2::with_mocked_responses()` — no VCR cassettes needed.

**Key file:** `R/pro_download_content.R`

---

## 2026-02-25 — Deprecate filter-based search; add `search.exact` and `search.semantic`

**Background:** OpenAlex deprecated the `filter=field.search:keyword` URL syntax
in favour of a top-level `search=keyword` parameter. Two new variants were also
introduced: `search.exact` (unstemmed) and `search.semantic` (AI-powered).

**Changes:**
- `pro_query()` already had a `search` parameter (mapped to `search=` in the URL);
  added `search.exact` and `search.semantic` alongside it in `shared_q`.
- `.validate_filter()` now emits a `cli::cli_warn()` when any filter name ends
  with `.search` or `.search.no_stem`, directing users to `search =` instead.
- Existing tests that use `title_and_abstract.search = "..."` are intentionally
  kept as **canaries**: they will fail when OpenAlex removes the deprecated syntax,
  signalling that migration is complete.
- New URL-construction tests added to `test-003-pro_query.R` for the new params.
- README example updated to use `search =`.
- Version bumped to 0.6.0.

**Key file:** `R/pro_query.R`

---

## 2026-02-24 — Fix Windows path-normalization failures (CI)

**Root cause:** On Windows GitHub Actions runners, `tempdir()` returns a path
containing the 8.3 short name (`RUNNER~1`), while `normalizePath(f)` on a file
*inside* that directory resolves to the long name (`runneradmin`). These are
structurally different strings even though they refer to the same location. Any
code that compared absolute paths (via `%in%`, `!=`, or regex substitution) for
resume detection or subdir logic would silently malfunction.

Additionally, `normalizePath()` uses `\` as a separator on Windows, but
`list.files()` and DuckDB use `/`, causing `%in%` comparisons to fail even when
the short/long-name issue is absent.

**Symptoms (12 test failures on Windows CI, none on macOS/Linux):**

1. `test-013` (resume detection in `snapshot_to_parquet()`): `%in%` comparing
   `list.files()` output (`/`) vs `normalizePath()` output (`\`) always `FALSE`
   → all files re-converted instead of skipped.
2. `test-012` (`build_corpus_index()` + `lookup_by_id()` path doubling):
   `build_corpus_index()` used `regexp_replace(filename, '<snapshot_dir>', '')`
   in SQL. On Windows, `snapshot_dir` contained `\`, DuckDB `filename` uses `/`
   → regex never matched → full absolute path stored. `lookup_by_id()` then
   did `file.path(snapshot_path, abs_path)` doubling the path.
3. `test-004`/`test-007` (spurious `query=` directories in
   `pro_request_jsonl_parquet()`): `dirname(normalizePath(f)) != input_root`
   always `TRUE` due to 8.3 vs long-name mismatch → every output file placed in
   a `query=<dirname>` subdirectory instead of the root output directory.

**Fixes:**

1. **`R/snapshot_to_parquet.R`**: Apply `gsub("\\\\", "/", ...)` to both sides
   of the `%in%` comparison used for resume detection (existing parquets vs
   expected parquets).
2. **`R/build_corpus_index.R`**: Compute `snapshot_depth` (number of path
   components in `snapshot_dir`) before `future_lapply`. Inside each worker,
   split the file path into components and extract
   `pf_parts[seq(snapshot_depth + 1, length(pf_parts))]` as the relative path.
   Pass this as a SQL literal string (`'<rel_path>' AS parquet_file`) — no
   `filename = true` needed, no regex in SQL.
3. **`R/pro_request_jsonl_parquet.R`**: Replace `normalizePath` string
   comparison with depth-based subdir detection: compute `input_depth`, split
   each file path, check `length(f_parts) > input_depth + 1` to detect
   subdirectories.
4. **`R/lookup_by_id.R`**: Normalize separators after `file.path()`:
   `gsub("\\\\", "/", file.path(snapshot_path, names(file_chunks)))`.

**Key principle:** Path-depth counting is immune to 8.3 vs long-name differences
because `RUNNER~1` and `runneradmin` occupy the same depth in the hierarchy.
Never compare absolute paths across `normalizePath()` and `list.files()` on
Windows.

**All 183 tests pass** on macOS after all fixes; Windows CI no longer has
path-related failures.

**Key files:** `R/snapshot_to_parquet.R`, `R/build_corpus_index.R`,
`R/pro_request_jsonl_parquet.R`, `R/lookup_by_id.R`

---

## 2026-02-24 — Export `infer_json_schema()` and rename cache files

**Export:** `infer_json_schema()` was previously internal (`@noRd`). It is now
exported with full roxygen documentation including `@section Caching` and
`@section Type-widening rules`. Useful standalone for any workflow that needs
a unified DuckDB columns clause from a set of JSON/NDJSON files.

**Cache file rename:** Per-file schema cache files were named
`%06d_<basename>.schema.csv` (sequential index + raw filename). The index was
meaningless when files were sampled randomly, and the `.gz` in the name
made it hard to identify the source. Renamed to `<update_date>_<part_name>.csv`
(e.g. `2024-01-15_part_001.csv`), derived from `basename(dirname(f))` with the
`updated_date=` hive prefix stripped, and `basename(f)` with `.gz` removed.

**Key file:** `R/infer_json_schema.R`

---

## 2026-02-23 — Preserve `abstract_inverted_index` as VARCHAR in works parquet

**Problem:** OpenAlex `works` files contain `abstract_inverted_index` with JSON keys
`"as"` and `"As"` (case-different, which is valid JSON). DuckDB folds struct field names
to lowercase, causing a collision (`duplicate key "as"`) that crashes the conversion.
`ignore_errors=true` silently drops entire records rather than just the problematic field,
which is too destructive. Dropping the column entirely loses data.

**Root cause:** DuckDB auto-infers JSON objects as `STRUCT` types and case-folds field
names. Arrow R has no JSON reading capability, so it cannot be used as an alternative.

**Fix:** After schema inference, override the type of `abstract_inverted_index` to
`VARCHAR` in the `columns_clause` for the `works` dataset. When DuckDB reads the field
with type `VARCHAR`, it captures the raw JSON text without parsing the object's keys into
struct fields — so no case-folding, no collision. All records are preserved.

The stored VARCHAR value is a JSON string (e.g. `'{"The":[0],"as":[1],"As":[2]}'`),
parseable with `jsonlite::fromJSON()` when needed. Case-sensitive keys are preserved
because they're stored as data, not struct field names.

**Changes:**
- `R/snapshot_to_parquet.R`: replaces the column-drop gsub with a type-override gsub
  (`'abstract_inverted_index': 'VARCHAR'`); `ignore_errors=true` removed from
  `ndjson_options` (no longer needed).
- `tests/testthat/test-013-snapshot_to_parquet.R`: added test verifying the column is
  present as character and that `"as"`/`"As"` round-trip correctly via jsonlite.

**Key file:** `R/snapshot_to_parquet.R`

---

## 2026-02-23 — Per-file schema inference with two-level disk caching

**Problem:** `infer_json_schema()` ran a single bulk DuckDB query against all sampled
files: `DESCRIBE SELECT * FROM read_json_auto([N files], union_by_name = true, ...)`.
For the `works` dataset (1981 files, `maximum_object_size=1000000000`), this OOMed and
killed R (exit code -1) when `sample_size` exceeded the file count and no sampling
occurred.

**Fix:** Replaced the single bulk query with a per-file loop — one small `DESCRIBE`
per file — followed by R-side schema merging. Added two levels of disk caching:

1. **Per-file schema cache** (`<parquet_ds>/.schema_cache/<update_date>_<part_name>.csv`):
   each file's schema saved immediately after inference, so mid-inference restarts
   skip already-processed files.
2. **Unified schema cache** (`<parquet_ds>/.schema_cache/unified_schema.csv`): the
   merged result saved after all per-file schemas are merged; loaded first on any
   subsequent run, bypassing all DuckDB queries entirely. Delete this file to force
   re-inference.

**Type-widening rules in `merge_schemas()`** (for columns that differ across files):
1. All identical → keep as-is.
2. STRUCT/LIST/MAP vs simpler type → complex type wins.
3. Multiple STRUCT types → pick the one with the most fields.
4. Numeric conflicts → widest type wins: `TINYINT < SMALLINT < INTEGER < BIGINT < HUGEINT < FLOAT < DOUBLE`.
5. Fallback → `VARCHAR`.
Column order is preserved (first-seen, not alphabetical) to maintain backward
compatibility with existing parquet consumers.

**Changes:**
- `R/infer_json_schema.R`: rewrote `infer_json_schema()` to use per-file loop with
  caching; added `schema_cache_dir` parameter; added `merge_schemas()` internal helper.
- `R/snapshot_to_parquet.R`: passes `schema_cache_dir = file.path(parquet_ds, ".schema_cache")`.
- `tests/testthat/test-013-snapshot_to_parquet.R`: added two new tests for cache
  creation and unified schema reuse.

**Key files:** `R/infer_json_schema.R`, `R/snapshot_to_parquet.R`,
`tests/testthat/test-013-snapshot_to_parquet.R`

---

## 2026-02-13 — DuckDB temp file IO error fix (TEMP_DIR in Makefile)

**Problem:** During `snapshot_to_parquet()` for the `works` dataset (resume run after
an OOM kill), DuckDB raised:

```
IO Error: Could not read enough bytes from file ".tmp/duckdb_temp_storage_DEFAULT-0.tmp":
  attempted to read 262144 bytes from location 24641536
```

DuckDB spills temporary data to `.tmp/` relative to the working directory by default.
This directory can fill up (or be on a slow/full filesystem) causing the error.

**Fix:** Exposed `temp_directory` via a new `TEMP_DIR` Makefile variable (default
`/tmp`) and passed it to `snapshot_to_parquet()` in the `parquet` target. The
`snapshot_to_parquet()` function already accepted `temp_directory`; only the Makefile
was missing the plumbing.

**Changes:**
- Added `TEMP_DIR=/tmp` variable to `inst/Makefile.snapshot`.
- Added `TEMP_DIR` to `help` output and the command-line override example.
- Passed `temp_directory = "'${TEMP_DIR}'"` to `snapshot_to_parquet()` in the `parquet`
  target.
- Updated `vignettes/snapshot.qmd`: added `TEMP_DIR` to the variables table and added a
  Troubleshooting entry explaining the error and fix.

**Key files:** `inst/Makefile.snapshot`, `vignettes/snapshot.qmd`

---

## 2026-02-13 — Remove `mailto`; temporarily require `api_key`

**Motivation:** OpenAlex retired email-based polite-pool access. API keys are now the
only supported authentication mechanism. Silently passing an empty key caused opaque
403 errors.

**Note:** This requirement was later relaxed (see 2026-03-02 entry above). Current
development supports unauthenticated mode via `api_key = NULL` / `""`.

**Changes:**

- Removed `mailto` parameter from `pro_request()`, `pro_fetch()`, `pro_count()`,
  `pro_validate_credentials()`, and `pro_query()` examples.
- Added upfront `api_key` validation in `pro_request()`, `pro_fetch()`, and
  `pro_count()`: if `Sys.getenv("openalexPro.apikey")` is empty, a clear error is
  thrown with instructions to set the env var.
- Simplified User-Agent from `openalexPro v[VERSION] (mailto:[EMAIL])` to
  `openalexPro/[VERSION]`.
- Removed `mailto` query parameter from `pro_count()` requests.
- Updated all four vignettes (`Quick_Start.qmd`, `pro_request.qmd`, `pro_query.qmd`,
  `Workflow.qmd`) to remove email setup steps.
- Updated all test files (`test-004` through `test-008`, `test-005-pro_fetch_search`,
  `test-006`) to remove `mailto = "test@example.com"` arguments.
- Patched VCR cassettes to remove `mailto=...` from recorded URIs.
- Added a dummy `api_key` fallback in `helper_vcr.R` so VCR-based tests pass without
  a real key set in the environment.

**Key files:** `R/pro_request.R`, `R/pro_fetch.R`, `R/pro_count.R`,
`R/pro_validate_credentials.R`, `tests/testthat/helper_vcr.R`,
`tests/fixtures/vcr/*.yml`

---

## 2026-02-13 — snapshot_to_parquet path fixes and Makefile improvements

**Motivation (path collision bug):** The original code used `basename()` to derive
output parquet filenames from input `.gz` filenames. OpenAlex snapshots use hive
partitioning (e.g. `updated_date=2024-01-01/part_000.gz`), so multiple partitions
contain identically-named files. Using `basename()` caused output collisions.

**Fix:** Replaced `basename()` with relative path computation:

```r
json_dir_norm <- normalizePath(json_dir)
rel_paths <- vapply(gz_files, function(f) {
  substring(normalizePath(f), nchar(json_dir_norm) + 2)
}, character(1), USE.NAMES = FALSE)
```

`nchar(root) + 1` = the path separator position; `+2` = first character of the
relative path. Avoids regex escaping entirely.

**Motivation (hive partition naming in pro_request_jsonl_parquet):** Query result
subfolders (e.g. `Chunk_1`, which may contain spaces) should become proper hive
partition directories (`query=Chunk_1`) in the parquet output for compatibility with
Arrow/DuckDB partition-aware reads.

**Fix in `pro_request_jsonl_parquet.R`:**

```r
if (dirname(f_norm) != input_root) {
  file.path(output, paste0("query=", basename(dirname(f_norm))), fname)
} else {
  file.path(output, fname)
}
```

**Makefile improvements (`inst/Makefile.snapshot`):**
- Added `SAMPLE_SIZE=10000` variable (passed to `snapshot_to_parquet()`).
- Added `cli.progress_handlers_force = "cli"` to the `Rscript` options so progress
  bars render in non-interactive (Makefile) sessions.
- Added `SAMPLE_SIZE` to `help` output and the override example line.

**Key files:** `R/snapshot_to_parquet.R`, `R/pro_request_jsonl_parquet.R`,
`inst/Makefile.snapshot`, `tests/testthat/test-013-snapshot_to_parquet.R`

---

## 2026-02-13 — OOM kill fix for schema inference

**Problem:** Running `snapshot_to_parquet()` on the `works` dataset (largest dataset,
~300 GB) with `SAMPLE_SIZE=1000` caused the R process to be killed (exit code 137 =
OOM) during schema inference. The schema inference DuckDB connection had no memory
limit, while the per-file conversion connections did.

**Fix:** Applied `memory_limit` and `temp_directory` settings to the schema inference
connection in `snapshot_to_parquet()` (same settings already applied to per-file
workers). This enables DuckDB to spill to disk during inference rather than exhausting
RAM.

**Note:** A batch-processing approach for schema inference (processing files in chunks
rather than a single DESCRIBE query) was explored but reverted because it changed
column ordering (DuckDB field order vs. `tapply` alphabetical sort), breaking test
snapshots.

**Key file:** `R/snapshot_to_parquet.R` (Stage 1 connection setup, lines ~153–168)

---

## 2026-02-13 — R CMD CHECK: no visible binding for `id`

**Problem:** `R CMD CHECK` reported: `lookup_by_id: no visible binding for global
variable 'id'` due to `dplyr::filter(id %in% ids)` in `R/lookup_by_id.R`.

**Fix:** Changed to `dplyr::filter(.data$id %in% ids)` and added
`@importFrom rlang .data` to the roxygen docs. The `NAMESPACE` was regenerated via
`devtools::document()`.

**Key file:** `R/lookup_by_id.R`

---

## Earlier (0.5.0) — snapshot_to_parquet major refactor

**Motivation:** The original `snapshot_to_parquet()` loaded all `.gz` files for a
dataset into a single DuckDB query, which caused OOM errors for large datasets. The
refactor converts each `.gz` to one `.parquet` file individually, enabling:

- Parallelisation via `future_lapply()` with one DuckDB connection per worker.
- Per-file resume: already-converted files are skipped on re-run.
- Unified schema: a sample of files is used to infer a consistent schema before
  conversion, preventing type conflicts across parquet files.

**Architecture:**

```
snapshot_to_parquet()         # main loop over datasets
  → infer_json_schema()       # Stage 1: DESCRIBE on sample of files
  → future_lapply(            # Stage 2: parallel conversion
      convert_json_to_parquet() # one DuckDB connection per file
    )
```

Both `infer_json_schema()` and `convert_json_to_parquet()` live in
`R/infer_json_schema.R` (internal, `@noRd`).

**Schema inference detail:** Uses DuckDB's
`DESCRIBE SELECT * FROM read_json_auto([...], union_by_name = true)` on a sample of
files. The resulting columns clause (`{'col': 'TYPE', ...}`) is then passed to
`read_json(..., columns = ...)` for each file, ensuring all output parquets share the
same schema even when individual files have missing columns.

**Special case:** The `works` dataset uses `maximum_object_size=1000000000` because
individual work records can exceed DuckDB's default JSON object size limit.

**Key files:** `R/snapshot_to_parquet.R`, `R/infer_json_schema.R`

---

## Earlier (0.5.0) — build_corpus_index and lookup_by_id

**Motivation:** The OpenAlex snapshot after conversion is ~300 GB of parquet files.
Loading it all into memory to look up specific IDs is not feasible. A dedicated index
(`_id_idx.parquet`) stores only `(id, source_file, row_group)` tuples, enabling fast
seeks.

**Architecture:**

```
build_corpus_index(corpus_dir)
  → scans all parquet files in corpus_dir
  → writes corpus_dir_id_idx.parquet alongside corpus_dir

lookup_by_id(ids, corpus_dir, index_file)
  → filters index for matching IDs
  → reads only the relevant row groups from source parquet files
```

**Key files:** `R/build_corpus_index.R`, `R/lookup_by_id.R`

---

## Earlier (0.4.1) — unified schema inference in pro_request_jsonl_parquet

**Motivation:** When downloading a large query, different JSONL pages can have
different column types (e.g. `apc_paid` is `null` in some pages and a struct in
others). Writing these to separate parquet files and then reading them together via
Arrow causes "Unsupported cast" errors.

**Fix:** Added upfront schema inference (sampling up to `sample_size` files with
`union_by_name = true`) before converting, so all parquet files share the same schema.

---

## Earlier (0.4.1) — api_key / email handling simplification

Removed `oa_mail()` and `oa_apikey()` helper functions. Credentials are now read
exclusively from environment variables:

- `openalexPro.apikey` — API key
- `openalexPro.email` — email (polite pool; later removed entirely in dev version)

---

## Earlier (0.3.x) — pro_fetch convenience wrapper

Added `pro_fetch()` as an all-in-one function that chains:
`pro_request()` → `pro_request_jsonl()` → `pro_request_jsonl_parquet()`

into a single call with a `project_folder` argument. Useful for the common "give me
a parquet dataset for this query" use case.

---

## Earlier (0.2.0) — pro_query builder

Added `pro_query()` as the package-native query builder. Handles:
- Entity selection
- Filter construction
- ID chunking (splitting large ID lists into multiple queries to stay within URL
  length limits)
- Returns a list of URLs when chunking is needed

---

## Design decisions (standing)

### One parquet per gz file
Each `.gz` input file produces exactly one `.parquet` output file, preserving
directory structure. This is intentional: it enables resume, parallelism, and
preserves hive partition directories from the source snapshot.

### No merging of parquet files
Parquet files are left as a dataset directory, not merged. Arrow and DuckDB both
handle multi-file datasets natively and more efficiently than a single large file.

### Workers parameter
All parallel operations use `future_lapply()` with `future::multisession`. The `workers`
parameter consistently controls parallelism. When `workers = NULL` or `workers <= 1`,
sequential processing is used.

### VCR cassettes
Tests use the `vcr` package to record/replay API interactions. Cassettes are stored in
`tests/fixtures/vcr/`. The `api_key` query parameter is filtered (replaced with
`<api-key>`) in both recorded and replayed requests. A dummy key
(`"test-api-key"`) is set in `helper_vcr.R` if no real key is present, so tests pass
in CI without real credentials.
