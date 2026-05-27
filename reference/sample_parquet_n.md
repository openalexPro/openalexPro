# Sample rows from Parquet files using DuckDB reservoir sampling

Draw a uniform random sample of `n` rows from one or more Parquet files
using DuckDB's SQL `USING SAMPLE reservoir(n ROWS)` clause. The sampling
is performed entirely inside DuckDB, so the full dataset is never loaded
into R.

This is well-suited for large Parquet corpora (e.g. OpenAlex works)
where you want a random subset of rows without materialising the whole
table.

## Usage

``` r
sample_parquet_n(path, n, seed = NULL, con = NULL, select = NULL)
```

## Arguments

- path:

  Character scalar. Path or glob pointing to one or more Parquet files,
  as understood by DuckDB's `parquet_scan()` table function. For
  example, `"spc_corpus/output/chapter_3/corpus/*.parquet"`.

- n:

  Integer scalar. Number of rows to sample. If `n` is larger than the
  total number of rows in the dataset, DuckDB returns all rows.

- seed:

  Optional integer scalar. If supplied, a `REPEATABLE(seed)` clause is
  added to the DuckDB query so that repeated calls with the same input
  data and seed return the same sample. If `NULL` (default), the sample
  is not forced to be reproducible at the DuckDB level.

- con:

  Optional
  [`DBIConnection`](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  to an existing DuckDB database. If `NULL` (the default), the function
  creates a temporary in-memory DuckDB instance, uses it for the query,
  and shuts it down before returning. If a connection is supplied, it is
  left open and not modified beyond running the sampling query.

- select:

  Optional character vector of column names to return. If `NULL`
  (default), all columns are returned (equivalent to `SELECT *`). Column
  names are passed through
  [`DBI::dbQuoteIdentifier()`](https://dbi.r-dbi.org/reference/dbQuoteIdentifier.html)
  to safely handle special characters. If any requested column does not
  exist in the Parquet schema, DuckDB will raise an error.

## Value

A `data.frame` with up to `n` rows, containing a uniform random sample
from the union of all Parquet files matched by `path`, restricted to the
columns specified in `select` (or all columns if `select` is `NULL`).

## Details

The function delegates to the following SQL pattern (simplified):


    SELECT [columns]
    FROM parquet_scan('path/to/files/*.parquet')
    USING SAMPLE reservoir(n ROWS)
    [REPEATABLE (seed)]

Using `reservoir(n ROWS)` gives an exact uniform sample of size `n` from
all rows in the dataset (unless `n` exceeds the total row count, in
which case all rows are returned).

Note that the `path` argument is passed directly to DuckDB's
`parquet_scan()` function, so you can use:

- A single Parquet file:

  - `"works.parquet"`

- A glob for many files:

  - `"works/*.parquet"`

- A directory, depending on your DuckDB version/configuration.

When `con` is `NULL`, the function creates an in-memory DuckDB database.
If you want to reuse the same DuckDB instance for multiple queries (for
performance reasons or to control pragmas), you can create a DuckDB
connection yourself and pass it via `con`.

## Examples

``` r
if (FALSE) { # \dontrun{
# Sample 1,000 rows from a directory of Parquet files
sample_df <- sample_parquet_duckdb(
  path = "spc_corpus/output/chapter_3/corpus/*.parquet",
  n = 10000L,
  seed = 1234
)

# Sample only a subset of columns
sample_df_small <- sample_parquet_duckdb(
  path = "spc_corpus/output/chapter_3/corpus/*.parquet",
  n = 10000L,
  seed = 1234,
  select = c("id", "doi", "citation", "author_abbr", "display_name", "ab")
)

# Reuse a DuckDB connection for multiple samples
con <- DBI::dbConnect(duckdb::duckdb())
on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

s1 <- sample_parquet_duckdb(
  path = "openalex_works/*.parquet",
  n = 500L,
  seed = 42,
  con = con
)

s2 <- sample_parquet_duckdb(
  path = "openalex_works/*.parquet",
  n = 500L,
  seed = 777,
  con = con
)
} # }
```
