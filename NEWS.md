# openalexPro 0.12.1

## Readable query files for papers: `_query_oql.txt`, `_query_oql.html`

Next to `_query.json`, each downloaded query now gets its OQL -- OpenAlex's
readable rendering of the query that ran -- as plain text (to paste into a
methods section) and as a self-contained HTML page with highlighted keywords,
OpenAlex IDs linked to their records, and the exact OQO. Because OpenAlex's
rendering can be lossy in some details, the OQL is translated back and
compared: the files say whether it reproduces the query exactly. Both use
OpenAlex's free `/query` endpoint (two calls per query); if it is unreachable
the download is unaffected and the files are marked "not checked". Both are
copied into the Parquet partition.

For a list of queries, `_queries_oql.txt` and `_queries_oql.html` at the top
of the output summarise all queries in list order -- name, records, whether
the OQL is exact, the OQL -- with totals, for a paper's supplement (queries
skipped by `resume` included, failed ones listed as not downloaded).

## Test recordings refreshed

All recorded API responses were re-recorded from the live API (with the key
sent as a header and masked). The snapshot differences were checked: only
data drift (counts, citations, one record with fewer locations) and fields
OpenAlex has added since spring (`study_designs`, `volume`, `awards` details,
`observed_orcids`, location `doi` / `listed_in`, `meta.x_query`); no field
was removed. The URL / OQO equivalence tests passed again on the fresh data,
and a `pro_count()` comparison was added. `inst/scripts/record_cassettes.R`
now records all tests even when snapshots fail (testthat stopped after 10
failures and left later cassettes unrecorded, while reporting success) and
stops if any cassette is missing.

## Lossless queries: `via = "oqo"`, query record, cost, key as header

- **`via = "oqo"`** (`pro_request()`, `pro_fetch()`, `pro_count()`; default
  `"url"`, unchanged): each query is translated once (free, with validation
  before any credits are spent) into an OpenAlex Query Object and sent via
  POST. Same results -- a new test downloads the same queries both ways and
  compares the complete result sets. No URL length limit and more than 100
  values per filter, so `pro_query(..., chunk_limit = 200)` fetches DOI and
  OpenAlex ID lists in about one request per chunk, still in parallel. Single records stay GET.
- **`_query.json`** per query records the URL, how it was sent, the query as
  OpenAlex ran it (OQL, OQO), records, requests, credits, cost and time; it
  is copied into the Parquet partition, so it survives `delete_input`.
  `pro_request()` reports the total cost.
- **The API key is sent as an `Authorization: Bearer` header**, never in the
  URL, so it no longer appears in URLs, logs, error messages or recorded test
  responses.
- With `via = "url"`, a filter with more than 100 values now stops before
  sending (OpenAlex rejects it), suggesting `chunk_limit` or `via = "oqo"`.

## OQL and OQO queries

`pro_query()` gains `oql` and `oqo` (both default `NULL`, behaviour unchanged)
for OpenAlex's query language and its JSON form, which express what the
classic filter syntax cannot, such as nested `and` / `or` conditions:

```r
pro_query(oql = "works where year >= (2020) and (title has (coral) or title has (reef))")
pro_query(oqo = list(get_rows = "works",
                     filter_rows = list(list(column_id = "publication_year", value = 2020))))
```

The URL targets the API root and runs through `pro_request()`, `pro_count()`
and `pro_fetch()` unchanged. Entity, conditions, grouping, `sample` and
`corpus` belong inside the query; combining it with `entity`, `id`, `doi`,
search arguments, `group_by` or filters is an error, because OpenAlex would
silently ignore them. `select` and `options` are passed alongside. An invalid
query fails with OpenAlex's parse error and position.

`pro_request()` now detects grouped results from the response
(`meta$groups_count`) instead of looking for `group_by=` in the URL, so
grouping inside an OQL / OQO query is saved and converted correctly.

## `pro_fetch()` gains `download_workers`

Downloading is limited by the API, converting by CPU and memory, so the best
number of workers differs. `pro_fetch()` used `workers` for both steps.
`download_workers` (default `workers`, so existing calls are unchanged) now
sets the download workers separately; `workers` sets the conversion workers.

## Download robustness: failing queries, paging parameters, semantic search

- **A failing query no longer stops a list download.** With a list of
  queries, an error in one (e.g. HTTP 404 for an ID that does not exist)
  aborted the whole run. Now the other queries complete, and one error at the
  end names each failed query with OpenAlex's reason. Failed queries keep
  their `00_in.progress` marker, so `resume = TRUE` fetches only those again.
- **Semantic search works with `pro_request()` / `pro_fetch()`.** The download
  always added `cursor=*`, which OpenAlex rejects for semantic search
  (HTTP 400). Semantic search is now fetched as its single page of at most 50
  results.
- **Paging parameters are no longer silently overwritten.** A `per_page` in
  the query (1--200) is kept; `page` and `cursor` are replaced by cursor
  paging with a warning (OpenAlex rejects `page` together with `cursor`).
  Without them, paging is unchanged (`per_page = 200`, cursor).
- **`pro_request_parquet(workers = NULL)` is sequential, as documented.** It
  ran under whatever `future` plan the user had set, so a parallel plan
  converted in parallel with a single worker's memory budget and all cores
  per process. `workers` now alone decides; the user's plan is restored.
- **Samples larger than one page are downloaded completely.** OpenAlex ends
  cursor paging of a `sample` after the first page, so
  `options = list(sample = 1000)` silently gave only 200 records. A sample
  is now paged by page number, up to OpenAlex's maximum of 10,000. Paging a
  sample needs a `seed`; if none is given, one is chosen and reported in a
  message so the same sample can be fetched again. Samples that fit in one
  page are unchanged.
- **Grouped and list results in one conversion** stopped with "Mixed entity
  types found". The error now names the queries of each kind and how to
  convert them separately; the JSON files are kept.

## Filter and select validation per entity

`pro_query()` checked filter names and `select` fields against the lists for
**works**, whatever the entity, so valid entity-specific names were rejected
before reaching OpenAlex -- e.g. `pro_query(entity = "institutions",
country_code = "US")` or `select = "orcid"` for authors. Refreshing with
`update = TRUE` did not help, as it fetched the works list again.

`opt_filter_names()` and `opt_select_fields()` gain an `entity` argument
(default `"works"`, so existing calls are unchanged) and cache one list per
entity; `pro_query()` validates against the queried entity's lists. The lists
come from OpenAlex's error message for an invalid name, which costs no
credits. An entity without a list (the retired `"venues"`) skips validation
and lets OpenAlex answer.

Parsing that message also dropped the first name of every list (e.g. the
`abstract.search` filter, and `id`, which was patched back in by hand) and
left a trailing period on the last select field (`"created_date."`); both are
fixed.

## Documentation brought up to date

- **API key name:** the vignettes, `CLAUDE.md` and the message of
  `pro_rate_limit_status()` told users to set `openalexPro.apikey`, which
  `pro_api_key()` never reads -- a key set that way was silently ignored. The
  correct name is the environment variable `openalexPro.api_key` (or the option
  `openalexPro$api_key`), as the README already said.
- **Search syntax:** wildcards (`microbio*`) and fuzzy terms work only with
  `search.exact`; the stemmed `search` rejects wildcards with HTTP 400. All
  three search types cost $0.001 per call (the vignette said $0.0001), and
  semantic search does not require an API key.
- **Entities:** `sources`, `topics` and `locations` replace `venues` and
  `concepts` in the examples; `topics.id` replaces `concepts.id`.
- **Corpus:** the deprecated `include_xpac` / `is_xpac` controls are replaced
  by the `corpus` parameter (`"core"`, `"all"`, `"expansion"`); combining them
  is an error at OpenAlex.
- **Pipeline:** README, vignettes and diagrams describe `pro_request_parquet()`
  instead of the deprecated JSONL pipeline, and `pro_fetch()` no longer appears
  to write JSONL files. New sections cover OQL / OQO, `resume`, error handling
  and budgets; `inst/errorcodes.qmd` is rewritten (the "polite pool" no longer
  exists).
- Links point to the current OpenAlex documentation at `help.openalex.org`.
- The `pro_request` vignette documents `pro_request_parquet()` (signature,
  schema inference, failure handling, `resume`) instead of the deprecated
  JSONL functions, which are reduced to a pointer to their help pages.
- The snapshot vignettes install `openalexSnapshot` from r-universe (it is
  available there) and no longer claim that error-raising stubs exist.
- `DESCRIPTION` has a real `Description`, and `jsonlite` moves from Suggests
  to Imports: `pro_query(oqo = <list>)` and every JSON response parse need it,
  and httr2 does not import it.
- Six Mermaid diagrams in the `pro_query` and `pro_request` vignettes showed
  "Syntax error" (unquoted labels containing `()` or `"`); they render again.

## The startup banner pointed at the old r-universe

`.onAttach()` printed `https://rkrug.r-universe.dev/openalexPro`. The package
has been distributed from `https://openalexpro.r-universe.dev` since the move
to the openalexPro organisation -- and `DESCRIPTION`'s
`Additional_repositories` already said so -- so the one URL every user saw on
every `library(openalexPro)` was the one that was wrong.

Also tidies two typos in the same banner (`functions definitions`, and a
space before a comma).

## `delete_input` no longer deletes pages that failed to convert

With `on_error = "warn"` or `"ignore"`, `pro_request_parquet(delete_input =
TRUE)` deleted the JSON input even when some files had failed -- the only copy
of those pages -- so `resume = TRUE` could not recover them. The input is now
kept unless every file converted.

## Downloads survive network failures and stalls

`api_call()` retried only on HTTP 429/5xx. A dropped connection or curl error
aborted the whole leaf, and a stalled transfer could hang a worker forever.
Network failures are now retried with the same backoff, and a transfer below
1 byte/s for 120 s is aborted and retried. Requires `httr2 >= 1.0.0`.

## `resume` works for a single URL, and in `pro_fetch()`

`pro_request(resume = TRUE)` was silently ignored for a single URL and failed
with "Directory exists". A single URL is now treated as one leaf. `pro_fetch()`
gains `resume` (default `FALSE`, behaviour unchanged), which completes an
interrupted download and conversion and returns a finished run unchanged.

## No count request per query before a parallel download

To size its progress bar, `pro_request()` with a list of queries first sent a
count request for every leaf, one after another, before downloading anything.
For a chunked DOI / ID list (one page per leaf) that doubled the requests and
their cost. Progress now counts leaves, each advancing in fractions as its
pages arrive, with no extra requests.

## Clearer API errors, and no pointless retries on an exhausted budget

A 4xx error now includes OpenAlex's own explanation (e.g. which filter name is
invalid) instead of only "HTTP 400 Bad Request". A 429 caused by the daily
budget -- used up (`X-RateLimit-Remaining` at zero), or a query refused as
costing more than is left (`"error": "not_enough_credits"`) -- fails
immediately and says when the budget resets, instead of backing off for about
17 minutes before failing.
`verbose = TRUE` no longer prints the API key as part of the URL.

`pro_query()` no longer fetches the list of valid `select` fields when no
`select` is given, saving a request per session.

## `pro_query()` knows the current entities

`entity` now also accepts `"sources"`, `"topics"` and `"locations"`. `"venues"`
and `"concepts"` (replaced by sources and topics in OpenAlex) are kept for
compatibility. The default is still `"works"`.

## Better load balancing for parallel downloads

`pro_request()` with a list of queries pre-split the leaves into one block per
worker, so a worker that drew the large leaves ran on while the others sat
idle. Each leaf is now dispatched to the next free worker.

# openalexPro 0.12.0

## Breaking: `pro_request_parquet()` no longer hides conversion failures

A JSON file that failed to convert was caught, `message()`d only when
`verbose`, and the run then reported success anyway. The page was simply
absent from the resulting corpus: `read_corpus()` worked, nothing warned, and
every downstream count was quietly wrong. On a large run under memory
pressure this is worse than a crash, because a crash at least announces
itself.

Failures are now collected, retried once sequentially with the full memory
budget (per-file peak memory varies with how large and nested a page is, so
sizing the per-worker limit for the worst file would throttle all of them),
and whatever still fails is reported according to the new `on_error`
argument: `"error"` (default) stops and names the files, `"warn"` warns and
returns, `"ignore"` restores the old silence.

**This will stop runs that previously appeared to succeed.** That is the
point. Pass `on_error = "warn"` for the closest thing to the old behaviour,
but visible.

Each file is now written to a `.part` sidecar and renamed on success. A
parquet footer is written last, so a worker killed mid-`COPY` used to leave a
file that looked plausible to `file.exists()` but could not be read.

## DuckDB connections are configured rather than left at their defaults

New internal `.pro_con()` factory, mirroring `openalexSnapshot:::.oas_con()`.
Every connection in the package now goes through it, including the schema
inference pass and `convert_json_to_parquet()`.

This matters most inside `future` workers. Each worker used to open a bare
`dbConnect(duckdb::duckdb())`, which means:

* a `memory_limit` of ~80% of system RAM **per worker** -- so N workers
  promised 0.8 x N of the machine, and
* a `temp_directory` of `.tmp` *relative to the working directory*, shared by
  every worker, which is the colliding-spill-file corruption openalexSnapshot
  documents in `build_citation_index()`.

Workers now get a per-worker memory budget derived from physical RAM and the
worker count, `threads = 1` (the processes already saturate the machine), and
a private spill directory under `tempdir()`. `memory_limit` and
`retry_memory_limit` are exposed for callers who want to set them directly.

Physical RAM is derived without a new dependency or platform code: a bare
DuckDB connection's own `memory_limit` is 80% of it.

## `resume` for both request functions

`pro_request(resume = TRUE)` refetches only the leaf queries that did not
complete, using the `00_in.progress` sentinel each leaf directory already
carried and which nothing previously read. `pro_request_parquet(resume =
TRUE)` converts only the files that are not already present -- trustworthy
because of the `.part`-and-rename change above.

Previously the only options were `overwrite = TRUE` (delete everything and
refetch) or `overwrite = FALSE` (hard error). There was no way to continue an
interrupted download.

# openalexPro 0.11.0

## Breaking changes

* **`build_corpus_index()` and `lookup_by_id()` are removed.** They had been
  left behind as stubs that raised "moved to the openalexSnapshot package".
  That was actively harmful: an exported stub **masks** the real function
  whenever both packages are attached, so
  `library(openalexSnapshot); library(openalexPro)` made the stub win and the
  call fail. Use `openalexSnapshot::build_corpus_index()` and
  `openalexSnapshot::lookup_by_id()`.

  `id_block()` and `read_corpus()` are unaffected and remain exported.

## Bug fixes

* `extract_doi()` no longer truncates DOIs containing `<`, `>`, `[` or `]`.
  The character class excluded them, so a SICI-style DOI such as
  `10.1175/1520-0450(1963)002<0713:ooasds>2.0.co;2` matched only up to the
  first `<` and returned `10.1175/1520-0450(1963)002`. The truncated remainder
  then *passed* the normalisation whitelist, so the function returned a
  plausible-looking wrong DOI with no warning and no `NA` -- silent corruption
  rather than a visible failure. Roughly 0.4% of OpenAlex works carry such
  DOIs (~1.4 million records).

  Both the match pattern and the normalisation whitelist now admit those
  characters. Note the fix required reordering rather than escaping: in a
  POSIX bracket expression a backslash is literal, so `]` must be the first
  character in the class and `-` the last.

  This also fixes `openalexConvert`'s `.normalize_doi()`, which delegates here
  and therefore emitted truncated DOIs into CSL-JSON output.

# openalexPro 0.10.4

## Internal / Code Quality

* `pro_request_parquet()` refactored into small internal helpers
  (`.prr_prepare_output`, `.prr_discover_jsons`, `.prr_infer_schema`,
  `.prr_apply_baseline`, `.prr_fix_json_types`, `.prr_output_paths`,
  `.prr_convert_one`) to drop cyclomatic complexity below the
  `goodpractice` threshold. Behaviour is unchanged.

* Added tests for `find_oas_binary()`, `run_oas()`,
  `pro_validate_credentials()`, `prepare_snapshot()`, and
  `sample_parquet_n()`. Package test coverage rose from ~73% to ~80%.

* Tests that intentionally exercise the deprecated
  `pro_request_jsonl_R()` / `pro_request_jsonl_parquet()` pipeline now
  wrap those calls in `suppressWarnings()` to keep test output clean.

* Added a `.lintr` configuration setting `line_length_linter(100)`
  (modern tidyverse default) and reflowed remaining long lines in
  package code.

## New Features

* `pro_request_parquet()` gains a `schema` parameter (default `"auto"`) that
  uses pre-built field-type schemas — inferred from the complete OpenAlex
  snapshot — to resolve ambiguous DuckDB type inference on small API pages.
  This eliminates `VARCHAR[] → JSON` type-conflict errors when unioning parquet
  files from separate API calls (e.g. keypaper + cited + citing in a snowball
  search).

* New `oa_cache_schema()` function copies schemas from a snapshot metadata
  directory (e.g. `/Volumes/openalex/openalex-snapshot_metadata`) into the
  user-level cache so the correct types are available even when the volume is
  not mounted.

* Factory-default schemas for all 21 OpenAlex entity types are now bundled in
  `inst/extdata/schemata/` and used automatically when `schema = "auto"`, so
  the feature works out-of-the-box without any manual cache population.

## Bug Fixes

* `oa_works_abstract_sql()` now casts `abstract_inverted_index` through JSON
  (`::JSON::MAP(VARCHAR, BIGINT[])`) before calling `map_entries()`. This
  fixes abstract reconstruction when DuckDB infers the column as `STRUCT`
  (which happens when a sampled API page contains no duplicate-cased keys)
  rather than `MAP`. The expression now handles `STRUCT`, `MAP`, and `VARCHAR`
  inputs uniformly (#XXX).

* `pro_request_parquet()` now overrides the inferred DuckDB type of
  `abstract_inverted_index` to `MAP(VARCHAR, BIGINT[])` when building the
  paginated `read_json` schema, so the fix applies even before the abstract SQL
  runs.

## Breaking Changes

* `snapshot_to_parquet()`, `build_corpus_index()`, and `lookup_by_id()` have
  moved to the **openalexSnapshot** package. Calling them in `openalexPro` now
  raises an informative error. Their `_R` variants have been removed entirely.

* `pro_request_parquet_R()` and `pro_fetch_R()` removed. `pro_request_parquet()`
  and `pro_fetch()` are now the single pure-R/DuckDB implementations.

## Internal Changes

* `oa_works_abstract_sql()`, `oa_works_citation_sql()`, and
  `oa_normalize_duckdb_type()` are now implemented in R (behaviour unchanged).

# openalexPro 0.9.0

## New Features

* **`pro_rate_limit_status()`** — query your OpenAlex API rate-limit status
  (daily budget, used, remaining, prepaid balance, reset time, per-endpoint
  costs).  Returns a list invisibly; prints a formatted summary when
  `verbose = TRUE`.

* New debug option `openalexPro.ratelimit_check`: when set to `TRUE` via
  `options(openalexPro.ratelimit_check = TRUE)`, every API call prints the
  current rate-limit status (budget, usage, remaining, reset time) as a message
  before the request is sent. Internally handled in `api_call()` using
  `pro_rate_limit_status(verbose = TRUE)`. A recursion guard temporarily
  disables the option during the nested rate-limit request.

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
  matches the directory layout used by the companion `openalex-snapshot` binary.
  The function now delegates to the binary rather than performing conversion in R.
  **Migration:** replace
  `snapshot_to_parquet(snapshot_dir = "...", parquet_dir = "...")` with
  `snapshot_to_parquet(root_dir = "...")`.

* `build_corpus_index()` has a new signature. The old `corpus_dir` parameter
  is replaced by `root_dir`. The function now delegates to the
  `openalex-snapshot` binary.  **Migration:** replace
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
