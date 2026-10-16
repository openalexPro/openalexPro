# Fetch and convert OpenAlex data to Parquet

Convenience wrapper that downloads records from OpenAlex via
[`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
and converts them directly to an Apache Parquet dataset via
[`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md).
No intermediate JSONL files are written.

## Usage

``` r
pro_fetch(
  query_url,
  pages = 10000,
  project_folder = NULL,
  overwrite = FALSE,
  api_key = pro_api_key(),
  delete_input = TRUE,
  workers = 1,
  download_workers = workers,
  verbose = FALSE,
  progress = TRUE,
  enrich = TRUE,
  count_only,
  error_log = NULL,
  resume = FALSE,
  via = c("url", "oqo"),
  inconsistency_on_resume = c("error", "warning", "ignore", "oldest", "newest"),
  compact_parquet = NULL
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
  [`pro_api_key()`](https://openalexpro.github.io/openalexPro/reference/pro_api_key.md).
  If `NULL` or `""`, requests are sent without an API key (subject to
  OpenAlex's unauthenticated limits).

- delete_input:

  Logical. If `TRUE` (the default), the `json` subfolder is deleted
  after successful conversion to Parquet.

- workers:

  Number of parallel workers for the conversion to Parquet (CPU and
  memory bound), and by default also for the download. Default 1.

- download_workers:

  Number of parallel workers for the download, used when `query_url` is
  a list. Defaults to `workers`. Downloads are limited by the API rather
  than the machine, so a few (e.g. 2–4) are usually enough, while the
  conversion can use more.

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

- resume:

  Logical. When `TRUE`, keep existing `json` and `parquet` subfolders
  and complete an interrupted run: only leaf queries that did not finish
  are downloaded again, and only missing Parquet files are converted. A
  finished run is returned unchanged. `overwrite` is ignored. Default
  `FALSE`.

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

- compact_parquet:

  `NULL` (default) keeps one Parquet file per API page. A number, e.g.
  `250000`, combines each query's page files into files of up to that
  many records once every file has converted – much faster to read. See
  [`pro_compact_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_compact_parquet.md).

## Value

Invisibly, the normalised path of the `parquet` subfolder inside
`project_folder`.

## Details

The function

- downloads records from OpenAlex via
  [`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
  into a `"json"` subfolder of `project_folder`, and

- converts the JSON files to an Apache Parquet dataset via
  [`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)
  into a `"parquet"` subfolder.

**This function assumes `count_only == FALSE`**

## See also

[`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
for the download step,
[`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)
for the conversion step,
[`pro_compact_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_compact_parquet.md)
to compact an existing dataset.

## Examples

``` r
if (FALSE) { # \dontrun{
# Combine each query's page files into files of up to 250,000 records,
# which are much faster to read
pro_fetch(
  pro_query(search = "coral reef", from_publication_date = "2020-01-01"),
  project_folder = "coral_reef",
  compact_parquet = 250000
)
} # }
```
