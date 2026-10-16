# Snapshot Conversion — Moved to openalexSnapshot

> **These functions have moved.**
>
> `snapshot_to_parquet()`, `build_corpus_index()`, and `lookup_by_id()`
> are now part of the **`openalexSnapshot`** package.
>
> Please install `openalexSnapshot` and refer to its documentation for
> converting the OpenAlex bulk snapshot to Parquet, building ID lookup
> indexes, and extracting records by ID.
>
> They are no longer present in `openalexPro` even as error-raising
> stubs: an exported stub masks the real function when both packages are
> attached.

``` r

install.packages(
  "openalexSnapshot",
  repos = c("https://openalexpro.r-universe.dev", "https://cloud.r-project.org")
)
```

Call them as `openalexSnapshot::snapshot_to_parquet()` and so on.
