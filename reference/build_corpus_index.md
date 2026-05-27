# Build a Parquet ID-lookup index

Builds a `<dataset>_id_idx.parquet` index from the Parquet corpus
produced by
[`snapshot_to_parquet()`](https://rkrug.github.io/openalexPro/reference/snapshot_to_parquet.md),
enabling fast record retrieval by OpenAlex ID using
[`lookup_by_id()`](https://rkrug.github.io/openalexPro/reference/lookup_by_id.md).

## Usage

``` r
build_corpus_index(
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

## Details

The function uses a two-stage approach:

1.  Index each parquet file individually (bounded memory, parallel via
    rayon, with resume support).

2.  Combine the per-file shard indexes into a single parquet index.

Paths can be supplied as a single `root_dir` (which iterates over all
requested `data_sets`) or as an explicit `corpus_dir` pointing to a
single dataset directory.

The index contains columns:

- id:

  The OpenAlex ID

- id_block:

  Block number computed as `floor(numeric_id / 10000)`

- parquet_file:

  Relative path to the Parquet file in the corpus

- file_row_number:

  Row number within the file (0-indexed)

## See also

[`build_corpus_index_R()`](https://rkrug.github.io/openalexPro/reference/build_corpus_index_R.md)
for the pure-R/DuckDB fallback,
[`lookup_by_id()`](https://rkrug.github.io/openalexPro/reference/lookup_by_id.md)
for ID-based record retrieval.

## Examples

``` r
if (FALSE) { # \dontrun{
build_corpus_index(root_dir = "/Volumes/openalex")

build_corpus_index(
  root_dir  = "/Volumes/openalex",
  data_sets = "works",
  workers   = 4
)

# Single explicit directory:
build_corpus_index(
  corpus_dir   = "/Volumes/openalex/parquet/works",
  memory_limit = "20GB"
)
} # }
```
