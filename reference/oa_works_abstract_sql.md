# Return the DuckDB SQL expression that reconstructs a plain-text abstract from the `abstract_inverted_index` column in OpenAlex works data.

The expression walks the map, collects (position, word) pairs, sorts by
position ascending, and joins words with single spaces. Returns NULL
when `abstract_inverted_index` is NULL.

## Usage

``` r
oa_works_abstract_sql()
```

## Value

A character scalar containing the SQL expression.

## Details

`abstract_inverted_index` is normalised to `MAP(VARCHAR, BIGINT[])` via
a double JSON cast (`::JSON::MAP(VARCHAR, BIGINT[])`) before
`map_entries()` is called. This makes the expression safe regardless of
whether DuckDB inferred the column as `MAP`, `STRUCT`, or `VARCHAR` (raw
JSON text): all three round-trip through the JSON representation
identically.
