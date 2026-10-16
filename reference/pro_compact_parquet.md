# Compact a Parquet dataset into fewer, larger files

[`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)
writes one Parquet file per API page (up to 200 records). That keeps the
conversion parallel and resumable, but a large query becomes thousands
of small files, which are slow to read. `pro_compact_parquet()` combines
them into files of up to `rows` records. Records, columns and their
order do not change.

## Usage

``` r
pro_compact_parquet(parquet_dir, rows, verbose = TRUE)
```

## Arguments

- parquet_dir:

  Output directory of
  [`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md),
  or the `parquet` folder of a
  [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
  project.

- rows:

  Maximum number of records per compacted file, e.g. `250000`.

- verbose:

  Logical. Report what was compacted. Default `TRUE`.

## Value

`parquet_dir` (invisibly).

## Details

Measured for 1.1 million works (5,460 page files): compaction took about
20 seconds; afterwards aggregates and lookups by ID ran 35 to 50 times
faster, reading full records with DuckDB 4 times faster, and the dataset
was 40% smaller. Files of 50,000 to 1 million records made no difference
to read speed; `rows = 250000` is a good choice (about 0.25 GB of full
works records; newer works with abstracts and long reference lists are
larger).

- Each query's partition (`query=<name>/`) is compacted on its own; its
  `_query.json` and `_query_oql.*` files stay.

- A compacted file holds whole consecutive pages, in download order, and
  is named after them: pages 1 to 1250 become
  `results_pages_1-1250.parquet`. A page with more than `rows` records
  becomes a file of its own. The `page` column is kept.

- Files are compacted one at a time: each is written to a `.part` file,
  its record count checked, renamed, and only then are its pages
  deleted. If interrupted, run it again: it completes what was started.

- Files compacted before are left as they are; only page files are
  combined.

- If a partition cannot be compacted (for example because its pages have
  conflicting column types), a warning says so and its page files stay:
  the dataset is complete either way.

- Indexes built by `openalexSnapshot::build_corpus_index()` or
  `build_doi_index()` point to files and row numbers, and would be wrong
  after compaction. If such an index exists next to `parquet_dir`, the
  function stops: delete the index, compact, and build it again.

## See also

The `compact_parquet` argument of
[`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)
and
[`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md),
which compacts right after the conversion.

## Examples

``` r
if (FALSE) { # \dontrun{
pro_compact_parquet("my_project/parquet", rows = 250000)
} # }
```
