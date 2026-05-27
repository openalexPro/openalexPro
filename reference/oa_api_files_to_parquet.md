# Parallel per-file conversion for OpenAlex API JSON responses.

Schema inference (including type normalisation) is performed in R and
the result is passed as pre-computed SQL fragments. This function
handles only the parallel execution of COPY statements via rayon.

## Usage

``` r
oa_api_files_to_parquet(
  input_files,
  output_files,
  array_field,
  list_type,
  extra_select,
  workers,
  verbose
)
```

## Arguments

- input_files:

  Character vector of input JSON file paths.

- output_files:

  Character vector of output Parquet file paths (same length as
  \`input_files\`).

- array_field:

  Name of the JSON array key (\`"results"\`, \`"group_by"\`), or \`""\`
  for single-record files.

- list_type:

  DuckDB STRUCT type string for array items, e.g. \`"STRUCT(id VARCHAR,
  title VARCHAR)\[\]"\`. \`""\` = use \`read_json_auto\`.

- extra_select:

  SQL fragment appended after \`SELECT \*\`, e.g. \`", abstract_expr AS
  abstract, 'p1' AS page"\`.

- workers:

  Number of parallel workers.

- verbose:

  Print failures to stderr.

## Value

Invisibly returns \`NULL\`.
