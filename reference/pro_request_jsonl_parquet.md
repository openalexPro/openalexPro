# Convert JSON files to Apache Parquet files

The function takes a directory of JSONL files as written from a call to
`pro_request_jsonl_R(...)` and converts each file individually to a
Parquet file. The subfolder structure from the input is preserved in the
output, so files in `Chunk_1/` will be written to `Chunk_1/` in the
output directory.

## Usage

``` r
pro_request_jsonl_parquet(
  input_jsonl = NULL,
  output = NULL,
  overwrite = FALSE,
  verbose = TRUE,
  delete_input = FALSE,
  sample_size = 1000,
  workers = NULL
)
```

## Arguments

- input_jsonl:

  The directory of JSON files returned from
  `pro_request(..., json_dir = "FOLDER")`.

- output:

  output directory for the parquet dataset; default: temporary
  directory.

- overwrite:

  Logical indicating whether to overwrite `output`.

- verbose:

  Logical indicating whether to show verbose information. Defaults to
  `TRUE`

- delete_input:

  Determines if the `input_jsonl` should be deleted afterwards. Defaults
  to `FALSE`.

- sample_size:

  Number of records to sample from each file when inferring the unified
  schema. Higher values give more accurate schema inference but use more
  memory. Default is 1000. Set to -1 to read all records (may be slow
  for large files).

- workers:

  Number of parallel workers for file conversion via
  [`future.apply::future_lapply()`](https://future.apply.futureverse.org/reference/future_lapply.html).
  Default is `NULL` (sequential processing).

## Value

The function returns the output path invisibly.

## Details

The `page` column (added by
[`pro_request_jsonl_R()`](https://rkrug.github.io/openalexPro/reference/pro_request_jsonl_R.md))
is preserved as a regular column in the Parquet data.

When starting the conversion, a file `00_in.progress` is created which
is deleted upon completion.

The function uses DuckDB to read the JSON files and to create the Apache
Parquet files. Each JSON file is converted individually using its own
DuckDB connection, which enables parallel processing via
[`future.apply::future_lapply()`](https://future.apply.futureverse.org/reference/future_lapply.html).

To ensure consistent schemas across all Parquet files, the function
first infers a unified schema by sampling records from all JSONL files.
This prevents type mismatches (e.g., a column being `struct` in one file
but `string` in another) that would cause errors when reading the
combined Parquet dataset.
