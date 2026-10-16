# Build an OpenAlex request (httr2)

Construct an `httr2` request for the OpenAlex API. All filters must be
supplied as named `...` arguments (e.g.,
`from_publication_date = "2020-01-01"`).

## Usage

``` r
pro_query(
  entity = c("works", "authors", "venues", "institutions", "concepts", "publishers",
    "funders", "sources", "topics", "locations"),
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
  oql = NULL,
  oqo = NULL,
  ...
)
```

## Arguments

- entity:

  Character; one of `"works"`, `"authors"`, `"institutions"`,
  `"publishers"`, `"funders"`, `"sources"`, `"topics"`, `"locations"`.
  `"venues"` (now `"sources"`) and `"concepts"` (now `"topics"`) are
  deprecated by OpenAlex and kept only for compatibility.

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
  quoted phrases (`"exact phrase"`) and proximity (`"word1 word2"~N`).
  Wildcards are rejected by the API (HTTP 400): use `search.exact`.
  Replaces the deprecated `filter = field.search:keyword` syntax.

- search.exact:

  Optional full-text search without stemming or stop-word removal.
  Supports the boolean/phrase/proximity syntax of `search`, plus
  wildcards and fuzzy matching. Use when you need to match exact word
  forms (e.g. `"surgery"` should not match `"surgical"`).

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
  `list(sort = "cited_by_count:desc", sample = 100, seed = 42)`).
  [`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
  does the paging, so `page` and `cursor` given here are replaced (with
  a warning); `per_page` is kept (1–200, default 200). A `sample` (up to
  10,000) is paged by page number and needs a `seed` when it spans
  several pages;
  [`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
  picks and reports one if none is given.

- endpoint:

  Base API URL. Defaults to `"https://api.openalex.org"`.

- chunk_limit:

  Number of DOIS or ids per chunk if chunked. Default: 50

- oql:

  Optional OQL (OpenAlex Query Language) query string, e.g.
  `"works where year is (2020) and type is (article)"`. See section *OQL
  and OQO*.

- oqo:

  Optional OQO (OpenAlex Query Object): a nested list, or a JSON string.
  See section *OQL and OQO*.

- ...:

  Filters as named arguments. Values may be scalars or vectors (vectors
  are collapsed with `"|"` to express OR). Arguments of the functions
  that send the query, such as `via` or `workers`, belong to
  \[pro_fetch()\], \[pro_request()\] or \[pro_count()\], not here.

## Value

An individual URL or a list of URLs.

## Details

Filter names are validated against `opt_filter_names(entity = entity)`
and `select` fields against `opt_select_fields(entity = entity)`, i.e.
against the names OpenAlex accepts for the queried entity.

If multiple more then 50 \`doi\` or openalex \`id\`s are provided, the
request is automatically split into chunks of 50 and a named list of
URLs is returned.

## Search syntax

All three search parameters (`search`, `search.exact`,
`search.semantic`) accept a query string. For `search` and
`search.exact`, the following syntax is supported:

- Boolean: `biodiversity AND finance`, `climate OR weather`,
  `ocean NOT pollution` (operators must be uppercase); group with
  parentheses. Words without an operator between them are combined with
  `AND`.

- Exact phrase: `"biodiversity finance"` (double quotes).

- Proximity: `"biodiversity finance"~5` (words within 5 positions), or
  two phrases near each other: `"machine learning"~5~"neural network"`.

Only with `search.exact` (the stemmed `search` rejects wildcards with
HTTP 400, and stemming distorts fuzzy terms):

- Wildcard: `microbio*` (zero or more characters), `organi?ation`
  (exactly one). At least 3 characters before the wildcard; no leading
  wildcard.

- Fuzzy: `biodiversty~1` (up to N character edits, N = 0–2; at least 3
  characters before the `~`).

See <https://help.openalex.org/api/searching/>. `search.semantic` does
not use keyword syntax; pass a natural-language phrase or even a full
abstract. It returns at most 50 results per call.

## OQL and OQO

OpenAlex's query language (`oql`) and its JSON form (`oqo`) express
queries the classic filter syntax cannot, such as nested `and` / `or`
conditions. The entity, all conditions, grouping (`group by`), `sample`
and `corpus` belong inside the query, so `entity`, `id`, `doi`, the
search arguments, `group_by` and filters in `...` cannot be combined
with it – OpenAlex would silently ignore them. `select` and `options`
(e.g. `sort`) are passed alongside. The URL targets the API root
(`https://api.openalex.org/?oql=...`) and works with
[`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md),
[`pro_count()`](https://openalexpro.github.io/openalexPro/reference/pro_count.md)
and
[`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
as usual. An invalid query fails at request time with OpenAlex's parse
error. See <https://help.openalex.org/api/oql/>.

## Deprecated search filters

Filter arguments with a `.search` suffix (e.g.
`title_and_abstract.search = "biodiversity"`) are deprecated by the
OpenAlex API. They still work but emit a warning. Use the `search`,
`search.exact`, or `search.semantic` parameters instead. See
<https://help.openalex.org/api/searching/> for details.

## Examples

``` r
if (FALSE) { # \dontrun{

url <- pro_query(
  entity = "works",
  search = "biodiversity",
  from_publication_date = "2020-01-01",
  language = c("en","de"),
  select = c("id","title","publication_year"),
  options = list(per_page = 5)
)

# OQL: nested conditions the filter syntax cannot express
url <- pro_query(
  oql = "works where year >= (2020) and (title has (coral) or title has (reef))"
)

# OQO: the same kind of query as a nested list
url <- pro_query(oqo = list(
  get_rows = "works",
  filter_rows = list(list(column_id = "publication_year", value = 2020))
))
} # }
```
