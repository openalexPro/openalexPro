# Populate the local baseline-schema cache from a snapshot metadata directory

Copies `unified_schema.csv` files from an OpenAlex snapshot metadata
directory (e.g. `/Volumes/openalex/openalex-snapshot_metadata`) into the
user-level cache used by
[`pro_request_parquet`](https://rkrug.github.io/openalexPro/reference/pro_request_parquet.md)`(schema = "auto")`.

## Usage

``` r
oa_cache_schema(source, entities = "all", overwrite = FALSE, verbose = TRUE)
```

## Arguments

- source:

  Path to the snapshot metadata directory, e.g.
  `"/Volumes/openalex/openalex-snapshot_metadata"`.

- entities:

  Character vector of entity names to cache, or `"all"` (default) to
  cache every entity directory found under `source`.

- overwrite:

  Logical. Overwrite an existing cached file? Default `FALSE`.

- verbose:

  Logical. Print progress messages? Default `TRUE`.

## Value

The path to the schemata cache directory (invisibly).

## Details

Once cached, the schemas are used even when the source volume is not
mounted. Update the cache periodically to pick up new fields added by
OpenAlex (run with `overwrite = TRUE`).

## See also

[`pro_request_parquet`](https://rkrug.github.io/openalexPro/reference/pro_request_parquet.md)
for the `schema` parameter.
