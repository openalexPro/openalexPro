# Convert an OpenAlex snapshot to Parquet format.

Full pipeline: schema inference (per-dataset, cached in
\`\<parquet_dir\>/\<dataset\>/.schema_cache/unified_schema.csv\`) plus
parallel per-file COPY via rayon.

## Usage

``` r
oa_snapshot_to_parquet(
  snapshot_dir,
  parquet_dir,
  data_sets,
  workers,
  sample_size,
  memory_limit,
  temp_dir,
  verbose
)
```

## Arguments

- snapshot_dir:

  Path to the snapshot root (contains a \`data/\` subdir).

- parquet_dir:

  Output directory for Parquet files.

- data_sets:

  Character vector of dataset names, or \`character(0)\` for all
  datasets found under \`snapshot_dir/data/\` (excluding
  \`merged_ids\`).

- workers:

  Number of parallel workers (\`1\` = sequential).

- sample_size:

  Files to sample for schema inference (\`0\` = all).

- memory_limit:

  DuckDB memory limit, e.g. \`"8GB"\` (\`""\` = no limit).

- temp_dir:

  DuckDB temp directory (\`""\` = system default).

- verbose:

  Print progress to stderr.

## Value

Invisibly returns \`NULL\`.
