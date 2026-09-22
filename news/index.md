# Changelog

## openalexPro 0.12.1

### The startup banner pointed at the old r-universe

`.onAttach()` printed `https://rkrug.r-universe.dev/openalexPro`. The
package has been distributed from `https://openalexpro.r-universe.dev`
since the move to the openalexPro organisation – and `DESCRIPTION`’s
`Additional_repositories` already said so – so the one URL every user
saw on every
[`library(openalexPro)`](https://github.com/openalexPro/openalexPro) was
the one that was wrong.

Also tidies two typos in the same banner (`functions definitions`, and a
space before a comma).

## openalexPro 0.12.0

### Breaking: `pro_request_parquet()` no longer hides conversion failures

A JSON file that failed to convert was caught,
[`message()`](https://rdrr.io/r/base/message.html)d only when `verbose`,
and the run then reported success anyway. The page was simply absent
from the resulting corpus:
[`read_corpus()`](https://openalexpro.github.io/openalexPro/reference/read_corpus.md)
worked, nothing warned, and every downstream count was quietly wrong. On
a large run under memory pressure this is worse than a crash, because a
crash at least announces itself.

Failures are now collected, retried once sequentially with the full
memory budget (per-file peak memory varies with how large and nested a
page is, so sizing the per-worker limit for the worst file would
throttle all of them), and whatever still fails is reported according to
the new `on_error` argument: `"error"` (default) stops and names the
files, `"warn"` warns and returns, `"ignore"` restores the old silence.

**This will stop runs that previously appeared to succeed.** That is the
point. Pass `on_error = "warn"` for the closest thing to the old
behaviour, but visible.

Each file is now written to a `.part` sidecar and renamed on success. A
parquet footer is written last, so a worker killed mid-`COPY` used to
leave a file that looked plausible to
[`file.exists()`](https://rdrr.io/r/base/files.html) but could not be
read.

### DuckDB connections are configured rather than left at their defaults

New internal `.pro_con()` factory, mirroring
`openalexSnapshot:::.oas_con()`. Every connection in the package now
goes through it, including the schema inference pass and
`convert_json_to_parquet()`.

This matters most inside `future` workers. Each worker used to open a
bare `dbConnect(duckdb::duckdb())`, which means:

- a `memory_limit` of ~80% of system RAM **per worker** – so N workers
  promised 0.8 x N of the machine, and
- a `temp_directory` of `.tmp` *relative to the working directory*,
  shared by every worker, which is the colliding-spill-file corruption
  openalexSnapshot documents in `build_citation_index()`.

Workers now get a per-worker memory budget derived from physical RAM and
the worker count, `threads = 1` (the processes already saturate the
machine), and a private spill directory under
[`tempdir()`](https://rdrr.io/r/base/tempfile.html). `memory_limit` and
`retry_memory_limit` are exposed for callers who want to set them
directly.

Physical RAM is derived without a new dependency or platform code: a
bare DuckDB connection’s own `memory_limit` is 80% of it.

### `resume` for both request functions

`pro_request(resume = TRUE)` refetches only the leaf queries that did
not complete, using the `00_in.progress` sentinel each leaf directory
already carried and which nothing previously read.
`pro_request_parquet(resume = TRUE)` converts only the files that are
not already present – trustworthy because of the `.part`-and-rename
change above.

Previously the only options were `overwrite = TRUE` (delete everything
and refetch) or `overwrite = FALSE` (hard error). There was no way to
continue an interrupted download.

## openalexPro 0.11.0

### Breaking changes

- **`build_corpus_index()` and `lookup_by_id()` are removed.** They had
  been left behind as stubs that raised “moved to the openalexSnapshot
  package”. That was actively harmful: an exported stub **masks** the
  real function whenever both packages are attached, so
  [`library(openalexSnapshot); library(openalexPro)`](https://rdrr.io/r/base/library.html)
  made the stub win and the call fail. Use
  `openalexSnapshot::build_corpus_index()` and
  `openalexSnapshot::lookup_by_id()`.

  [`id_block()`](https://openalexpro.github.io/openalexPro/reference/id_block.md)
  and
  [`read_corpus()`](https://openalexpro.github.io/openalexPro/reference/read_corpus.md)
  are unaffected and remain exported.

### Bug fixes

- [`extract_doi()`](https://openalexpro.github.io/openalexPro/reference/extract_doi.md)
  no longer truncates DOIs containing `<`, `>`, `[` or `]`. The
  character class excluded them, so a SICI-style DOI such as
  `10.1175/1520-0450(1963)002<0713:ooasds>2.0.co;2` matched only up to
  the first `<` and returned `10.1175/1520-0450(1963)002`. The truncated
  remainder then *passed* the normalisation whitelist, so the function
  returned a plausible-looking wrong DOI with no warning and no `NA` –
  silent corruption rather than a visible failure. Roughly 0.4% of
  OpenAlex works carry such DOIs (~1.4 million records).

  Both the match pattern and the normalisation whitelist now admit those
  characters. Note the fix required reordering rather than escaping: in
  a POSIX bracket expression a backslash is literal, so `]` must be the
  first character in the class and `-` the last.

  This also fixes `openalexConvert`’s `.normalize_doi()`, which
  delegates here and therefore emitted truncated DOIs into CSL-JSON
  output.

## openalexPro 0.10.4

### Internal / Code Quality

- [`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)
  refactored into small internal helpers (`.prr_prepare_output`,
  `.prr_discover_jsons`, `.prr_infer_schema`, `.prr_apply_baseline`,
  `.prr_fix_json_types`, `.prr_output_paths`, `.prr_convert_one`) to
  drop cyclomatic complexity below the `goodpractice` threshold.
  Behaviour is unchanged.

- Added tests for `find_oas_binary()`, `run_oas()`,
  [`pro_validate_credentials()`](https://openalexpro.github.io/openalexPro/reference/pro_validate_credentials.md),
  `prepare_snapshot()`, and
  [`sample_parquet_n()`](https://openalexpro.github.io/openalexPro/reference/sample_parquet_n.md).
  Package test coverage rose from ~73% to ~80%.

- Tests that intentionally exercise the deprecated
  `pro_request_jsonl_R()` /
  [`pro_request_jsonl_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl_parquet.md)
  pipeline now wrap those calls in
  [`suppressWarnings()`](https://rdrr.io/r/base/warning.html) to keep
  test output clean.

- Added a `.lintr` configuration setting `line_length_linter(100)`
  (modern tidyverse default) and reflowed remaining long lines in
  package code.

### New Features

- [`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)
  gains a `schema` parameter (default `"auto"`) that uses pre-built
  field-type schemas — inferred from the complete OpenAlex snapshot — to
  resolve ambiguous DuckDB type inference on small API pages. This
  eliminates `VARCHAR[] → JSON` type-conflict errors when unioning
  parquet files from separate API calls (e.g. keypaper + cited + citing
  in a snowball search).

- New `oa_cache_schema()` function copies schemas from a snapshot
  metadata directory
  (e.g. `/Volumes/openalex/openalex-snapshot_metadata`) into the
  user-level cache so the correct types are available even when the
  volume is not mounted.

- Factory-default schemas for all 21 OpenAlex entity types are now
  bundled in `inst/extdata/schemata/` and used automatically when
  `schema = "auto"`, so the feature works out-of-the-box without any
  manual cache population.

### Bug Fixes

- [`oa_works_abstract_sql()`](https://openalexpro.github.io/openalexPro/reference/oa_works_abstract_sql.md)
  now casts `abstract_inverted_index` through JSON
  (`::JSON::MAP(VARCHAR, BIGINT[])`) before calling `map_entries()`.
  This fixes abstract reconstruction when DuckDB infers the column as
  `STRUCT` (which happens when a sampled API page contains no
  duplicate-cased keys) rather than `MAP`. The expression now handles
  `STRUCT`, `MAP`, and `VARCHAR` inputs uniformly (#XXX).

- [`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)
  now overrides the inferred DuckDB type of `abstract_inverted_index` to
  `MAP(VARCHAR, BIGINT[])` when building the paginated `read_json`
  schema, so the fix applies even before the abstract SQL runs.

### Breaking Changes

- `snapshot_to_parquet()`, `build_corpus_index()`, and `lookup_by_id()`
  have moved to the **openalexSnapshot** package. Calling them in
  `openalexPro` now raises an informative error. Their `_R` variants
  have been removed entirely.

- `pro_request_parquet_R()` and `pro_fetch_R()` removed.
  [`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)
  and
  [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
  are now the single pure-R/DuckDB implementations.

### Internal Changes

- [`oa_works_abstract_sql()`](https://openalexpro.github.io/openalexPro/reference/oa_works_abstract_sql.md),
  [`oa_works_citation_sql()`](https://openalexpro.github.io/openalexPro/reference/oa_works_citation_sql.md),
  and
  [`oa_normalize_duckdb_type()`](https://openalexpro.github.io/openalexPro/reference/oa_normalize_duckdb_type.md)
  are now implemented in R (behaviour unchanged).

## openalexPro 0.9.0

### New Features

- **[`pro_rate_limit_status()`](https://openalexpro.github.io/openalexPro/reference/pro_rate_limit_status.md)**
  — query your OpenAlex API rate-limit status (daily budget, used,
  remaining, prepaid balance, reset time, per-endpoint costs). Returns a
  list invisibly; prints a formatted summary when `verbose = TRUE`.

- New debug option `openalexPro.ratelimit_check`: when set to `TRUE` via
  `options(openalexPro.ratelimit_check = TRUE)`, every API call prints
  the current rate-limit status (budget, usage, remaining, reset time)
  as a message before the request is sent. Internally handled in
  `api_call()` using `pro_rate_limit_status(verbose = TRUE)`. A
  recursion guard temporarily disables the option during the nested
  rate-limit request.

## openalexPro 0.8.1

### Bug Fixes

- [`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
  list method now respects the `overwrite` parameter. Previously, when
  `query_url` was a list, the top-level `output` directory was neither
  checked nor deleted regardless of `overwrite`. It now errors if the
  directory exists and `overwrite = FALSE`, and deletes it upfront if
  `overwrite = TRUE`.

- [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
  now deletes all three subdirectories (`json`, `jsonl`, `parquet`)
  upfront before the pipeline starts when `overwrite = TRUE`, rather
  than delegating deletion to each sub-function individually. If any of
  the subdirectories exist and `overwrite = FALSE`, the function now
  errors immediately with a clear message listing which directories
  already exist.

## openalexPro 0.8.0

### New Features

- [`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md),
  [`pro_request_jsonl()`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl.md),
  and
  [`pro_request_jsonl_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl_parquet.md)
  now accept **nested lists** of query URLs. Each nesting level is
  preserved as a subdirectory in the output, and the parquet stage
  converts directory depth into hive-style partition keys: depth 1 →
  `query=<name>`, depth 2 → `query_l2=<name>`, depth 3 →
  `query_l3=<name>`, etc. The resulting dataset is readable with
  [`arrow::open_dataset()`](https://arrow.apache.org/docs/r/reference/open_dataset.html)
  and the partition columns appear as regular columns.
  [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
  inherits this behaviour automatically. A new internal helper
  `collect_leaf_queries()` performs the recursive list flattening.

## openalexPro 0.7.0

### Breaking Changes

- `snapshot_to_parquet()` has a new signature. The old `snapshot_dir`
  and `parquet_dir` parameters are replaced by a single `root_dir`
  parameter that matches the directory layout used by the companion
  `openalex-snapshot` binary. The function now delegates to the binary
  rather than performing conversion in R. **Migration:** replace
  `snapshot_to_parquet(snapshot_dir = "...", parquet_dir = "...")` with
  `snapshot_to_parquet(root_dir = "...")`.

- `build_corpus_index()` has a new signature. The old `corpus_dir`
  parameter is replaced by `root_dir`. The function now delegates to the
  `openalex-snapshot` binary. **Migration:** replace
  `build_corpus_index(corpus_dir = "...")` with
  `build_corpus_index(root_dir = "...")`.

- `lookup_by_id()` has a new signature. The old `index_file` and
  `output` parameters are replaced by `root_dir` and `project_dir`
  (consistent with the project-folder convention used by
  [`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
  and
  [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)).
  The function now delegates to the `openalex-snapshot` binary.
  **Migration:** replace
  `lookup_by_id(index_file = "...", output = "...")` with
  `lookup_by_id(root_dir = "...", project_dir = "...")`.

### New Features

- Pure-R / DuckDB fallback variants are now exported as separate
  functions:

  - `snapshot_to_parquet_R()` — original R implementation of snapshot
    conversion (uses DuckDB + arrow, no external binary required)
  - `build_corpus_index_R()` — original R implementation of index
    building
  - `lookup_by_id_R()` — original R implementation of ID-based record
    lookup

  These retain the original parameter names and are useful when the
  `openalex-snapshot` binary is unavailable.

- `find_oas_binary()` and `run_oas()` are exported internal helpers for
  resolving and invoking the `openalex-snapshot` binary. They support:

  1.  Explicit `oas_bin` argument
  2.  `options(openalexPro.oas_bin = "/path/to/binary")`
  3.  PATH search via `Sys.which("openalex-snapshot")`

- `inst/Makefile.snapshot` updated to use the `openalex-snapshot` binary
  directly (replacing `Rscript` invocations of the now-renamed R
  functions).

## openalexPro 0.6.1

### Bug Fixes

- Manual add the `id` field to the `opt_select_names()` as it is missing
  from the returned list from OpenAlex

### Changes

- Normalized `api_key` handling across API-calling functions:
  [`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md),
  [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md),
  [`pro_count()`](https://openalexpro.github.io/openalexPro/reference/pro_count.md),
  and
  [`pro_download_content()`](https://openalexpro.github.io/openalexPro/reference/pro_download_content.md)
  now accept `api_key = NULL` or `api_key = ""`. In that case, requests
  are sent without an API key (subject to OpenAlex’s unauthenticated
  limits).

- Added explicit `api_key` type validation in API-calling functions.
  Accepted inputs are now limited to `NULL` or a length-1 character
  string.

- Updated
  [`pro_rate_limit_status()`](https://openalexpro.github.io/openalexPro/reference/pro_rate_limit_status.md)
  to handle `api_key = NULL` safely (informational message + `FALSE`
  return), and aligned documentation.

### Testing and Tooling

- Added opt-in live API contract tests
  (`tests/testthat/test-900-live_api_contracts.R`) gated by
  `OPENALEXPRO_LIVE_TESTS=true` and a non-dummy `openalexPro.apikey`.

- Added `inst/scripts/record_cassettes.R` and recording safeguards to
  prevent accidental re-recording with invalid credentials.

- Reduced warning noise in test runs by cleaning up deprecated-search
  warning handling and removing unused cassette hooks.

## openalexPro 0.6.0

### New Features

- Added
  [`pro_rate_limit_status()`](https://openalexpro.github.io/openalexPro/reference/pro_rate_limit_status.md)
  to query the OpenAlex rate-limit endpoint (`GET /rate-limit`). Returns
  the full rate-limit JSON invisibly (daily budget, used, remaining,
  prepaid balance, per-endpoint costs, reset time). Prints a
  human-readable summary via
  [`message()`](https://rdrr.io/r/base/message.html) when
  `verbose = TRUE` (the default). Returns `FALSE` for a missing or
  invalid API key, and `NULL` on a network error, so callers can
  distinguish auth problems from transient failures.

- [`pro_validate_credentials()`](https://openalexpro.github.io/openalexPro/reference/pro_validate_credentials.md)
  refactored to use
  [`pro_rate_limit_status()`](https://openalexpro.github.io/openalexPro/reference/pro_rate_limit_status.md)
  internally instead of making a separate
  [`pro_count()`](https://openalexpro.github.io/openalexPro/reference/pro_count.md)
  request. Behaviour and return value are unchanged.

- Added
  [`pro_download_content()`](https://openalexpro.github.io/openalexPro/reference/pro_download_content.md)
  to download full-text PDFs (`format = "pdf"`) or TEI XML
  (`format = "grobid-xml"`) from the OpenAlex content endpoint
  (`content.openalex.org`). Accepts a vector of work IDs, supports
  parallel downloads via `workers`, and returns a data frame with
  per-file status (`"ok"` / `"not_found"` / `"error"`). Note: content
  downloads cost \$0.01 per file.

- Added `search.exact` and `search.semantic` parameters to
  [`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md),
  matching the new OpenAlex search API:

  - `search.exact`: searches without stemming or stop-word removal;
    supports boolean operators, quoted phrases, proximity (`~N`), and
    wildcards.
  - `search.semantic`: AI embedding-based search that matches by
    conceptual meaning rather than keywords (max 50 results, max 1
    req/sec).
  - `search`: now documented to support the full boolean/phrase/wildcard
    syntax in addition to its existing stemmed matching.

- Exported
  [`infer_json_schema()`](https://openalexpro.github.io/openalexPro/reference/infer_json_schema.md)
  for direct use. Infers a unified DuckDB columns clause from a set of
  JSON/NDJSON files via per-file `DESCRIBE` queries with type-widening
  and optional two-level disk caching (`schema_cache_dir`).

### Internal Changes

- [`pro_rate_limit_status()`](https://openalexpro.github.io/openalexPro/reference/pro_rate_limit_status.md)
  and
  [`pro_download_content()`](https://openalexpro.github.io/openalexPro/reference/pro_download_content.md)
  now route their HTTP requests through the internal `api_call()`
  helper, unifying retry logic and error handling across all real API
  call sites.
  [`suppressMessages()`](https://rdrr.io/r/base/message.html) is used to
  suppress `api_call()`’s internal logging so each function emits its
  own user-facing messages.
  [`pro_download_content()`](https://openalexpro.github.io/openalexPro/reference/pro_download_content.md)
  now also sends a `User-Agent` header (previously omitted).

### Deprecations

- Filter arguments with a `.search` suffix
  (e.g. `title_and_abstract.search = "..."`) are deprecated by the
  OpenAlex API. They still work but now emit a warning. Use the `search`
  parameter of
  [`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)
  instead: `pro_query(entity = "works", search = "your terms")`. See
  <https://developers.openalex.org/guides/searching> for details.

### Bug Fixes

- Fixed Windows path-normalization failures in `snapshot_to_parquet()`,
  `build_corpus_index()`, `lookup_by_id()`, and
  [`pro_request_jsonl_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl_parquet.md).
  On Windows,
  [`normalizePath()`](https://rdrr.io/r/base/normalizePath.html) can
  return 8.3 short names (e.g. `RUNNER~1`) for
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html)-derived paths
  while [`list.files()`](https://rdrr.io/r/base/list.files.html) and
  DuckDB resolve to long names (`runneradmin`). Resume detection in
  `snapshot_to_parquet()` used `%in%` on paths with mixed separators
  (`\` vs `/`), causing already-converted files to be reconverted.
  `build_corpus_index()` embedded `snapshot_dir` (with `\`) inside a
  DuckDB `regexp_replace` pattern, which never matched — so the full
  absolute path was stored in the index and later doubled by
  `lookup_by_id()`.
  [`pro_request_jsonl_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl_parquet.md)
  used `normalizePath` string comparison to detect subdirectories, which
  always failed, placing every output file in a spurious
  `query=<dirname>` subdirectory.

  Fixes: (1) normalize separators to `/` with `gsub("\\\\", "/", ...)`
  on both sides of `%in%` comparisons; (2) compute relative paths in R
  using path-depth counting (`strsplit(path, "/")` then indexed
  extraction) rather than string-matching absolute paths — immune to 8.3
  vs long-name differences;

  3.  pass the relative path as a SQL literal in `build_corpus_index()`
      instead of computing it inside DuckDB with a regex.

### Changes

- Schema cache per-file CSVs renamed from `%06d_<basename>.schema.csv`
  to `<update_date>_<part_name>.csv` (e.g. `2024-01-15_part_001.csv`),
  making each cache file directly traceable to its source `.gz`.

### Breaking Changes

- Removed `mailto` parameter from all API functions
  ([`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md),
  [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md),
  [`pro_count()`](https://openalexpro.github.io/openalexPro/reference/pro_count.md),
  [`pro_validate_credentials()`](https://openalexpro.github.io/openalexPro/reference/pro_validate_credentials.md)).
  OpenAlex no longer uses email addresses for polite-pool access.
- `api_key` handling was tightened in 0.6.0 for
  [`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md),
  [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md),
  and
  [`pro_count()`](https://openalexpro.github.io/openalexPro/reference/pro_count.md).  
  Note: this was later relaxed again in development; current development
  allows `api_key = NULL` / `""` and runs in unauthenticated mode.
- Simplified User-Agent string from
  `openalexPro v[VERSION] (mailto:[EMAIL])` to `openalexPro/[VERSION]`.

## openalexPro 0.5.0

### New Features

#### Snapshot Handling

- Added `prepare_snapshot()` function for setting up a directory with
  Makefile and documentation for managing OpenAlex snapshots.
- Added `Makefile.snapshot` in `inst/` for automating snapshot download,
  conversion, and indexing. Includes targets for `snapshot`, `parquet`,
  `parquet_index`, and automatic renaming of existing data with release
  dates.
- Added `snapshot_to_parquet()` function for converting OpenAlex
  snapshot NDJSON files to Parquet format using DuckDB. Processes each
  `.gz` file individually with per-file resume support. Supports
  parallel processing via `workers` (using `future_lapply()`) and
  unified schema inference via `sample_size`.
- Added `build_corpus_index()` function for creating memory-efficient
  Parquet indexes for fast ID lookups. Handles 300M+ records by
  processing parquet files individually, with optional parallelization
  via `workers` and progress reporting via `progressr`. The index file
  is auto-named and placed alongside the corpus directory.
- Added `lookup_by_id()` function for fast record retrieval from a
  parquet corpus using pre-built indexes. Uses Arrow for index filtering
  with automatic ID normalization. Supports parallel reads via `workers`
  and streaming to parquet via `output` for millions of IDs without
  loading into memory.
- Added `snapshot_filter_ids()` function for filtering snapshot data by
  ID lists.
- Added
  [`id_block()`](https://openalexpro.github.io/openalexPro/reference/id_block.md)
  helper function for computing ID block partitions.

### Documentation

- Added `snapshot.qmd` vignette with comprehensive guide on downloading,
  converting, and querying OpenAlex snapshots locally.

### Changes

- Refactored `snapshot_to_parquet()` to process each `.gz` file
  individually instead of all at once. This reduces memory usage,
  enables per-file resume on interruption, and shows progress with ETA.
  The `workers` parameter now controls parallel `future` workers instead
  of DuckDB threads. Added `sample_size` parameter for schema inference.
- Extracted
  [`infer_json_schema()`](https://openalexpro.github.io/openalexPro/reference/infer_json_schema.md)
  and `convert_json_to_parquet()` internal helpers, shared by both
  `snapshot_to_parquet()` and
  [`pro_request_jsonl_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl_parquet.md).
- Refactored
  [`pro_request_jsonl_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl_parquet.md)
  to per-file conversion with `future_lapply()` parallelization. Removes
  hive partitioning by `page`; subfolder structure is preserved
  directly. Added `workers` parameter. Removed `progress` parameter
  (replaced by `progressr`).

### Bug Fixes

- Fixed vignette parse errors in `pro_query.qmd` (malformed code block
  closings).
- Fixed out-of-memory crash in `snapshot_to_parquet()` when
  `sample_size` exceeded the number of available files
  (e.g. `sample_size = 10000` with 1981 works files). Schema inference
  now processes one file at a time instead of a single bulk DuckDB
  query.
- Fixed `duplicate key "as"` crash when converting the `works` dataset.
  `abstract_inverted_index` is now stored as `VARCHAR` (raw JSON string)
  rather than a `STRUCT`. DuckDB folds struct field names to lowercase,
  causing a collision between the valid JSON keys `"as"` and `"As"` in
  this field. Storing as `VARCHAR` avoids struct parsing entirely and
  preserves the data. Parse individual values with
  [`jsonlite::fromJSON()`](https://jeroen.r-universe.dev/jsonlite/reference/fromJSON.html)
  when needed.
- Fixed DuckDB temp file IO errors during `snapshot_to_parquet()` by
  exposing a `TEMP_DIR` variable in `Makefile.snapshot` (default
  `/tmp`).

### Changes

- `snapshot_to_parquet()` schema inference now runs one DuckDB
  `DESCRIBE` per file instead of a single query across all sampled
  files. Results are cached in `<parquet_ds>/.schema_cache/`: per-file
  CSVs (`<update_date>_<part_name>.csv`) enable mid-run resume; a
  unified `unified_schema.csv` is loaded on subsequent runs to skip
  inference entirely. Delete `unified_schema.csv` to force re-inference.

### Tests

- Added comprehensive tests for `snapshot_to_parquet()`,
  `build_corpus_index()`, and `lookup_by_id()`.
- Added tests for schema caching, unified schema reuse, and works
  `abstract_inverted_index` VARCHAR round-trip.

## openalexPro v0.4.2

### Breaking Changes

- removal of `load_sql_file()` function as not needed anymore

### Documentation

- Update from vignettes and adding of new ones
- Update of README.md

### Tests

- Remove need in tests for openalexR

## openalexPro 0.4.1

- Standardised progressbar handling
- Changed default pages from 1,000 to 10,000
- Refactored `pro_query` and removed `multiple_ids` argument using
  Claude and expanded tests and added vignette.
- Added creation of `00_completed` in output directory of `json`,
  `jsonl` and `parquet` folders upon successful completion
- Changed api key and email handling. Removed oap_mail()\_ and
  oap_apikey() and simplified handling of api key and email to only use
  environmental variables `openalexPro.email` and `openalexPro.apikey`
- Added unified schema inference to
  [`pro_request_jsonl_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl_parquet.md)
  to prevent schema conflicts when reading combined Parquet datasets.
  New `sample_size` parameter controls schema inference sampling. This
  fixes “Unsupported cast from string to struct” errors when fields have
  different types across JSONL files (e.g., `apc_paid` being `null` in
  some files and a struct in others).
- Removed `harmonize_parquet_schemata()` as it is no longer needed with
  the new unified schema inference.
- Increased default n umber of pages to be read by `request_json()` from
  1000 to 10000 to allow the initially planned 2,000,000 work download.

## openalexPro 0.4.0

- CI and coverage tweaks for CRAN readiness.

- splitting snowball functionality into openalexSnowball

## openalexPro 0.3.1

- Added
  [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
  with `project_folder` support for structured outputs.
- Added progress reporting and parallelization for
  [`pro_request_jsonl()`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl.md).
- Added
  [`sample_parquet_n()`](https://openalexpro.github.io/openalexPro/reference/sample_parquet_n.md)
  random sampling utilities with `select` support.
- Improved `count_only` output to return a data frame with an error
  column.

## openalexPro 0.3.0

- Added `count_only` support for
  [`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
  and related helpers.
- Added DOI handling improvements and API call fixes.

## openalexPro 0.2.0

- Introduced
  [`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)
  as the package-native query builder with chunking.
- Added snowball search utilities and citation edge extraction workflow.
- Expanded conversion pipeline tests and VCR-based API fixtures.
- Added
  [`extract_doi()`](https://openalexpro.github.io/openalexPro/reference/extract_doi.md)
  helpers and compatibility reporting artifacts.
