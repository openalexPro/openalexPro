# `pro_request()` - Background and Technical Documentation

## Introduction

The
[`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
function is the core data retrieval component of the `openalexPro`
workflow. It downloads data from the OpenAlex API and saves it as JSON
files to disk, enabling processing of datasets too large to fit in
memory.

This vignette provides a comprehensive guide to using
[`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
and related functions, including:

- Basic usage patterns
- Progress bars and parallel processing
- The complete data pipeline
  ([`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
  →
  [`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md))
- Internal architecture and flow diagrams
- Error handling and retry logic

## Authentication

OpenAlex offers limited API access without credentials. Free API keys
with substantially higher rate limits can be obtained from the [OpenAlex
website](https://openalex.org). Premium API access with even higher
limits can also be purchased.

`openalexPro` uses environment variables for credentials (recommended):

``` r

# Set credentials (typically in your .Renviron file)
Sys.setenv(openalexPro.api_key = "your-api-key-here")

# Validate your credentials
pro_validate_credentials()
```

You can also pass credentials directly to functions:

``` r

pro_request(
  query_url = url,
  output = "data/json",
  api_key = "your-api-key"
)
```

To force unauthenticated mode for a call, pass `api_key = NULL` (or
`""`):

``` r

pro_request(
  query_url = url,
  output = "data/json",
  api_key = NULL
)
```

## Basic Usage

### Simple Download

The most basic usage requires a query URL (from
[`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md))
and an output directory:

``` r

library(openalexPro)

# Build query
url <- pro_query(
  entity = "works",
  search = "climate change",
  from_publication_date = "2023-01-01"
)

# Download data
pro_request(
  query_url = url,
  output = "data/json"
)
```

### Get Count Only

To check how many results a query returns without downloading:

``` r

# Get count for a single query
count <- pro_request(
  query_url = url,
  count_only = TRUE
)
count$count
# [1] 45632

# Or use pro_count() directly
meta <- pro_count(query_url = url)
meta
#   count db_response_time_ms page per_page error
# 1 45632                  42    1        1    NA
```

### Download with Progress Bar

Progress bars are enabled by default:

``` r

pro_request(
  query_url = url,
  output = "data/json",
  progress = TRUE # Default
)
# Downloading ████████████████░░░░░░░░░░░░░░░░ 120/229 [1m 23s]
```

For a list of queries, the progress bar counts queries; each one
advances it in fractions as its pages arrive. No extra count requests
are made up front.

### Limiting Pages

By default,
[`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
downloads up to 100,000 pages per query (20 million records at 200 per
page;
[`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
defaults to 10,000 pages). For a list of queries the limit applies to
each query. You can adjust this:

``` r

# Download only first 100 pages (20,000 records)
pro_request(
  query_url = url,
  output = "data/json",
  pages = 100
)

# Download all pages (use with caution for large queries!)
pro_request(
  query_url = url,
  output = "data/json",
  pages = NULL
)
```

## Handling Chunked Queries

When
[`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)
returns a list of URLs (due to automatic chunking of large ID lists),
[`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
handles them seamlessly:

``` r

# Query with many DOIs triggers automatic chunking
dois <- paste0("10.1234/example", 1:150)
urls <- pro_query(entity = "works", doi = dois)

length(urls) # 3 chunks
names(urls) # "chunk_1", "chunk_2", "chunk_3"

# pro_request handles the list automatically
pro_request(
  query_url = urls,
  output = "data/json"
)
# Creates: data/json/chunk_1/, data/json/chunk_2/, data/json/chunk_3/
```

### Nested List Queries

[`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
also accepts **nested lists** of URLs. Each nesting level is preserved
as a subdirectory, and
[`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)
converts the directory depth to hive-style partition keys:

| Directory depth | Partition key     |
|-----------------|-------------------|
| 1               | `query=<name>`    |
| 2               | `query_l2=<name>` |
| 3               | `query_l3=<name>` |

``` r

# Build a nested query list manually
queries <- list(
  year_2022 = pro_query(entity = "works", publication_year = 2022),
  year_2023 = pro_query(entity = "works", publication_year = 2023),
  institutions = list(
    usa = pro_query(entity = "institutions", country_code = "US"),
    uk  = pro_query(entity = "institutions", country_code = "GB")
  )
)

# Download: creates nested subdirectory structure
pro_request(
  query_url = queries,
  output    = "data/json"
)
# Creates:
#   data/json/year_2022/
#   data/json/year_2023/
#   data/json/institutions/usa/
#   data/json/institutions/uk/

# After parquet conversion the dataset is hive-partitioned:
#   data/parquet/query=year_2022/
#   data/parquet/query=year_2023/
#   data/parquet/query=institutions/query_l2=usa/
#   data/parquet/query=institutions/query_l2=uk/

# Filter by partition
ds <- arrow::open_dataset("data/parquet")
ds |> dplyr::filter(query == "year_2022")
ds |> dplyr::filter(query == "institutions", query_l2 == "usa")
```

[`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
inherits nested list support automatically — you can pass a nested list
directly as `query_url`.

### Parallel Downloads

For chunked queries, enable parallel processing:

``` r

pro_request(
  query_url = urls,
  output = "data/json",
  workers = 4 # Use 4 parallel workers
)
```

Each query is handed to the next free worker, so a few large queries do
not leave the other workers idle. Pages within one query are always
fetched one after another (by cursor, or by page number for a `sample`),
so `workers` only helps with a list of queries.

If one query of a list fails (e.g. HTTP 404 for an ID that does not
exist), the others still complete. At the end, one error names each
failed query with OpenAlex’s reason; `resume = TRUE` then fetches only
those again.

### Resuming an Interrupted Download

With `resume = TRUE`, an existing `output` is kept and only queries that
did not finish are downloaded. Each query directory carries a
`00_in.progress` marker while it is being written. This works for a
single URL as well as for lists, and `pro_fetch(resume = TRUE)` also
completes an interrupted Parquet conversion:

``` r

pro_request(query_url = urls, output = "data/json", resume = TRUE)
pro_fetch(query_url = urls, project_folder = "data", resume = TRUE)
```

#### Continuing in the middle of a query

An interrupted query does not start again: it **continues after its last
saved page**. OpenAlex’s cursors are positions in the sort order and do
not expire, but they contain nothing about the query, so after each page
the exact query and the cursor are saved in `_paging.json`, together
with the time the cursor was created:

    Resuming `json` at page 4001 with a cursor from 2026-10-14T08:31:48Z
    (3.2 hours ago). Records that changed since then may appear twice or be
    missing; see `inconsistency_on_resume`. ...

Whatever cannot be trusted – a damaged `_paging.json`, a different
query, missing pages – leads back to fetching the query again from page
1, with a message saying why. Samples and semantic search always start
again (they are at most 50 requests). To fetch a query whole on purpose,
delete its `_paging.json`.

#### Inconsistencies after a resume

Between the sessions OpenAlex’s data can change – citation counts, new
works – and records can move across the cursor position: they then
appear twice, or are missing. After a resumed query,
[`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
checks:

- **duplicates**, exactly, by work ID across all pages of the query;
- **missing records**, as the **net** difference to the number OpenAlex
  now reports. A record lost and another one added since cancel out, so
  this check cannot see every gap.

`inconsistency_on_resume` decides what happens:

| Value               | Duplicates                     | Missing records (net) |
|---------------------|--------------------------------|-----------------------|
| `"error"` (default) | stop                           | stop                  |
| `"warning"`         | keep both copies, warn         | warn                  |
| `"ignore"`          | keep both copies               | –                     |
| `"oldest"`          | keep the first downloaded copy | warn                  |
| `"newest"`          | keep the last downloaded copy  | warn                  |

With `"error"`, nothing is lost: everything stays on disk, and a rerun
with `resume = TRUE` and another value applies that choice **without
downloading anything again**. `"oldest"` and `"newest"` remove the other
copy from its page file. The resume and the result of the check are
recorded in the query’s `_query.json` (`resumed`, `duplicates`,
`duplicates_removed`, `missing_net`, …).

``` r

# after an "error": keep the newest copy of each duplicate, no download
pro_request(query_url = urls, output = "data/json", resume = TRUE,
            inconsistency_on_resume = "newest")
```

### Lossless Queries with `via = "oqo"`

By default (`via = "oqo"`, also for
[`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
and
[`pro_count()`](https://openalexpro.github.io/openalexPro/reference/pro_count.md))
each query is translated once into an OpenAlex Query Object (OQO) – the
form OpenAlex compiles every query to anyway – and every page is sent as
a POST request with the OQO in the body:

`via = "url"` sends every query as a GET request with the query in the
URL instead:

``` r

pro_fetch(urls, project_folder = "data", via = "url")
```

- **Same results.** The test suite downloads the same queries both ways
  and compares the complete result sets (filters, boolean, wildcard and
  proximity search, samples, grouped results, other entities, DOI lists,
  OQL and OQO input). Only semantic search can differ by a work or two –
  as it does between two identical GET requests.
- **Checked before spending credits.** The translation is free and
  validates the query; an invalid query stops with OpenAlex’s message
  before any paid request.
- **No URL limits.** A URL may carry at most 100 values per filter (with
  `via = "url"`,
  [`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
  stops early when a filter has more). An OQO may carry more, so
  `pro_query(..., chunk_limit = 200)` fetches a DOI or OpenAlex ID list
  in about one request per chunk – and the chunks still download in
  parallel with `workers`.
- **The exact query is recorded** (see below).

Single records (`works/W123`) are always fetched with GET; they are
free.

### What Was Asked, and What It Cost

Each query directory gets a `_query.json`: the URL (without the key),
how it was sent (`via`), the query as OpenAlex ran it (`oql`, `oqo`),
the number of records, requests and credits, the cost in USD, and when
it ran.
[`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)
copies it into the matching Parquet partition, so it is kept when the
JSON files are deleted. At the end,
[`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
reports the total, e.g. `i 12 requests, 12 credits ($0.0012)`. Arrow and
DuckDB ignore the file (leading underscore, not `.parquet`).

For methods sections and supplements, each query directory also gets the
query in OpenAlex’s readable query language (OQL), in two forms:

- `_query_oql.txt`: plain text, ready to paste into a paper, e.g.

      # OpenAlex query (OQL)
      # Records: 141 | Downloaded: 2026-10-14 (UTC) | openalexPro 0.13.0
      # Exact: this OQL translates back to exactly the query that ran.

      get works where full text has (microbio*)
        and source is [Nature](S137773608)
        and published in 2020

- `_query_oql.html`: the same, nicely formatted with highlighted
  keywords and OpenAlex IDs linked to their records; self-contained (no
  scripts, no external resources), with the exact OQO and the request
  URL in collapsible sections.

The OQL is OpenAlex’s own rendering of the query that ran. Because that
rendering can be lossy in some details, it is translated back and
compared: the header says **Exact** if the printed OQL reproduces the
query, otherwise **Not exact** (then the OQO in `_query.json` is the
exact query) or **Not checked** (if OpenAlex’s free `/query` endpoint
could not be reached). Single records (`works/W123`) get no OQL files.
Like `_query.json`, both files are copied into the Parquet partition.

For a list of queries, `_queries_oql.txt` and `_queries_oql.html` at the
top of the output summarise all queries for a supplement: in the order
of the list, each query’s name, number of records, whether its OQL is
exact, and the OQL itself, with totals (records, credits, cost) in the
header; the HTML adds an overview table linking to each query. Queries
skipped by `resume = TRUE` are included, failed ones are listed as “Not
downloaded”. Both files are copied to the top of the Parquet folder.

The API key is sent as an `Authorization: Bearer` header, never in the
URL, so it does not appear in logs, error messages or recorded test
responses.

## Function Parameters Reference

| Parameter | Type | Default | Description |
|----|----|----|----|
| `query_url` | character/list | required | URL or list of URLs from [`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md) |
| `pages` | integer/NULL | 100000 | Max pages per query. `NULL` = all pages |
| `output` | character | required | Directory for JSON output files |
| `overwrite` | logical | FALSE | Delete existing output directory if it exists |
| `api_key` | character/NULL | env var | Optional API key. If `NULL` or `""`, requests are sent without key. |
| `workers` | integer | 1 | Parallel workers for list queries |
| `verbose` | logical | FALSE | Show detailed messages |
| `progress` | logical | TRUE | Show progress bar |
| `count_only` | logical | FALSE | Return count without downloading |
| `error_log` | character/NULL | NULL | Path for error log file |
| `resume` | logical | FALSE | Keep `output`, refetch only unfinished queries |
| `via` | character | “oqo” | `"oqo"` (translated once, sent via POST) or `"url"` (GET) |

## pro_request() Architecture

### High-Level Flow

``` mermaid
flowchart TD
    Start([pro_request called]) --> CheckList{query_url<br/>is list?}

    CheckList -->|Yes| ListMethod[LIST METHOD:<br/>Multiple queries]
    CheckList -->|No| ScalarMethod[SCALAR METHOD:<br/>Single query]

    %% List Method Branch
    ListMethod --> SetupFutures[Setup future plan<br/>based on workers]
    SetupFutures --> CountOnly1{count_only?}

    CountOnly1 -->|Yes| ParallelCount["Parallel pro_count()<br/>for each URL"]
    ParallelCount --> ReturnCounts([Return named vector])

    CountOnly1 -->|No| ParallelDownload[future_lapply:<br/>fetch_query_pages<br/>for each URL]
    ParallelDownload --> ReturnOutput([Return output path])

    %% Scalar Method Branch
    ScalarMethod --> CountOnly2{count_only?}
    CountOnly2 -->|Yes| SingleCount[pro_count]
    SingleCount --> ReturnMeta([Return metadata])

    CountOnly2 -->|No| FetchPages[fetch_query_pages<br/>with CLI progress]
    FetchPages --> ReturnPath([Return output path])

    style Start fill:#e1f5e1
    style ReturnCounts fill:#e1f5e1
    style ReturnOutput fill:#e1f5e1
    style ReturnMeta fill:#e1f5e1
    style ReturnPath fill:#e1f5e1
    style ListMethod fill:#cce5ff
    style ScalarMethod fill:#fff3cd
```

### fetch_query_pages() Internal Helper

The `fetch_query_pages()` function handles the actual page-by-page
download:

``` mermaid
flowchart TD
    Start([fetch_query_pages called]) --> CheckOutput{output<br/>exists?}

    CheckOutput -->|Yes, overwrite=FALSE| ErrorExists[Stop: Directory exists]
    CheckOutput -->|Yes, overwrite=TRUE| DeleteDir[Delete existing<br/>directory]
    CheckOutput -->|No| CreateDir[Create output<br/>directory]

    DeleteDir --> CreateDir
    CreateDir --> CreateProgress[Create<br/>00_in.progress file]
    CreateProgress --> BuildRequest[Build httr2 request<br/>api_key optional]

    BuildRequest --> FirstRequest[First API call<br/>to inspect meta]
    FirstRequest --> CheckSingle{Single record<br/>response?}

    CheckSingle -->|Yes| SaveSingle[Save single_1.json]
    SaveSingle --> Success1([Success: Return path])

    CheckSingle -->|No| CheckGroup{meta.groups_count<br/>set?}
    CheckGroup -->|Yes| PrefixGroup[Prefix:<br/>group_by_page_]
    CheckGroup -->|No| PrefixResults[Prefix:<br/>results_page_]
    PrefixGroup --> CalcMaxPages[Calculate max_pages<br/>from meta]
    PrefixResults --> CalcMaxPages
    CalcMaxPages --> StartProgress[Start CLI<br/>progress bar]
    StartProgress --> SaveFirst[Save first page:<br/>PREFIX1.json]

    SaveFirst --> PageLoop{More pages?<br/>next_cursor exists?}

    PageLoop -->|Yes| CheckLimit{page > pages<br/>limit?}
    CheckLimit -->|Yes| Done[Exit loop]
    CheckLimit -->|No| NextRequest[Request next page<br/>by cursor, or page<br/>number for a sample]
    NextRequest --> SavePage[Save<br/>PREFIXN.json]
    SavePage --> UpdateProgress[Update<br/>progress bar]
    UpdateProgress --> PageLoop

    PageLoop -->|No| Done
    Done --> DeleteProgressFile[Delete<br/>00_in.progress]
    DeleteProgressFile --> Success2([Success: Return path])

    style Start fill:#e1f5e1
    style Success1 fill:#e1f5e1
    style Success2 fill:#e1f5e1
    style ErrorExists fill:#f8d7da
    style PageLoop fill:#fff3cd
```

Whether a query is grouped is decided from the first response (grouped
responses carry a numeric `meta$groups_count`), not from the URL, so
grouping inside an OQL / OQO query is detected as well. Grouped pages
are saved as `group_by_page_N.json`.

### api_call() Retry Logic

All HTTP requests go through `api_call()` which provides robust retry
logic. Network failures (dropped connection, curl errors) are retried
like transient statuses, and a transfer that stalls (less than 1 byte/s
for 120 s) is aborted and retried. A 429 caused by the daily budget is
not retried (see below):

``` mermaid
flowchart TD
    Start([api_call]) --> ConfigRetry[Configure retry:<br/>max 10 attempts<br/>exponential backoff]

    ConfigRetry --> Perform[Perform request]
    Perform --> CheckStatus{HTTP Status?}

    CheckStatus -->|200 OK| ReturnSuccess([Return response])

    CheckStatus -->|429 rate, 500-504,<br/>network failure| Transient[Transient error:<br/>wait and retry]
    CheckStatus -->|429 budget| Abort0([Abort: budget<br/>and reset time])
    Transient --> RetryCount{Retries<br/>exhausted?}
    RetryCount -->|No| Perform
    RetryCount -->|Yes| LogError[Log error]
    LogError --> Abort1([Abort with error])

    CheckStatus -->|400| Check400[Check if HTML<br/>response requested]
    Check400 -->|Yes + HTML| Return400([Return for inspection])
    Check400 -->|No| Abort2([Abort with error])

    CheckStatus -->|Other 4xx/5xx| LogOther[Log unexpected status]
    LogOther --> Abort3([Abort with error])

    style Start fill:#e1f5e1
    style ReturnSuccess fill:#e1f5e1
    style Return400 fill:#fff3cd
    style Abort1 fill:#f8d7da
    style Abort2 fill:#f8d7da
    style Abort3 fill:#f8d7da
    style Transient fill:#cce5ff
```

#### Transient Error Handling

The following HTTP status codes are considered transient and trigger
automatic retry:

| Status | Meaning | Action |
|----|----|----|
| 429 | Too Many Requests (more than 100 requests/s) | Wait with exponential backoff |
| 500 | Internal Server Error | Retry up to 10 times |
| 502 | Bad Gateway | Retry up to 10 times |
| 503 | Service Unavailable | Retry up to 10 times |
| 504 | Gateway Timeout | Retry up to 10 times |

Not retried, because retrying cannot help:

| Status | Meaning | Behaviour |
|----|----|----|
| 429 | Daily budget used up (`X-RateLimit-Remaining` is 0), or `not_enough_credits` (the query costs more than is left) | Abort at once; the error says when the budget resets (midnight UTC) |
| 400, 403, 404 | Invalid query, no access, not found | Abort; the error includes OpenAlex’s own message, e.g. which filter name is invalid, or the OQL parse error |

## Output File Structure

After a successful download, the output directory contains:

    data/json/
    ├── results_page_1.json
    ├── results_page_2.json
    ├── results_page_3.json
    └── ...

For chunked queries (list of URLs):

    data/json/
    ├── chunk_1/
    │   ├── results_page_1.json
    │   ├── results_page_2.json
    │   └── ...
    ├── chunk_2/
    │   ├── results_page_1.json
    │   └── ...
    └── chunk_3/
        └── ...

### Progress Tracking

During download, a `00_in.progress` file exists in the output directory.
This file is automatically deleted upon successful completion. If
present, it indicates:

- Download is still in progress, OR
- Download was interrupted and is incomplete

`resume = TRUE` uses this marker to decide which queries to fetch again.

## The Complete Data Pipeline

### Pipeline Overview

``` mermaid
flowchart LR
    subgraph Step1[Step 1: Query]
        PQ[pro_query]
    end

    subgraph Step2[Step 2: Download]
        PR[pro_request]
    end

    subgraph Step3[Step 3: Convert]
        PRP[pro_request_parquet]
    end

    subgraph Step4[Step 4: Analyze]
        DB[(DuckDB)]
    end

    PQ -->|URL/URLs| PR
    PR -->|JSON files| PRP
    PRP -->|Parquet dataset| DB

    style Step1 fill:#e1f5e1
    style Step2 fill:#cce5ff
    style Step3 fill:#fff3cd
    style Step4 fill:#e1f5e1
```

[`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
runs steps 2 and 3 in one call.

### Complete Example

``` r

library(openalexPro)

# Step 1: Build query
urls <- pro_query(
  entity = "works",
  search = "machine learning healthcare",
  from_publication_date = "2020-01-01",
  type = "article",
  select = c(
    "ids", "title", "abstract_inverted_index", "publication_year",
    "authorships", "cited_by_count"
  )
)

# Step 2: Download JSON from API
pro_request(
  query_url = urls,
  output = "data/json",
  pages = 1000,
  progress = TRUE
)

# Step 3: Convert to Parquet (adds `abstract` and `citation` columns)
pro_request_parquet(
  input_json = "data/json",
  output = "data/parquet",
  progress = TRUE,
  workers = 4
)

# Step 4: Query with DuckDB
library(duckdb)
con <- dbConnect(duckdb())
dbGetQuery(
  con,
  "
  SELECT title, publication_year, cited_by_count
  FROM read_parquet('data/parquet/**/*.parquet')
  ORDER BY cited_by_count DESC
  LIMIT 10
"
)
```

------------------------------------------------------------------------

## pro_request_parquet()

### Purpose

Converts the JSON files written by
[`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
into an Apache Parquet dataset using DuckDB, one Parquet file per JSON
file, with no intermediate files. During conversion it:

1.  **Reconstructs abstracts** from `abstract_inverted_index` (column
    `abstract`)
2.  **Generates citation strings** such as “Smith et al. (2023)” (column
    `citation`)
3.  **Adds a `page` column** for tracking data provenance
4.  **Optionally adds constant columns** (`add_columns`)

Abstracts and citations are only added for works, when the needed fields
are present and `enrich = TRUE` (the default).
[`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
calls
[`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
and then
[`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md).

### Function Signature

``` r

pro_request_parquet(
  input_json = NULL,
  output = NULL,
  add_columns = list(),
  overwrite = FALSE,
  verbose = TRUE,
  progress = TRUE,
  delete_input = FALSE,
  sample_size = 1000,
  workers = NULL,
  enrich = TRUE,
  schema = "auto",
  resume = FALSE,
  on_error = c("error", "warn", "ignore"),
  memory_limit = NULL,
  retry_memory_limit = NULL
)
```

### Parameters

| Parameter | Type | Default | Description |
|----|----|----|----|
| `input_json` | character | required | Directory of JSON files from [`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md) |
| `output` | character | required | Output directory for the Parquet dataset |
| `add_columns` | list | [`list()`](https://rdrr.io/r/base/list.html) | Named character scalars added as constant columns |
| `overwrite` | logical | FALSE | Overwrite an existing `output` |
| `verbose` | logical | TRUE | Show progress messages |
| `progress` | logical | TRUE | Show a progress bar |
| `delete_input` | logical | FALSE | Delete `input_json` after a complete conversion (kept if any file failed) |
| `sample_size` | integer | 1000 | Records per file sampled for schema inference (`-1` = all) |
| `workers` | integer/NULL | NULL | Parallel workers; `NULL` or 1 runs sequentially |
| `enrich` | logical | TRUE | Add `abstract` and `citation` columns for works |
| `schema` | character/NULL | “auto” | Baseline schema for ambiguous column types (see below) |
| `resume` | logical | FALSE | Keep `output` and convert only missing files |
| `on_error` | character | “error” | What to do with files that still fail: `"error"`, `"warn"`, `"ignore"` |
| `memory_limit` | character/NULL | NULL | DuckDB memory limit per worker; derived from RAM and `workers` |
| `retry_memory_limit` | character/NULL | NULL | Memory limit for the sequential retry pass |

### Internal Flow

``` mermaid
flowchart TD
    Start([pro_request_parquet]) --> Prepare[Prepare output:<br/>overwrite / resume<br/>create 00_in.progress]
    Prepare --> Discover[Find JSON files<br/>results / group_by / single]
    Discover --> Infer[Infer schema from<br/>up to 20 sampled files]
    Infer --> Baseline[Resolve ambiguous types<br/>with baseline schema]
    Baseline --> Convert[Convert each file<br/>DuckDB COPY to .part<br/>rename on success]
    Convert --> Failed{Any file<br/>failed?}
    Failed -->|No| Done[Delete input if<br/>delete_input = TRUE<br/>remove 00_in.progress]
    Failed -->|Yes, workers > 1| Retry[Retry failed files<br/>sequentially, full memory]
    Failed -->|Yes, sequential| OnError
    Retry --> Still{Still failing?}
    Still -->|No| Done
    Still -->|Yes| OnError[on_error:<br/>error / warn / ignore<br/>keep input and 00_in.progress]
    Done --> Return([Return output path])
    OnError --> Return

    style Start fill:#e1f5e1
    style Return fill:#e1f5e1
    style Retry fill:#fff3cd
    style OnError fill:#f8d7da
```

### Schema Harmonization

Different OpenAlex records can have different field structures. For
example:

- A field can be a struct in one record and `null` in all records of
  another page
- Nested arrays can be empty in one file and populated in another

[`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)
therefore infers one schema from a sample of up to 20 files
(`sample_size` records per file) and converts every file with these
column types, so all Parquet files can be read together:

``` mermaid
flowchart LR
    subgraph Input[Input JSON Files]
        F1["File 1:<br/>location: struct"]
        F2["File 2:<br/>location: null"]
        F3["File 3:<br/>location: struct"]
    end

    subgraph Schema[Schema Inference]
        Sample[Sample up to<br/>20 files]
        Describe[DuckDB<br/>DESCRIBE]
        Baseline[Baseline schema<br/>for JSON-typed columns]
    end

    subgraph Output[Unified Schema]
        Unified["location: struct<br/>(applied to all files)"]
    end

    F1 --> Sample
    F2 --> Sample
    F3 --> Sample
    Sample --> Describe
    Describe --> Baseline
    Baseline --> Unified

    style Input fill:#f8d7da
    style Schema fill:#cce5ff
    style Output fill:#e1f5e1
```

When DuckDB can only infer the generic `JSON` type for a column (for
example because it is `null` in every sampled record), the `schema`
argument supplies the type:

- `"auto"` (default): detect the entity from the columns and use the
  matching baseline schema from the user cache
  (`oa_schema(update = TRUE)`) or the schemas bundled with the package
- `"none"` or `NULL`: use DuckDB’s inference only
- a CSV file (columns `col_name`, `col_type`) or a directory of
  `<entity>.csv` files

### Failure Handling and Resume

Each file is converted on its own, so one problematic page does not stop
the others:

- Every file is written to a `.part` sidecar and renamed only on
  success, so a Parquet file that exists is always complete.
- With `workers > 1`, files that fail (typically from memory pressure on
  large, deeply nested pages) are retried once, sequentially and with
  the whole memory budget.
- Files that still fail are handled according to `on_error`: `"error"`
  (default) stops and names them, `"warn"` warns and returns, `"ignore"`
  is silent. In every case the JSON input is kept and `00_in.progress`
  stays in `output`.
- `resume = TRUE` keeps an existing `output` and converts only the files
  that are missing:

``` r

pro_request_parquet(
  input_json = "data/json",
  output = "data/parquet",
  resume = TRUE
)
```

With `workers > 1`, each worker gets its own DuckDB connection with a
share of the memory budget, one thread and a private temporary
directory.

### Output Structure

For a flat (single-URL) input:

    data/parquet/
    ├── results_page_1.parquet
    ├── results_page_2.parquet
    └── ...

For a flat list of URLs (e.g. `chunk_1`, `chunk_2` from auto-chunking):

    data/parquet/
    ├── query=chunk_1/
    │   ├── results_page_1.parquet
    │   └── results_page_2.parquet
    └── query=chunk_2/
        └── results_page_1.parquet

For a two-level nested list:

    data/parquet/
    ├── query=year_2022/
    │   └── results_page_1.parquet
    ├── query=year_2023/
    │   └── results_page_1.parquet
    └── query=institutions/
        ├── query_l2=usa/
        │   └── results_page_1.parquet
        └── query_l2=uk/
            └── results_page_1.parquet

The hive partition columns (`query`, `query_l2`, …) become regular
columns when you open the dataset with
[`arrow::open_dataset()`](https://arrow.apache.org/docs/r/reference/open_dataset.html),
enabling efficient predicate pushdown.

------------------------------------------------------------------------

### Deprecated: the JSONL Pipeline

[`pro_request_jsonl()`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl.md)
and
[`pro_request_jsonl_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl_parquet.md)
converted the JSON files in two steps via intermediate JSONL files. They
still work but are deprecated;
[`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)
replaces both. See their help pages
([`?pro_request_jsonl`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl.md),
[`?pro_request_jsonl_parquet`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl_parquet.md))
for existing code.

------------------------------------------------------------------------

## Error Handling

### Common Errors

#### Output Directory Exists

``` r

pro_request(query_url = url, output = "data/json")
# Error: Directory data/json exists.
# Either specify `overwrite = TRUE` or delete it.

# Solution:
pro_request(query_url = url, output = "data/json", overwrite = TRUE)
```

#### No Output Specified

``` r

pro_request(query_url = url)
# Error: No `output` specified!
```

#### API Rate Limiting

OpenAlex allows up to 100 requests per second and a daily budget (\$0.10
without an API key, \$1 with a free key). If you exceed the per-second
limit (HTTP 429), the function retries with exponential backoff. If the
daily budget is used up, it stops at once and reports when the budget
resets (midnight UTC). To stay within the budget:

1.  Use an API key (free from OpenAlex)
2.  Check the cost first: searches cost ten times as much as filter
    queries
3.  Use `resume = TRUE` after the reset to complete an interrupted
    download

You can check your current budget and remaining allowance at any time
with:

``` r

pro_rate_limit_status()
```

This queries the `/rate-limit` endpoint and prints your daily budget,
amount used, remaining balance, and seconds until the daily reset.

#### Request Size Exceeded

OpenAlex has a maximum request size of 4094 characters. If exceeded:

``` r

meta <- pro_count(query_url = very_long_url)
meta$count
# [1] -4195  # Negative indicates error

meta$error
# [1] "ERROR: Request size exceeds the maximum limit of 4094."
```

**Solution:** Use
[`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)
with chunking (it handles this automatically).

## Best Practices

### 1. Always Use Progress Bars

Progress bars help monitor long downloads and estimate completion:

``` r

pro_request(url, output = "data", progress = TRUE)
```

### 2. Use Appropriate Page Limits

Start with smaller page limits during development:

``` r

# Development: small sample
pro_request(url, output = "test", pages = 10)

# Production: full download
pro_request(url, output = "data", pages = 10000)
```

### 3. Enable Error Logging for Large Jobs

``` r

pro_request(
  query_url = urls,
  output = "data/json",
  error_log = "download_errors.log"
)
```

### 4. Clean Up Intermediate Files

Use `delete_input = TRUE` to save disk space:

``` r

# Convert and delete JSON (kept if any file failed to convert)
pro_request_parquet(
  input_json = "data/json",
  output = "data/parquet",
  delete_input = TRUE
)
```

[`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
deletes the JSON files by default (`delete_input = TRUE`).

### 5. Use Parallel Processing Wisely

More workers isn’t always better:

``` r

# Downloads: limited by the API, a few workers for a list of queries
pro_request(urls, output = "data/json", workers = 4)

# Conversion: CPU and memory bound; each worker gets a share of the memory
pro_request_parquet("data/json", "data/parquet", workers = parallel::detectCores() - 1)

# pro_fetch() does both: `download_workers` for the download (defaults to
# `workers`), `workers` for the conversion
pro_fetch(urls, project_folder = "data", download_workers = 4,
          workers = parallel::detectCores() - 1)
```

## See Also

- [`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md) -
  Build OpenAlex API query URLs
- [`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md) -
  Convert the JSON results to a Parquet dataset
- [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md) -
  Download and convert in one step
- [`read_corpus()`](https://openalexpro.github.io/openalexPro/reference/read_corpus.md) -
  Open the Parquet dataset
- [`pro_count()`](https://openalexpro.github.io/openalexPro/reference/pro_count.md) -
  Get result counts without downloading
- [`pro_validate_credentials()`](https://openalexpro.github.io/openalexPro/reference/pro_validate_credentials.md) -
  Validate API credentials (optional helper)
- [`pro_rate_limit_status()`](https://openalexpro.github.io/openalexPro/reference/pro_rate_limit_status.md) -
  Check current rate limit usage and remaining budget
- [`opt_filter_names()`](https://openalexpro.github.io/openalexPro/reference/opt_filter_names.md) -
  List available filter names
- [`opt_select_fields()`](https://openalexpro.github.io/openalexPro/reference/opt_select_fields.md) -
  List available select fields

## References

- [OpenAlex API Documentation](https://help.openalex.org/api/)
- [OpenAlex Authentication and Rate
  Limits](https://help.openalex.org/api/authentication/)
- [OpenAlex Error Handling](https://help.openalex.org/api/errors/)
- [Apache Parquet Format](https://parquet.apache.org/)
- [DuckDB Documentation](https://duckdb.org/docs/)
