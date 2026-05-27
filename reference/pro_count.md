# Retrieve metadata counts for a PRO API request

Builds an \`httr2\` request targeting the OpenAlex PRO endpoint,
executes it, and extracts the pagination metadata. Only summary metadata
is requested and the first page is fetched to minimise API usage.

## Usage

``` r
pro_count(query_url, api_key = pro_api_key(), error_log = NULL)
```

## Arguments

- query_url:

  Character string containing the fully constructed OpenAlex PRO
  endpoint URL.

- api_key:

  Character string API key or \`NULL\`. Defaults to \`pro_api_key()\`.
  If \`NULL\` or \`""\`, the request is sent without an API key (subject
  to OpenAlex's unauthenticated limits).

- error_log:

  location of error log of API calls. (default: \`NULL\` (none)).

## Value

A data.frame containing \`count\`, \`db_response_time_ms\`, \`page\`,
and \`per_page\` elements. If count is negative, the size of the request
is larger then the allowed limit of 4094. If the request fails, each
value is \`NA\`.

## Examples

``` r
if (FALSE) { # \dontrun{
meta <- pro_count("https://api.openalex.org/works?filter=host_venue.id:V123")
meta[["count"]]
} # }
```
