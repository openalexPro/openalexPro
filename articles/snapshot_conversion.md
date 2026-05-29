# Snapshot Conversion — Moved to openalexSnapshot

> **These functions have moved.**
>
> [`snapshot_to_parquet()`](https://openalexpro.github.io/openalexPro/reference/snapshot_to_parquet.md),
> [`build_corpus_index()`](https://openalexpro.github.io/openalexPro/reference/build_corpus_index.md),
> and
> [`lookup_by_id()`](https://openalexpro.github.io/openalexPro/reference/lookup_by_id.md)
> are now part of the **`openalexSnapshot`** package.
>
> Please install `openalexSnapshot` and refer to its documentation for
> converting the OpenAlex bulk snapshot to Parquet, building ID lookup
> indexes, and extracting records by ID.

``` r

# Install openalexSnapshot (once available on r-universe):
pak::pak("openalexSnapshot")
```

Calling these functions in `openalexPro` raises an informative error
pointing to `openalexSnapshot`.
