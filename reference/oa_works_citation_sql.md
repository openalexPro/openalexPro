# Return the DuckDB SQL expression that builds a short citation string from the \`authorships\` and \`publication_year\` columns in OpenAlex works data.

Format: \`"Author (year)"\` / \`"A & B (year)"\` / \`"A et al.
(year)"\`. Null year renders as \`"(n.d.)"\`. Null or empty
\`authorships\` yields NULL.

## Usage

``` r
oa_works_citation_sql()
```

## Value

A character scalar containing the SQL expression.
