# Return the DuckDB SQL expression that reconstructs a plain-text abstract from the `abstract_inverted_index` MAP column in OpenAlex works data.

The expression walks the map, collects (position, word) pairs, sorts by
position ascending, and joins words with single spaces. Returns NULL
when `abstract_inverted_index` is NULL.

## Usage

``` r
oa_works_abstract_sql()
```

## Value

A character scalar containing the SQL expression.
