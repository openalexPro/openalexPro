# Translate a query with OpenAlex's \`/query\` endpoint

Sends a query to OpenAlex's free \`POST /query\` endpoint, which
validates it and translates it into all of its forms: the OQO (OpenAlex
Query Object), OQL and the classic URL. No records are fetched and no
credits are spent.

## Usage

``` r
pro_translate(body, root = "https://api.openalex.org", api_key = pro_api_key())
```

## Arguments

- body:

  A list with exactly one of \`oql\` (an OQL string), \`oxurl\` (a
  classic query path such as \`"/works?filter=publication_year:2020"\`)
  or \`oqo\` (an OQO as a list).

- root:

  The API root, default \`"https://api.openalex.org"\`.

- api_key:

  API key or \`NULL\`. Default \[pro_api_key()\].

## Value

The parsed response: a list with \`oqo\`, \`oql\`, \`oql_oneline\`,
\`oxurl\` and \`validation\`. Stops with OpenAlex's validation messages
if the query is invalid.

## Examples

``` r
if (FALSE) { # \dontrun{
tr <- pro_translate(list(oql = "get works where published in 2020"))
tr$oqo
pro_translate(list(oxurl = "/works?filter=type:erratum"))$oql_oneline
} # }
```
