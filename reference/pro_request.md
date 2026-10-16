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
  error_log = NULL,
  resume = FALSE,
  via = c("url", "oqo"),
  inconsistency_on_resume = c("error", "warning", "ignore", "oldest", "newest")
)
```

## Arguments

- query_url:

  The URL of the API query or a list of URLs returned from
  [`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md).

- pages:

  The maximum number of pages (of 200 records) downloaded per query; for
  a list, the limit applies to each leaf query. 100000 pages are
  20,000,000 records; for more, use the snapshot instead. If `NULL`, all
  pages will be downloaded.

- output:

  directory where the JSON files are saved. Required (the default `NULL`
  stops with an error) unless `count_only = TRUE`.

- overwrite:

  Logical. If `TRUE`, `output` will be deleted before downloading. For a
  list `query_url`, the entire top-level `output` directory is removed
  upfront. If `FALSE` (the default) and `output` already exists, the
  function stops with an error.

- api_key:

  Character string API key or `NULL`. Defaults to
  [`pro_api_key()`](https://openalexpro.github.io/openalexPro/reference/pro_api_key.md).
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

- resume:

  Logical. When `TRUE`, keep an existing `output` and download only what
  is missing: finished queries are skipped (detected by the
  `00_in.progress` sentinel each query directory carries while it is
  being written), and an interrupted query continues after its last
  saved page, using the cursor stored in its `_paging.json` (the message
  says how old it is). If that state cannot be trusted, or for samples
  and semantic search, the query is fetched again from page 1. A single
  URL is treated as one query. Default `FALSE`.

- via:

  How each query is sent. `"url"` (default): as a GET request with the
  query in the URL, as built by
  [`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md).
  `"oqo"`: translated once (free) into an OpenAlex Query Object and sent
  via POST, with the same results. It has no URL length limit, accepts
  more than 100 values per filter (so
  `pro_query(..., chunk_limit = 200)` fetches a DOI or ID list in about
  one page per chunk), checks the query before any credits are spent,
  and records the exact query in `_query.json`. Single records
  (`works/W123`) are always fetched via GET.

- inconsistency_on_resume:

  What to do when a query that was resumed in the middle turns out
  inconsistent, because OpenAlex's data changed between the sessions:
  records that appear twice (found exactly, by work ID) or missing
  records (only as a net difference to OpenAlex's current count – a
  record lost and another added cancel out). `"error"` (default) stops;
  nothing is lost, and a rerun with `resume = TRUE` and another value
  applies that choice without downloading again. `"warning"` keeps both
  copies and warns, `"ignore"` keeps both silently, `"oldest"` /
  `"newest"` keep the first / last downloaded copy (removing the other
  from its page file) and warn about missing records.

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

If one query of a list fails (e.g. HTTP 404 for an ID that does not
exist), the other queries still complete. At the end, one error names
each failed query with OpenAlex's reason. The failed queries keep their
`00_in.progress`, so `resume = TRUE` fetches only them again.

Pages are fetched with cursor paging. A `per_page` in the query is kept;
`page` and `cursor` are replaced, with a warning. A `sample` is fetched
by page number, as OpenAlex ends cursor paging of a sample after the
first page; if it spans several pages and has no `seed`, one is chosen
and reported. Semantic search (`search.semantic`) is fetched as its
single page of at most 50 results.

Each query directory also gets a record of the query: `_query.json` (the
URL, how it was sent, the query as OpenAlex ran it as OQL and OQO,
records, requests, credits, cost, time), and for papers `_query_oql.txt`
and a formatted, self-contained `_query_oql.html` with the query in
OpenAlex's readable query language (OQL). The OQL is translated back and
compared with the query that ran; the files say whether it reproduces it
exactly. Single records get only `_query.json`. For a list of queries,
`_queries_oql.txt` and `_queries_oql.html` at the top of `output`
summarise all queries (records, exactness, OQL), e.g. for a paper's
supplement.
