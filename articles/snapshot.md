# Working with OpenAlex Snapshots — Moved to openalexSnapshot

> **Snapshot functionality has moved.**
>
> The full OpenAlex snapshot workflow — downloading, converting
> `.json.gz` files to Parquet, building ID lookup indexes, and
> extracting records by ID — is now part of the **`openalexSnapshot`**
> package.
>
> Please install `openalexSnapshot` and refer to its documentation.

``` r

# Install openalexSnapshot (once available on r-universe):
pak::pak("openalexSnapshot")
```

Calling
[`snapshot_to_parquet()`](https://rkrug.github.io/openalexPro/reference/snapshot_to_parquet.md),
[`build_corpus_index()`](https://rkrug.github.io/openalexPro/reference/build_corpus_index.md),
or
[`lookup_by_id()`](https://rkrug.github.io/openalexPro/reference/lookup_by_id.md)
in `openalexPro` raises an informative error pointing to
`openalexSnapshot`.
