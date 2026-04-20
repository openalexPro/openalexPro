# openalexPro (development)

# openalexPro 0.8.1

## Bug Fixes

* `pro_request()` list method now respects the `overwrite` parameter. Previously,
  when `query_url` was a list, the top-level `output` directory was neither
  checked nor deleted regardless of `overwrite`. It now errors if the directory
  exists and `overwrite = FALSE`, and deletes it upfront if `overwrite = TRUE`.

* `pro_fetch()` now deletes all three subdirectories (`json`, `jsonl`, `parquet`)
  upfront before the pipeline starts when `overwrite = TRUE`, rather than
  delegating deletion to each sub-function individually. If any of the
  subdirectories exist and `overwrite = FALSE`, the function now errors
  immediately with a clear message listing which directories already exist.

# openalexPro 0.8.0

## New Features

* `pro_request()`, `pro_request_jsonl()`, and `pro_request_jsonl_parquet()`
  now accept **nested lists** of query URLs. Each nesting level is preserved
  as a subdirectory in the output, and the parquet stage converts directory
  depth into hive-style partition keys: depth 1 → `query=<name>`, depth 2 →
  `query_l2=<name>`, depth 3 → `query_l3=<name>`, etc. The resulting dataset
  is readable with `arrow::open_dataset()` and the partition columns appear
  as regular columns. `pro_fetch()` inherits this behaviour automatically.
  A new internal helper `collect_leaf_queries()` performs the recursive list
  flattening.

# openalexPro 0.7.0

## Breaking Changes

* `snapshot_to_parquet()` has a new signature. The old `snapshot_dir` and
  `parquet_dir` parameters are replaced by a single `root_dir` parameter that
  matches the directory layout used by the companion `openalex-snapshot` Rust
  binary. The function now delegates to the binary rather than performing
  conversion in R. **Migration:** replace
  `snapshot_to_parquet(snapshot_dir = "...", parquet_dir = "...")` with
  `snapshot_to_parquet(root_dir = "...")`.

* `build_corpus_index()` has a new signature. The old `corpus_dir` parameter
  is replaced by `root_dir`. The function now delegates to the
  `openalex-snapshot` binary. **Migration:** replace
  `build_corpus_index(corpus_dir = "...")` with
  `build_corpus_index(root_dir = "...")`.

* `lookup_by_id()` has a new signature. The old `index_file` and `output`
  parameters are replaced by `root_dir` and `project_dir` (consistent with the
  project-folder convention used by `pro_request()` and `pro_fetch()`). The
  function now delegates to the `openalex-snapshot` binary. **Migration:**
  replace `lookup_by_id(index_file = "...", output = "...")` with
  `lookup_by_id(root_dir = "...", project_dir = "...")`.

## New Features

* Pure-R / DuckDB fallback variants are now exported as separate functions:
  - `snapshot_to_parquet_R()` — original R implementation of snapshot
    conversion (uses DuckDB + arrow, no external binary required)
  - `build_corpus_index_R()` — original R implementation of index building
  - `lookup_by_id_R()` — original R implementation of ID-based record lookup
  
  These retain the original parameter names and are useful when the
  `openalex-snapshot` binary is unavailable.

* `find_oas_binary()` and `run_oas()` are exported internal helpers for
  resolving and invoking the `openalex-snapshot` binary. They support:
  1. Explicit `oas_bin` argument
  2. `options(openalexPro.oas_bin = "/path/to/binary")`
  3. PATH search via `Sys.which("openalex-snapshot")`

* `inst/Makefile.snapshot` updated to use the `openalex-snapshot` binary
  directly (replacing `Rscript` invocations of the now-renamed R functions).

## Dependencies

* The `openalex-snapshot` Rust binary is now required for
  `snapshot_to_parquet()`, `build_corpus_index()`, and `lookup_by_id()`.
  Download from <https://github.com/rkrug/openalex-snapshot/releases> or build
  with `cargo build --release`. The pure-R `*_R()` variants have no binary
  dependency.

# openalexPro 0.6.1

## Bug Fixes
* Manual add the `id` field to the `opt_select_names()` as it is missing from the returned 
  list from OpenAlex
  
## Changes

* Normalized `api_key` handling across API-calling functions:
  `pro_request()`, `pro_fetch()`, `pro_count()`, and
  `pro_download_content()` now accept `api_key = NULL` or `api_key = ""`.
  In that case, requests are sent without an API key (subject to OpenAlex's
  unauthenticated limits).

* Added explicit `api_key` type validation in API-calling functions.
  Accepted inputs are now limited to `NULL` or a length-1 character string.

* Updated `pro_rate_limit_status()` to handle `api_key = NULL` safely
  (informational message + `FALSE` return), and aligned documentation.

## Testing and Tooling

* Added opt-in live API contract tests (`tests/testthat/test-900-live_api_contracts.R`)
  gated by `OPENALEXPRO_LIVE_TESTS=true` and a non-dummy
  `openalexPro.apikey`.

* Added `inst/scripts/record_cassettes.R` and recording safeguards to prevent
  accidental re-recording with invalid credentials.

* Reduced warning noise in test runs by cleaning up deprecated-search warning
  handling and removing unused cassette hooks.

# openalexPro 0.6.0

## New Features

* Added `pro_rate_limit_status()` to query the OpenAlex rate-limit endpoint
  (`GET /rate-limit`). Returns the full rate-limit JSON invisibly (daily budget,
  used, remaining, prepaid balance, per-endpoint costs, reset time). Prints a
  human-readable summary via `message()` when `verbose = TRUE` (the default).
  Returns `FALSE` for a missing or invalid API key, and `NULL` on a network
  error, so callers can distinguish auth problems from transient failures.

* `pro_validate_credentials()` refactored to use `pro_rate_limit_status()`
  internally instead of making a separate `pro_count()` request. Behaviour and
  return value are unchanged.

* Added `pro_download_content()` to download full-text PDFs
  (`format = "pdf"`) or TEI XML (`format = "grobid-xml"`) from the OpenAlex
  content endpoint (`content.openalex.org`). Accepts a vector of work IDs,
  supports parallel downloads via `workers`, and returns a data frame with
  per-file status (`"ok"` / `"not_found"` / `"error"`). Note: content
  downloads cost \$0.01 per file.

* Added `search.exact` and `search.semantic` parameters to `pro_query()`,
  matching the new OpenAlex search API:
  - `search.exact`: searches without stemming or stop-word removal; supports
    boolean operators, quoted phrases, proximity (`~N`), and wildcards.
  - `search.semantic`: AI embedding-based search that matches by conceptual
    meaning rather than keywords (max 50 results, max 1 req/sec).
  - `search`: now documented to support the full boolean/phrase/wildcard
    syntax in addition to its existing stemmed matching.

* Exported `infer_json_schema()` for direct use. Infers a unified DuckDB columns
  clause from a set of JSON/NDJSON files via per-file `DESCRIBE` queries with
  type-widening and optional two-level disk caching (`schema_cache_dir`).

## Internal Changes

* `pro_rate_limit_status()` and `pro_download_content()` now route their HTTP
  requests through the internal `api_call()` helper, unifying retry logic and
  error handling across all real API call sites. `suppressMessages()` is used
  to suppress `api_call()`'s internal logging so each function emits its own
  user-facing messages. `pro_download_content()` now also sends a `User-Agent`
  header (previously omitted).

## Deprecations

* Filter arguments with a `.search` suffix (e.g. `title_and_abstract.search = "..."`)
  are deprecated by the OpenAlex API. They still work but now emit a warning.
  Use the `search` parameter of `pro_query()` instead:
  `pro_query(entity = "works", search = "your terms")`.
  See <https://developers.openalex.org/guides/searching> for details.

## Bug Fixes

* Fixed Windows path-normalization failures in `snapshot_to_parquet()`,
  `build_corpus_index()`, `lookup_by_id()`, and `pro_request_jsonl_parquet()`.
  On Windows, `normalizePath()` can return 8.3 short names (e.g. `RUNNER~1`)
  for `tempdir()`-derived paths while `list.files()` and DuckDB resolve to long
  names (`runneradmin`). Resume detection in `snapshot_to_parquet()` used
  `%in%` on paths with mixed separators (`\` vs `/`), causing already-converted
  files to be reconverted. `build_corpus_index()` embedded `snapshot_dir` (with
  `\`) inside a DuckDB `regexp_replace` pattern, which never matched — so the
  full absolute path was stored in the index and later doubled by
  `lookup_by_id()`. `pro_request_jsonl_parquet()` used `normalizePath` string
  comparison to detect subdirectories, which always failed, placing every output
  file in a spurious `query=<dirname>` subdirectory.

  Fixes: (1) normalize separators to `/` with `gsub("\\\\", "/", ...)` on both
  sides of `%in%` comparisons; (2) compute relative paths in R using path-depth
  counting (`strsplit(path, "/")` then indexed extraction) rather than
  string-matching absolute paths — immune to 8.3 vs long-name differences;
  (3) pass the relative path as a SQL literal in `build_corpus_index()` instead
  of computing it inside DuckDB with a regex.

## Changes

* Schema cache per-file CSVs renamed from `%06d_<basename>.schema.csv` to
  `<update_date>_<part_name>.csv` (e.g. `2024-01-15_part_001.csv`), making
  each cache file directly traceable to its source `.gz`.

## Breaking Changes

* Removed `mailto` parameter from all API functions (`pro_request()`, `pro_fetch()`,
  `pro_count()`, `pro_validate_credentials()`). OpenAlex no longer uses email addresses
  for polite-pool access.
* `api_key` handling was tightened in 0.6.0 for
  `pro_request()`, `pro_fetch()`, and `pro_count()`.  
  Note: this was later relaxed again in development; current development allows
  `api_key = NULL` / `""` and runs in unauthenticated mode.
* Simplified User-Agent string from `openalexPro v[VERSION] (mailto:[EMAIL])` to
  `openalexPro/[VERSION]`.

# openalexPro 0.5.0

## New Features

### Snapshot Handling
* Added `prepare_snapshot()` function for setting up a directory with Makefile and documentation
  for managing OpenAlex snapshots.
* Added `Makefile.snapshot` in `inst/` for automating snapshot download, conversion, and indexing.
  Includes targets for `snapshot`, `parquet`, `parquet_index`, and automatic renaming of existing
  data with release dates.
* Added `snapshot_to_parquet()` function for converting OpenAlex snapshot NDJSON files to Parquet format
  using DuckDB. Processes each `.gz` file individually with per-file resume support. Supports parallel
  processing via `workers` (using `future_lapply()`) and unified schema inference via `sample_size`.
* Added `build_corpus_index()` function for creating memory-efficient Parquet indexes for fast ID lookups.
  Handles 300M+ records by processing parquet files individually, with optional parallelization via
  `workers` and progress reporting via `progressr`. The index file is auto-named and placed alongside
  the corpus directory.
* Added `lookup_by_id()` function for fast record retrieval from a parquet corpus using pre-built indexes.
  Uses Arrow for index filtering with automatic ID normalization. Supports parallel reads
  via `workers` and streaming to parquet via `output` for millions of IDs without loading into memory.
* Added `snapshot_filter_ids()` function for filtering snapshot data by ID lists.
* Added `id_block()` helper function for computing ID block partitions.

## Documentation

* Added `snapshot.qmd` vignette with comprehensive guide on downloading, converting, and querying
  OpenAlex snapshots locally.

## Changes

* Refactored `snapshot_to_parquet()` to process each `.gz` file individually instead of all at once.
  This reduces memory usage, enables per-file resume on interruption, and shows progress with ETA.
  The `workers` parameter now controls parallel `future` workers instead of DuckDB threads.
  Added `sample_size` parameter for schema inference.
* Extracted `infer_json_schema()` and `convert_json_to_parquet()` internal helpers, shared by
  both `snapshot_to_parquet()` and `pro_request_jsonl_parquet()`.
* Refactored `pro_request_jsonl_parquet()` to per-file conversion with `future_lapply()`
  parallelization. Removes hive partitioning by `page`; subfolder structure is preserved
  directly. Added `workers` parameter. Removed `progress` parameter (replaced by `progressr`).

## Bug Fixes

* Fixed vignette parse errors in `pro_query.qmd` (malformed code block closings).
* Fixed out-of-memory crash in `snapshot_to_parquet()` when `sample_size` exceeded the
  number of available files (e.g. `sample_size = 10000` with 1981 works files). Schema
  inference now processes one file at a time instead of a single bulk DuckDB query.
* Fixed `duplicate key "as"` crash when converting the `works` dataset.
  `abstract_inverted_index` is now stored as `VARCHAR` (raw JSON string) rather than a
  `STRUCT`. DuckDB folds struct field names to lowercase, causing a collision between the
  valid JSON keys `"as"` and `"As"` in this field. Storing as `VARCHAR` avoids struct
  parsing entirely and preserves the data. Parse individual values with
  `jsonlite::fromJSON()` when needed.
* Fixed DuckDB temp file IO errors during `snapshot_to_parquet()` by exposing a
  `TEMP_DIR` variable in `Makefile.snapshot` (default `/tmp`).

## Changes

* `snapshot_to_parquet()` schema inference now runs one DuckDB `DESCRIBE` per file
  instead of a single query across all sampled files. Results are cached in
  `<parquet_ds>/.schema_cache/`: per-file CSVs (`<update_date>_<part_name>.csv`) enable
  mid-run resume; a unified `unified_schema.csv` is loaded on subsequent runs to skip
  inference entirely. Delete `unified_schema.csv` to force re-inference.

## Tests

* Added comprehensive tests for `snapshot_to_parquet()`, `build_corpus_index()`, and `lookup_by_id()`.
* Added tests for schema caching, unified schema reuse, and works `abstract_inverted_index` VARCHAR round-trip.

# openalexPro v0.4.2

## Breaking Changes

* removal of `load_sql_file()` function as not needed anymore

## Documentation

* Update from vignettes and adding of new ones
* Update of README.md

## Tests

* Remove need in tests for openalexR

# openalexPro 0.4.1

* Standardised progressbar handling
* Changed default pages from 1,000 to 10,000
* Refactored `pro_query` and removed `multiple_ids` argument using Claude and expanded tests and added vignette.
* Added creation of `00_completed` in output directory of `json`, `jsonl` and `parquet` folders upon successful completion
* Changed api key and email handling. Removed oap_mail()_ and oap_apikey() and simplified handling of api key and email to only use
  environmental variables `openalexPro.email` and `openalexPro.apikey`
* Added unified schema inference to `pro_request_jsonl_parquet()` to prevent schema conflicts when reading
  combined Parquet datasets. New `sample_size` parameter controls schema inference sampling. This fixes
  "Unsupported cast from string to struct" errors when fields have different types across JSONL files
  (e.g., `apc_paid` being `null` in some files and a struct in others).
* Removed `harmonize_parquet_schemata()` as it is no longer needed with the new unified schema inference.
* Increased default n umber of pages to be read by `request_json()` from 1000 to 10000 to allow the initially planned 2,000,000
  work download.
  
# openalexPro 0.4.0
* CI and coverage tweaks for CRAN readiness.

* splitting snowball functionality into openalexSnowball

# openalexPro 0.3.1

* Added `pro_fetch()` with `project_folder` support for structured outputs.
* Added progress reporting and parallelization for `pro_request_jsonl()`.
* Added `sample_parquet_n()` random sampling utilities with `select` support.
* Improved `count_only` output to return a data frame with an error column.

# openalexPro 0.3.0

* Added `count_only` support for `pro_request()` and related helpers.
* Added DOI handling improvements and API call fixes.

# openalexPro 0.2.0

* Introduced `pro_query()` as the package-native query builder with chunking.
* Added snowball search utilities and citation edge extraction workflow.
* Expanded conversion pipeline tests and VCR-based API fixtures.
* Added `extract_doi()` helpers and compatibility reporting artifacts.
