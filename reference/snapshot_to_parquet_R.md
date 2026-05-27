# Convert OA snapshot to Parquet format (pure-R implementation)

Pure-R/DuckDB fallback for
[`snapshot_to_parquet()`](https://rkrug.github.io/openalexPro/reference/snapshot_to_parquet.md).
Use this variant in environments where the compiled Rust library is not
available. Both functions share the same argument signature.

## Usage

``` r
snapshot_to_parquet_R(
  root_dir = NULL,
  data_sets = NULL,
  workers = NULL,
  sample_size = 20,
  memory_limit = NULL,
  temp_directory = NULL,
  progress = TRUE,
  verbose = TRUE,
  snapshot_dir = NULL,
  parquet_dir = NULL
)
```

## Arguments

- root_dir:

  Root directory. If provided, `snapshot_dir` defaults to
  `<root_dir>/openalex-snapshot` and `parquet_dir` defaults to
  `<root_dir>/parquet`.

- data_sets:

  Character vector of dataset names to convert (e.g.
  `c("works", "authors")`). `NULL` converts all datasets found under
  `<snapshot_dir>/data/`.

- workers:

  Number of parallel workers for file conversion. Default is `NULL`
  (sequential).

- sample_size:

  Number of `.gz` files to sample for unified schema inference. Higher
  values give more accurate schemas but take longer. Default is `20`.
  Use `NULL` or `0` to use all files.

- memory_limit:

  DuckDB memory limit per worker (e.g., `"8GB"`). Default is `NULL`
  (DuckDB default).

- temp_directory:

  Location of the temporary directory for DuckDB. Default is `NULL`
  (system default).

- progress:

  Ignored (kept for backward compatibility; progress is reported to
  stderr by the Rust backend).

- verbose:

  Print per-dataset progress messages. Default is `TRUE`.

- snapshot_dir:

  Explicit path to the snapshot data directory (the one containing a
  `data/` subfolder). Required when `root_dir` is not provided.

- parquet_dir:

  Explicit path to the Parquet output directory. Required when
  `root_dir` is not provided.

## Value

Invisibly returns `NULL`.

## See also

[`snapshot_to_parquet()`](https://rkrug.github.io/openalexPro/reference/snapshot_to_parquet.md)
