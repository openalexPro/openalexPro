# Disclaimer

The package is provided **as is** and the authors do not take any
responsibility for any damages or losses arising from its use. The
software is provided without warranty of any kind, express or implied,
including but not limited to the warranties of merchantability, fitness
for a particular purpose, and non-infringement. Use at your own risk.

The authors are not affiliated with [OpenAlex](https://openalex.org) in
any way.

# LLM Usage Disclosure

Code and documentation in this project have been generated with the
assistance of the codex LLM tools as well as Claude Code in Positron.
All content and code and documentation is based on the conceptualisation
by the authors and has been thoroughly reviewed and edited by humans
afterwards.

# Introduction

This package is inspired by the package
[`openalexR`](https://github.com/ropensci/openalexR) but provides a
different approach to retrieve works from OpenAlex. In contrast to
`openalexR`, which does all processing and conversions in memory,
[`openalexPro`](https://openalexpro.r-universe.dev/openalexPro) uses an
on-disc processing approach where the data is processed by number of
records returned per individual call, i.e. a per-page processing
approach. Doing all processing in memory has advantages for smaller
numbers of records retrieved from [OpenAlex](https://openalex.org), but
limits the number of works which can be retrieved due to memory
limitations and a considerable slowdown due to repeated memory
allocations even before that. The on-disc based processing essentially
should scale at most linearly with the number of pages requested from
[OpenAlex](https://openalex.org) and likely considerably less as
parallel processing is used extensively in
[`openalexPro`](https://openalexpro.r-universe.dev/openalexPro).

# Quickstart

## Installation

The latest “stable” version is available via
[r-universe](https://openalexpro.r-universe.dev/openalexPro)

``` r

install.packages('openalexPro', repos = c('https://openalexpro.r-universe.dev', 'https://cloud.r-project.org'))
```

The “development” version can be installed from github. **This is
generally not recommended!** Unless you need bleeding edge functionality
and can deal with changing function definitions, or want to test new
functionality, this is not recommended.

``` r

remotes::install_github("openalexPro/openalexPro", ref = "dev")
```

## Authentication (Optional, Recommended)

`openalexPro` can run without an API key, but OpenAlex applies much
stricter limits in unauthenticated mode. For real workloads, an API key
should be obtained. Let’s assume your key is “xxxxxxx”.

There are three ways of providing, which are evaluated in order:

1.  You can set an `openalexPro` option using \`opt_api_key(“xxxxxxx”)
2.  You can set the environmental variable `openalexPro.api_key` to the
    API key. This can be set in the `.Renviron file`
3.  You can save your API key in the keyring using
    `keyring::key_set("API_openalex")` which will ask you for the key
    which then will be saved securely and encrypted in your keyring.
    Where that is, depends on the OS and your setup (see the [`keyring`
    package documentation](https://keyring.r-lib.org/index.html) for
    details).

The safest one is (3), but (1) depends how you put the API key in the
option.

After setup, you can validate your credentials and see your available
daily or prepaid budget:

``` r

# Check current key status
pro_validate_credentials()

# Inspect budget/usage (requires a valid key)
pro_rate_limit_status()
```

## Live API Contract Tests (Optional)

The default test suite is cassette-based and deterministic.  
To run online contract checks against the live OpenAlex API:

``` r

Sys.setenv(OPENALEXPRO_LIVE_TESTS = "true")
devtools::test(filter = "900-live")
```

### 1. Define query (`openalexPro::pro_query()`)

The query is defined using the function
[`openalexPro::pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md).
It follows the logic and arguments of
[`openalexR::oa_query()`](https://docs.ropensci.org/openalexR/reference/oa_query.html).
In addition to
[`openalexR::oa_query()`](https://docs.ropensci.org/openalexR/reference/oa_query.html),
the names of filters as well as fields selected for retrieval are
verified before sending them to OpenAlex.

The supported filter names can be retrieved by running

``` r

opt_filter_names()                        # works (default)
opt_filter_names(entity = "institutions") # names differ per entity
```

and supported select fields by running

``` r

opt_select_fields()
opt_select_fields(entity = "authors")
```

[`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)
validates against the lists for the queried `entity`.

This defines a basic query.

``` r

query <- pro_query(
entity = "works",
  search = "biodiversity sandwich island",
  from_publication_date = "2023-01-01",
  type = "article",
  select = c("ids", "title", "publication_year", "cited_by_count")
)
```

This returns a URL, which one can open in the browser.

If, however, for example 100 DOIs are given to be retrieved, the query
is chunked into chunks of a maximum of the value of the argument
`chunk_limit`, default is 50. In this case, the functions returns a
[`list()`](https://rdrr.io/r/base/list.html) with each element named
`chunk_x` and containing the URL as a character vector.

The resulting URL(s) can be opened in the browser for evaluation.

Queries the classic filter syntax cannot express, such as nested `and` /
`or` conditions across fields, can be written in OpenAlex’s query
language OQL, or as its JSON form OQO (see the [OQL
documentation](https://help.openalex.org/api/oql/)):

``` r

query <- pro_query(
  oql = "works where year >= (2020) and title-abstract has ((coral OR reef) AND bleaching)"
)
```

The entity and all conditions are part of the query; `select` and
`options` can be added as usual.

[`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
and
[`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
send every query as an OpenAlex Query Object via POST (`via = "oqo"`,
the default; `via = "url"` sends a GET URL): the same results (the test
suite compares complete result sets), checked before any credits are
spent, no URL length limit (so `pro_query(..., chunk_limit = 200)` for
DOI and ID lists), and the exact query recorded in a `_query.json` per
query together with its cost. For papers, each query also gets
`_query_oql.txt` and a formatted `_query_oql.html` with the query in
OpenAlex’s readable query language (OQL), checked to reproduce the query
exactly; for a list of queries, `_queries_oql.txt` / `_queries_oql.html`
summarise them all for a supplement.

## `pro_fetch()`

For most use cases,
[`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
handles everything in one call:

``` r

# Download, transform, and convert to Parquet in one step
pro_fetch(
  query_url = url,
  project_folder = "Biodiversity_from_sandwich_islands",
  progress = TRUE
)
```

All intermediate folders and data are deleted, and only the final
parquet dataset remains in
`Biodiversity_from_sandwich_islands/parquet/`.

## Advanced Workflow (Individual Functions)

For more control over the pipeline, use the individual functions:

``` r

library(openalexPro)
```

### 1. Retrieving records (`openalexPro::pro_request()`)

``` r

json_files <- openalexPro::pro_request(
  query_url = query,
  output = "json",
  verbose = TRUE
)
```

Will retrieve the records and save them into the folder specified in
output. One important difference is now between the query being a single
URL or a list: if it is a list, the `future` and `future.apply` packages
are used to process the URLs in the list in parallel.

[`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
also accepts **nested lists**, which creates a mirrored nested directory
structure. The subsequent
[`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)
step converts the directory depth into hive-style partition keys
(`query=<name>`, `query_l2=<name>`, …), so the final parquet dataset can
be filtered by group directly:

``` r

queries <- list(
  year_2022 = pro_query(entity = "works", publication_year = 2022),
  year_2023 = pro_query(entity = "works", publication_year = 2023)
)
pro_fetch(query_url = queries, project_folder = "by_year")

# Parquet partitions: by_year/parquet/query=year_2022/ and query=year_2023/
arrow::open_dataset("by_year/parquet") |> dplyr::filter(query == "year_2022")
```

An interrupted download can be completed with `resume = TRUE`: only the
queries that did not finish are fetched again.

### 2. Convert to `parquet` database (`openalexPro::pro_request_parquet()`)

Here the json files are converted into a page partitioned dataset saved
as individual `parquet` files in the folder provided by the `output`
argument. For works, the abstract text is re-constructed and a citation
string is generated:

``` r

parquet <- "./parquet"
openalexPro::pro_request_parquet(
  input_json = json_files,
  output = parquet,
  verbose = TRUE
)
```

These functions are pipeline ready and can be chained in a pipeline:

``` r

corpus <- pro_query(...) |>
  pro_request(...) |>
  pro_request_parquet(...)
```

The older two-step conversion via JSONL files
([`pro_request_jsonl()`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl.md)
and
[`pro_request_jsonl_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl_parquet.md))
is deprecated.

By default there is one `parquet` file per API page (up to 200 records),
which keeps the conversion parallel and resumable. For large downloads,
`compact_parquet = 250000` (in
[`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)
or
[`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md))
combines each query’s page files into files of up to 250,000 records
after the conversion;
[`pro_compact_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_compact_parquet.md)
does the same for an existing dataset. Records, columns and their order
do not change, but reading is much faster: for 1.1 million works,
aggregates and lookups by ID ran 35 to 50 times faster, and the dataset
was 40% smaller.

### Convenience Function to Read the Retrieved Data (`openalexPro::read_corpus()`)

The
[`read_corpus()`](https://openalexpro.github.io/openalexPro/reference/read_corpus.md)
function reads the corpus either as a arrow `Dataset` object if
`return_data = FALSE`, which is essentially metadata to the dataset, or
a `data.frame`, if `return_data = TRUE`, in which case the whole dataset
is loaded into memory. Especially the `return_data = FALSE` opens
possiblilities on on-disc process =ing of mlarge datasets using the
`dplyr` pipeline with
[`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html)
at the end to retrieve the actual data:

``` r

read_corpus("Biodiversity_from_sandwich_islands") |>
  dplyr::filter(cited_by_count > 100) |>

  # only now, the actual data is retrieved.
  dplyr::collect()
```

# Design Principles

The retrieval of works and the initial processing / preparation can be
split into these two steps:

In a first step
([`openalexPro::pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)),
each page from the API call is saved into an individual json file as
returned by the API. The number of retrieved records is effectively only
limited by the space on the drive where the json files are saved. As the
complete responses including metadata are saved, one could end here and
use custom made code to further process the responses, i.e. ingest it
into a database.

In a second step
([`openalexPro::pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)),
the json files are converted on a per file basis into a parquet database
partitioned by `page` using the `duckdb` package. In this step the
abstract text is re-constructed, a citation string for each work is
generated, and a `page` field is added. As the processing is done per
page, the conversion is not limited by memory.

This approach results in a stable pipeline which works for the retrieval
of small as well as large to huge corpora. As the processing is done per
page (which have a maximum of 200 works), the scaling should be more or
less linear (in one application, more than 4 million works were
retrieved without problems).

One point which needs to be taken into consideration when retrieving
huge corpora, are rate limits by OpenAlex (see
[here](https://help.openalex.org/api/authentication/) and
[here](https://help.openalex.org/access/example-costs/) for further
details). Use
[`pro_rate_limit_status()`](https://openalexpro.github.io/openalexPro/reference/pro_rate_limit_status.md)
to inspect your current daily budget, usage, and remaining allowance at
any time.

The final format which is used in this package to save the retrieved
data is the `parquet` format which is space efficient and allows on disc
processing, therefore there is no need to load the complete data into
memory (see [here](https://parquet.apache.org/docs/) for a detailed
description of the format as well as the [r-package
`arrow`](https://arrow.apache.org/docs/r/)). To use the on disc
processing in R, the `arrow` packages interfaces directly with `dplyr`,
so that one can do a lot of processing before retrieving the actual data
into memory (see the section on [dplyr and
arrow](https://r4ds.hadley.nz/arrow.html#using-dplyr-with-arrow) as well
more general the [arrow chapter](https://r4ds.hadley.nz/arrow.html) in
Hadley Wickham’s [R for Data Science (2e)](https://r4ds.hadley.nz)
book).

# Snowball Searches

Snowball search functionality has moved to the separate
[`openalexSnowball`](https://github.com/openalexPro/openalexSnowball)
package, which depends on `openalexPro` for the underlying pipeline.
