# Look up records by ID using a pre-built index (pure-R implementation)

Pure-R/DuckDB fallback for
[`lookup_by_id()`](https://rkrug.github.io/openalexPro/reference/lookup_by_id.md).
Use this variant in environments where the compiled Rust library is not
available. Both functions share the same argument signature.

## Usage

``` r
lookup_by_id_R(
  root_dir = NULL,
  ids,
  project_dir = NULL,
  data_sets = NULL,
  workers = NULL,
  progress = TRUE,
  verbose = TRUE,
  index_file = NULL,
  selected = NULL,
  output = NULL
)
```

## Arguments

- root_dir:

  Root directory containing `parquet/` and the dataset indexes produced
  by
  [`build_corpus_index()`](https://rkrug.github.io/openalexPro/reference/build_corpus_index.md).
  Index files are expected at
  `<root_dir>/parquet/<dataset>_id_idx.parquet`.

- ids:

  Character vector of OpenAlex IDs to retrieve. Can be long form (e.g.
  `"https://openalex.org/W2741809807"`) or short form (e.g.
  `"W2741809807"`).

- project_dir:

  Project output directory. Extracted Parquet files are written to
  `<project_dir>/snapshot_extract_<dataset>/`. Only used when `root_dir`
  is provided.

- data_sets:

  Character vector of dataset names to search (e.g.
  `c("works", "authors")`). `NULL` searches all indexed datasets under
  `<root_dir>/parquet/`. Ignored when `index_file` is provided.

- workers:

  Number of parallel workers for reading corpus files. Default is `NULL`
  (sequential).

- progress:

  Ignored (kept for backward compatibility).

- verbose:

  Print progress messages. Default is `TRUE`.

- index_file:

  Explicit path to an index parquet file created by
  [`build_corpus_index()`](https://rkrug.github.io/openalexPro/reference/build_corpus_index.md).
  When provided, `root_dir`, `data_sets`, and `project_dir` are ignored.

- selected:

  Ignored in the Rust backend (kept for backward compatibility with the
  pure-R implementation).

- output:

  Path to an output directory for writing results as Parquet files when
  using `index_file` mode. If `NULL` (default), results are returned as
  a data frame. Ignored when `root_dir` is used (use `project_dir`
  instead).

## Value

See
[`lookup_by_id()`](https://rkrug.github.io/openalexPro/reference/lookup_by_id.md).

## See also

[`lookup_by_id()`](https://rkrug.github.io/openalexPro/reference/lookup_by_id.md)
