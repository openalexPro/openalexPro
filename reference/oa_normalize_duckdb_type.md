# Canonicalise a DuckDB type string.

Uppercases SQL type keywords (`BIGINT`, `VARCHAR`, `STRUCT`, ...) while
preserving the case of struct field identifiers.

## Usage

``` r
oa_normalize_duckdb_type(t)
```

## Arguments

- t:

  A character scalar: a raw DuckDB type string, e.g.
  `"struct(author struct(display_name varchar))"`.

## Value

A character scalar with normalised type keywords.
