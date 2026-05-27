# Build a Parquet ID-lookup index (pure-R implementation)

Pure-R/DuckDB fallback for
[`build_corpus_index()`](https://rkrug.github.io/openalexPro/reference/build_corpus_index.md).
Use this variant in environments where the compiled Rust library is not
available. Both functions share the same argument signature.

## Usage

``` r
build_corpus_index_R(
  root_dir = NULL,
  data_sets = NULL,
  workers = NULL,
  memory_limit = NULL,
  overwrite = FALSE,
  verbose = TRUE,
  corpus_dir = NULL
)
```

## Arguments

- root_dir:

  Root directory containing a `parquet/` subdirectory produced by
  [`snapshot_to_parquet()`](https://rkrug.github.io/openalexPro/reference/snapshot_to_parquet.md).
  If provided, the index for each dataset in `data_sets` is created at
  `<root_dir>/parquet/<dataset>_id_idx.parquet`.

- data_sets:

  Character vector of dataset names to index (e.g.
  `c("works", "authors")`). `NULL` indexes all datasets found under
  `<root_dir>/parquet/`. Ignored when `corpus_dir` is provided.

- workers:

  Number of parallel workers for Stage 1 indexing. Default is `NULL`
  (sequential).

- memory_limit:

  DuckDB memory limit (e.g., `"20GB"`). Default is `NULL`.

- overwrite:

  If `TRUE`, rebuilds existing indexes. Default is `FALSE` (skip if the
  index already exists).

- verbose:

  Print progress messages. Default is `TRUE`.

- corpus_dir:

  Explicit path to a single dataset Parquet directory (e.g.
  `"/Volumes/openalex/parquet/works"`). The index is written as a
  sibling file: `<parent>/<basename>_id_idx.parquet`. When this is
  provided, `root_dir` and `data_sets` are ignored.

## Value

When `corpus_dir` is provided, invisibly returns the path to the created
index file. When `root_dir` is used, invisibly returns `root_dir`.

## See also

[`build_corpus_index()`](https://rkrug.github.io/openalexPro/reference/build_corpus_index.md)
