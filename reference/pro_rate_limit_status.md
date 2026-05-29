# Check OpenAlex rate limit status

Queries the OpenAlex rate-limit endpoint and returns current API usage
and remaining budget as a parsed list.

## Usage

``` r
pro_rate_limit_status(api_key = pro_api_key(), verbose = TRUE)
```

## Arguments

- api_key:

  API key (character string) or \`NULL\`. Defaults to
  [`pro_api_key()`](https://openalexpro.github.io/openalexPro/reference/pro_api_key.md).
  If \`NULL\` or \`""\`, this function returns `FALSE` with an
  informational message.

- verbose:

  Logical. If `TRUE` (default), prints rate limit info via
  [`message()`](https://rdrr.io/r/base/message.html).

## Value

Invisibly, the parsed JSON list with all rate limit fields; `FALSE` if
the API key is missing or invalid; or `NULL` if the request failed due
to a network error.
