# Working with OpenAlex Snapshots — Moved to openalexSnapshot

> **Snapshot functionality has moved.**
>
> The full OpenAlex snapshot workflow — downloading the official Parquet
> snapshot, building ID lookup indexes, and extracting records by ID —
> is now part of the **`openalexSnapshot`** package.
>
> Please install `openalexSnapshot` and refer to its documentation.

``` r

# Install openalexSnapshot (once available on r-universe):
pak::pak("openalexSnapshot")
```

`snapshot_to_parquet()`, `build_corpus_index()` and `lookup_by_id()` are
no longer part of `openalexPro` in any form. They previously remained as
stubs that raised an informative error, but an exported stub **masks**
the real function whenever both packages are attached –
[`library(openalexSnapshot); library(openalexPro)`](https://rdrr.io/r/base/library.html)
made the stub win and error. Call them as
`openalexSnapshot::build_corpus_index()` and so on.
