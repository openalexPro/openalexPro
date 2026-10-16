# Infer unified JSON schema using DuckDB

Infers the schema of each JSON/NDJSON file individually via DuckDB's
\`read_json_auto()\` and merges the results using type-widening rules.
Processing files one at a time avoids the out-of-memory errors that
occur when opening all files in a single DuckDB query.

## Usage

``` r
infer_json_schema(
  con,
  files,
  sample_size = 20,
  extra_options = "",
  verbose = TRUE,
  schema_cache_dir = NULL
)
```

## Arguments

- con:

  An active DuckDB connection (\`DBI::dbConnect(duckdb::duckdb())\`)
  with the JSON extension loaded (\`LOAD json\`).

- files:

  Character vector of paths to JSON or NDJSON (\`.gz\`) files.

- sample_size:

  Number of files to sample for schema inference. Higher values give
  more accurate schemas but take longer. Use \`0\` or \`NULL\` to use
  all files. Default is \`20\`.

- extra_options:

  Additional options appended to the \`read_json_auto\` SQL call, e.g.
  \`", maximum_object_size=1000000000"\` for large JSON objects. Default
  is \`""\`.

- verbose:

  If \`TRUE\`, print progress messages and a progress bar. Default is
  \`TRUE\`.

- schema_cache_dir:

  Path to a directory for caching per-file and unified schemas. The
  directory is created if it does not exist. \`NULL\` (default) disables
  caching.

## Value

A DuckDB columns clause string (e.g.
`"{'col1': 'VARCHAR', 'col2': 'BIGINT', ...}"`) suitable for use as the
\`columns\` argument to \`read_json()\`. Returns \`NULL\` if schema
inference fails for all files.

## Details

The returned columns clause can be passed directly to \`read_json(...,
columns = \<result\>)\` or \`read_json_auto(..., columns = \<result\>)\`
in subsequent DuckDB queries to enforce a consistent schema across all
files.

## Caching

When \`schema_cache_dir\` is provided, two levels of caching apply: -
\*\*Unified schema\*\* (\`unified_schema.csv\`): if present, loaded and
returned immediately — no DuckDB queries needed. Delete this file to
force re-inference. - \*\*Per-file schemas\*\*
(\`\<update_date\>\_\<part_name\>.csv\`): each file's schema is saved as
it is inferred. On restart, already-cached files are skipped, enabling
mid-run resume for large file sets.

## Type-widening rules

When a column has different types across files, the unified type is
chosen by these rules (in order): 1. All identical → keep as-is. 2. Any
\`STRUCT\`/\`LIST\`/\`MAP\` vs simpler type → complex type wins. 3.
Multiple \`STRUCT\` types → pick the one with the most fields. 4.
Numeric conflicts → widest type wins (\`TINYINT \< SMALLINT \< INTEGER
\< BIGINT \< HUGEINT \< FLOAT \< DOUBLE\`). 5. Fallback → \`VARCHAR\`.

## See also

\[pro_request_jsonl_parquet()\] (deprecated), which uses this function
internally.

## Examples

``` r
if (FALSE) { # \dontrun{
con <- DBI::dbConnect(duckdb::duckdb())
DBI::dbExecute(con, "LOAD json")
files <- list.files("path/to/snapshot/works", pattern = "\\.gz$",
                    recursive = TRUE, full.names = TRUE)
schema <- infer_json_schema(con, files, sample_size = 50,
                            schema_cache_dir = "path/to/cache")
DBI::dbDisconnect(con, shutdown = TRUE)
# schema is now a string like: {'id': 'VARCHAR', 'title': 'VARCHAR', ...}
} # }
```
