# Build an OpenAlex request (httr2)

Construct an `httr2` request for the OpenAlex API. All filters must be
supplied as named `...` arguments (e.g.,
`from_publication_date = "2020-01-01"`).

## Usage

``` r
pro_query(
  entity = c("works", "authors", "venues", "institutions", "concepts", "publishers",
    "funders"),
  id = NULL,
  doi = NULL,
  search = NULL,
  search.exact = NULL,
  search.semantic = NULL,
  group_by = NULL,
  select = NULL,
  options = NULL,
  endpoint = "https://api.openalex.org",
  chunk_limit = 50L,
  ...
)
```

## Arguments

- entity:

  Character; one of `"works"`, `"authors"`, `"venues"`,
  `"institutions"`, `"concepts"`, `"publishers"`, `"funders"`.

- id:

  Optional ID or vector of IDs (e.g., `"W1775749144"`). If a single ID
  is provided, fetches one entity directly. If multiple IDs are
  provided, they are automatically moved into the `ids.openalex` filter.

- doi:

  Optional DOI or vector of DOIs (e.g., `"10.1038/s41586-021-03819-2"`).
  Values are moved into the `doi` filter and automatically chunked into
  separate requests when the number of DOIs exceeds `chunk_limit`.

- search:

  Optional full-text search string. Applies stemming and stop-word
  removal. Supports boolean operators (`AND`, `OR`, `NOT` in uppercase),
  quoted phrases (`"exact phrase"`), proximity (`"word1 word2"~N`),
  wildcards (`*`, `?`), and fuzzy matching (`term~N`). Replaces the
  deprecated `filter = field.search:keyword` syntax.

- search.exact:

  Optional full-text search without stemming or stop-word removal.
  Supports the same boolean/phrase/wildcard syntax as `search`. Use when
  you need to match exact word forms (e.g. `"surgery"` should not match
  `"surgical"`).

- search.semantic:

  Optional semantic (AI-powered) search string. Uses embeddings to match
  conceptual meaning rather than exact keywords. Limited to 1 request
  per second and returns at most 50 results per query.

- group_by:

  Optional field to group by (facets), e.g. `"type"`.

- select:

  Optional character vector of fields to return.

- options:

  Optional named list of additional query parameters (e.g.,
  `list(per_page = 200, sort = "cited_by_count:desc", cursor = "*", sample = 100)`).

- endpoint:

  Base API URL. Defaults to `"https://api.openalex.org"`.

- chunk_limit:

  Number of DOIS or ids per chunk if chunked. Default: 50

- ...:

  Filters as named arguments. Values may be scalars or vectors (vectors
  are collapsed with `"|"` to express OR).

## Value

An individual URL or a list of URLs.

## Details

Filter names are validated via `.validate_filter()` using
[`opt_filter_names()`](https://rkrug.github.io/openalexPro/reference/opt_filter_names.md).
`select` fields are validated via `.validate_select()` using
`` `opt_select_fields()` ``.

If multiple more then 50 \`doi\` or openalex \`id\`s are provided, the
request is automatically split into chunks of 50 and a named list of
URLs is returned.

## Search syntax

All three search parameters (`search`, `search.exact`,
`search.semantic`) accept a query string. For `search` and
`search.exact`, the following syntax is supported:

- Boolean: `biodiversity AND finance`, `climate OR weather`,
  `ocean NOT pollution` (operators must be uppercase).

- Exact phrase: `"biodiversity finance"` (double quotes).

- Proximity: `"biodiversity finance"~5` (words within 5 positions).

- Wildcard: `bio*` (zero or more characters), `organi?ation`.

- Fuzzy: `biodiversty~1` (allows 1 character edit).

`search.semantic` does not use keyword syntax; pass a natural-language
phrase or even a full abstract. It returns at most 50 results per call.

## Deprecated search filters

Filter arguments with a `.search` suffix (e.g.
`title_and_abstract.search = "biodiversity"`) are deprecated by the
OpenAlex API. They still work but emit a warning. Use the `search`,
`search.exact`, or `search.semantic` parameters instead. See
<https://developers.openalex.org/guides/searching> for details.

## Examples

``` r
if (FALSE) { # \dontrun{

req <- oa_build_req(
  entity = "works",
  search = "biodiversity",
  from_publication_date = "2020-01-01",
  language = c("en","de"),
  select = c("id","title","publication_year"),
  options = list(per_page = 5)
)
# resp <- api_call(req)
# httr2::resp_body_json(resp)
} # }
```
