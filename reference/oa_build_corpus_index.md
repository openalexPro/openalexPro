# Build a two-stage ID-lookup index for a single Parquet corpus directory.

Stage 1: per-file shard indexes (parallel via rayon). Stage 2: combine
shards into \`\<corpus_name\>\_id_idx.parquet\`.

## Usage

``` r
oa_build_corpus_index(corpus_dir, workers, memory_limit, overwrite, verbose)
```

## Arguments

- corpus_dir:

  Path to a single dataset Parquet directory.

- workers:

  Number of parallel workers for Stage 1.

- memory_limit:

  DuckDB memory limit (\`""\` = no limit).

- overwrite:

  If \`TRUE\`, rebuild an existing index.

- verbose:

  Print progress to stderr.

## Value

Character scalar: path to the index file.

## Details

Returns the path to the created index file as a character scalar.
