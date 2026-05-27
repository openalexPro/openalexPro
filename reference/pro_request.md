# Fetch works from OpenAlex

All returned values from OpenAlex will be saved as json files in the
`output` directory and the return value is the directory of the json
files.

## Usage

``` r
pro_request(
  query_url,
  pages = 1e+05,
  output = NULL,
  overwrite = FALSE,
  api_key = pro_api_key(),
  workers = 1,
  verbose = FALSE,
  progress = TRUE,
  count_only = FALSE,
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

- output:

  directory where the JSON files are saved. Default is a temporary
  directory. Needs to be specified.

- overwrite:

  Logical. If `TRUE`, `output` will be deleted before downloading. For a
  list `query_url`, the entire top-level `output` directory is removed
  upfront. If `FALSE` (the default) and `output` already exists, the
  function stops with an error.

- api_key:

  Character string API key or `NULL`. Defaults to
  [`pro_api_key()`](https://rkrug.github.io/openalexPro/reference/pro_api_key.md).
  If `NULL` or `""`, requests are sent without an API key (subject to
  OpenAlex's unauthenticated limits).

- workers:

  Number of parallel workers to use if `query_url` is a list. Defaults
  to 1.

- verbose:

  Logical indicating whether to show verbose messages.

- progress:

  Logical indicating whether to show a progress bar. Default `TRUE`.

- count_only:

  return count only as a data.frame.

- error_log:

  location of error log of API calls. (default: `NULL` (none)).

## Value

If `count_only` is `FALSE` (the default) the complete path to the
expanded and normalized `output`. If `count_only` is `TRUE`, a
data.frame with metadata about the query (count, db_response_time_ms,
page, per_page, error). When `query_url` is a list, an additional
`query` column identifies each query.

## Details

If query_url is a list, the function is called for each element of the
list in parallel using a maximum of `workers` parallel R sessions. The
results from the individual URLs in the list are returned in a folder
named after the names of the list elements in the `output` folder.

When starting the download, a file `00_in.progress` which is deleted
upon completion.
