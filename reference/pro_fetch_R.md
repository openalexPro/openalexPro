# Fetch and convert OpenAlex data to Parquet (pure-R implementation)

Pure-R/DuckDB fallback for
[`pro_fetch()`](https://rkrug.github.io/openalexPro/reference/pro_fetch.md).
Uses
[`pro_request_parquet_R()`](https://rkrug.github.io/openalexPro/reference/pro_request_parquet_R.md)
for the conversion step instead of the Rust-backed
[`pro_request_parquet()`](https://rkrug.github.io/openalexPro/reference/pro_request_parquet.md).
Both functions share the same argument signature and produce identical
output.

## Usage

``` r
pro_fetch_R(
  query_url,
  pages = 10000,
  project_folder = NULL,
  overwrite = FALSE,
  api_key = pro_api_key(),
  delete_input = TRUE,
  workers = 1,
  verbose = FALSE,
  progress = TRUE,
  enrich = TRUE,
  count_only,
  error_log = NULL
)
```

## Arguments

- query_url:

  The URL of the API query or a list of URLs returned from
  [`pro_query()`](https://rkrug.github.io/openalexPro/reference/pro_query.md).

- pages:

  The number of pages to be downloaded. The default is set to 10000,
  which would be 2,000,000 works. It is recommended to not increase it
  beyond 100000 due to server load and to use the snapshot instead. If
  `NULL`, all pages will be downloaded. Default: 100000.

- project_folder:

  Directory where intermediate (`json`) and final (`parquet`) results
  are stored. If it does not exist, it is created. If `NULL`, a
  temporary directory is created.

- overwrite:

  Logical. If `TRUE`, the `json` and `parquet` subdirectories are
  deleted from `project_folder` before the pipeline starts. If `FALSE`
  (the default) and any of those subdirectories already exist, the
  function stops with an error.

- api_key:

  Character string API key or `NULL`. Defaults to
  [`pro_api_key()`](https://rkrug.github.io/openalexPro/reference/pro_api_key.md).
  If `NULL` or `""`, requests are sent without an API key (subject to
  OpenAlex's unauthenticated limits).

- delete_input:

  Logical. If `TRUE` (the default), the `json` subfolder is deleted
  after successful conversion to Parquet.

- workers:

  Number of parallel workers to use if `query_url` is a list. Defaults
  to 1.

- verbose:

  Logical indicating whether to show verbose messages.

- progress:

  Logical indicating whether to show a progress bar. Default `TRUE`.

- enrich:

  Logical. When `TRUE` (the default) and the inferred schema contains
  `abstract_inverted_index` / `authorships` / `publication_year`, add
  `abstract` and `citation` computed columns.

- count_only:

  Do not use it here. The function will abort if set to `TRUE` and give
  a warning if `FALSE`.

- error_log:

  location of error log of API calls. (default: `NULL` (none)).

## Value

Invisibly, the normalised path of the `parquet` subfolder inside
`project_folder`.

## See also

[`pro_fetch()`](https://rkrug.github.io/openalexPro/reference/pro_fetch.md)
