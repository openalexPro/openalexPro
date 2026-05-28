# Convert JSON files from pro_request() directly to Apache Parquet

Single-step replacement for the two-step
[`pro_request_jsonl_R()`](https://rkrug.github.io/openalexPro/reference/pro_request_jsonl_R.md) +
[`pro_request_jsonl_parquet()`](https://rkrug.github.io/openalexPro/reference/pro_request_jsonl_parquet.md)
pipeline. Reads the JSON files written by
[`pro_request()`](https://rkrug.github.io/openalexPro/reference/pro_request.md)
and converts each one to a Parquet file using DuckDB, with no
intermediate JSONL on disk.

## Usage

``` r
pro_request_parquet(
  input_json = NULL,
  output = NULL,
  add_columns = list(),
  overwrite = FALSE,
  verbose = TRUE,
  progress = TRUE,
  delete_input = FALSE,
  sample_size = 1000,
  workers = NULL,
  enrich = TRUE,
  schema = "auto"
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

  Logical. Show a progress bar. Default `TRUE`.

- delete_input:

  Logical. Delete `input_json` after a successful conversion. Default
  `FALSE`.

- sample_size:

  Integer. Number of records per file passed to DuckDB's `sample_size`
  option during schema inference. Use `-1` to read all records (accurate
  but slow for large files). Default `1000`.

- workers:

  Integer. Number of parallel workers. `NULL` or `1` runs sequentially.
  Default `NULL`.

- enrich:

  Logical. When `TRUE` (the default) and the inferred schema contains
  `abstract_inverted_index` / `authorships` / `publication_year`, add
  `abstract` and `citation` computed columns.

- schema:

  Controls use of a pre-built baseline schema for type resolution.
  Possible values:

  `"auto"` (default)

  :   Auto-detect the OpenAlex entity type from the inferred columns,
      then load the matching schema from the user cache (populated by
      [`oa_cache_schema()`](https://rkrug.github.io/openalexPro/reference/oa_cache_schema.md))
      or the schemas bundled with the package. For each column where
      DuckDB runtime inference produced the ambiguous `JSON` fallback
      type, the baseline type is used instead. Falls back silently to
      runtime-only inference when the entity cannot be detected or no
      schema is found.

  `"none"` or `NULL`

  :   Skip the baseline entirely; behaviour is identical to package
      versions before this feature was added.

  A file path

  :   Path to a CSV with columns `col_name` / `col_type`. Used directly
      as the baseline.

  A directory path

  :   Auto-detect entity, then look for `<entity>.csv` inside that
      directory. Useful when pointing directly at a snapshot-metadata
      schemata directory.

## Value

Output directory path (invisibly).

## Details

For works entities the function detects the presence of
`abstract_inverted_index`, `authorships`, and `publication_year` in the
inferred schema and, when `enrich = TRUE` (the default), adds two
computed columns:

- **`abstract`** — plain text reconstructed from
  `abstract_inverted_index`.

- **`citation`** — `"Author (year)"` / `"A & B (year)"` /
  `"A et al. (year)"`.

These expressions are identical to those used by the `openalex-snapshot`
CLI binary, so the Parquet output matches the snapshot pipeline column
for column.

## File format

[`pro_request()`](https://rkrug.github.io/openalexPro/reference/pro_request.md)
writes one JSON file per API page. For paginated queries each file has
the structure `{"results": [...], "meta": {...}}`. For group-by queries
the array field is `"group_by"`. For single-record lookups the file is a
bare JSON object. All three formats are handled automatically.

## Output layout

The subdirectory structure of `input_json` is preserved, with
hive-partition naming (`query=<name>/`, `query_l2=<name>/`, …) so that
Arrow/DuckDB can read the result as a partitioned dataset. A `page`
column is added to each record with a value derived from the source
filename (or subdirectory for multi-query inputs).

## See also

[`pro_request()`](https://rkrug.github.io/openalexPro/reference/pro_request.md)
to download the JSON files,
[`pro_request_jsonl_R()`](https://rkrug.github.io/openalexPro/reference/pro_request_jsonl_R.md)
and
[`pro_request_jsonl_parquet()`](https://rkrug.github.io/openalexPro/reference/pro_request_jsonl_parquet.md)
for the older two-step pipeline (now deprecated).
