# Convert JSON files from pro_request() directly to Apache Parquet (pure-R)

Pure-R/DuckDB fallback for
[`pro_request_parquet()`](https://rkrug.github.io/openalexPro/reference/pro_request_parquet.md).
Use this variant in environments where the compiled Rust library is not
available. Both functions share the same argument signature.

## Usage

``` r
pro_request_parquet_R(
  input_json = NULL,
  output = NULL,
  add_columns = list(),
  overwrite = FALSE,
  verbose = TRUE,
  progress = TRUE,
  delete_input = FALSE,
  sample_size = 1000,
  workers = NULL,
  enrich = TRUE
)
```

## Arguments

- input_json:

  Directory of JSON files returned by
  [`pro_request()`](https://rkrug.github.io/openalexPro/reference/pro_request.md).

- output:

  Output directory for the Parquet dataset.

- add_columns:

  Named list of scalar constant columns to embed in every output record
  (e.g. `list(query = "my_filter")`). Values are embedded as SQL string
  literals; only character scalars are supported.

- overwrite:

  Logical. Overwrite `output` if it already exists. Default `FALSE`.

- verbose:

  Logical. Show progress messages. Default `TRUE`.

- progress:

  Logical. Ignored (kept for backward compatibility; progress is
  reported to stderr by the Rust backend).

- delete_input:

  Logical. Delete `input_json` after a successful conversion. Default
  `FALSE`.

- sample_size:

  Integer. Number of records per file passed to DuckDB's `sample_size`
  option during schema inference. Use `-1` to read all records (accurate
  but slow for large files). Default `1000`.

- workers:

  Integer. Number of parallel workers for
  [`oa_api_files_to_parquet()`](https://rkrug.github.io/openalexPro/reference/oa_api_files_to_parquet.md).
  `NULL` or `1` runs sequentially. Default `NULL`.

- enrich:

  Logical. When `TRUE` (the default) and the inferred schema contains
  `abstract_inverted_index` / `authorships` / `publication_year`, add
  `abstract` and `citation` computed columns.

## Value

Output directory path (invisibly).

## See also

[`pro_request_parquet()`](https://rkrug.github.io/openalexPro/reference/pro_request_parquet.md)
