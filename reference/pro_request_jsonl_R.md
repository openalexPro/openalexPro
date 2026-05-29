# Convert JSON files to jsonl files

The function takes a directory of JSON files as written from a call to
`pro_request(...)` and is preparing the json files to be processed
further using DuckDB by converting them to `jsonl` files. The subfolders
in `input_json` are preserved in `output`, i.e. results of a list of
initial queries passed to
[`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
are maintained.

## Usage

``` r
pro_request_jsonl_R(
  input_json = NULL,
  output = NULL,
  add_columns = list(),
  overwrite = FALSE,
  verbose = TRUE,
  progress = TRUE,
  delete_input = FALSE,
  workers = 1
)
```

## Arguments

- input_json:

  The directory of JSON files returned from
  `pro_request(..., json_dir = "FOLDER")`.

- output:

  output directory for the jsonl files as created by calls to
  \`jq_execute().

- add_columns:

  List of additional fields to be added to the output. They nave to be
  provided as a named list, e./g.
  `list(column_1 = "value_1", column_2 = 2)`. Only Scalar values are
  supported.

- overwrite:

  Logical indicating whether to overwrite `output`.

- verbose:

  Logical indicating whether to show a verbose information. Defaults to
  `TRUE`

- progress:

  Logical indicating whether to show a progress bar. Default `TRUE`.

- delete_input:

  Determines if the `input_json` should be deleted afterwards. Defaults
  to `FALSE`.

- workers:

  Number of parallel workers to use. Defaults to 1.

## Value

The function does returns the output invisibly.

## Details

See
[`jq_execute`](https://openalexpro.github.io/openalexPro/reference/jq_execute.md)
or the [`vignette`](https://rdrr.io/r/utils/vignette.html)("jq", package
= "openalexPro") for more information on the conversion of the JSON
files. The folder/filename is converted to a value named `page` As an
example:

1.  the subfolder in the `output` folder is called `Chunk_1`

2.  the page othe json file represents is `2`

3.  The resulting cvalus for `page` will be `Chunk_1_2`

When starting the conversion, a file `00_in.progress` which is deleted
upon completion.

The function uses DuckDB to read the JSON files and to create the Apache
Parquet files. The function creates a DuckDB connection in memory and
readsds the JSON files into DuckDB when needed. Then it creates a SQL
query to convert the JSON files to Apache Parquet files and to copy the
result to the specified directory.

## Examples

``` r
if (FALSE) { # \dontrun{
  source_to_parquet(
  input_json = "json",
  source_type = "snapshot",
  output = "parquet"
) } # }
```
