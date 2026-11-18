# Create OpenAlex collections from queries

Turns each query into an OpenAlex
[collection](https://help.openalex.org/api/collections): a saved set of
IDs on OpenAlex's servers that can be reused in later queries
(`pro_query(collection = "col_...")`) and combined with other
collections. OpenAlex runs the query itself (an *import*);
`pro_collection()` waits for it and then downloads what `select` asks
for.

## Usage

``` r
pro_collection(
  query_url,
  name = NULL,
  project_folder,
  select = "id",
  refresh = FALSE,
  api_key = pro_api_key(),
  verbose = FALSE,
  progress = TRUE,
  ...
)
```

## Arguments

- query_url:

  A query from
  [`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md),
  or a named (nested) list of queries: each element becomes its own
  collection, named after its list names (nested names joined with `_`).
  A list of chunks from
  [`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)
  would give one collection per chunk; use
  `pro_query(..., chunk_limit = 1e6)` to keep one query in one URL (the
  import has no URL length limit).

- name:

  Name of the collection (and of its folder) for a single query. For a
  list, the list names are used and `name` must be `NULL`.

- project_folder:

  Directory for the `<name>.collection` folders.

- select:

  What to download: `"id"` (default) the member IDs only; `NULL`
  nothing; `"all"` the full records; or a character vector of fields
  (see
  [`opt_select_fields()`](https://openalexpro.github.io/openalexPro/reference/opt_select_fields.md))
  for records with those fields. The member IDs are downloaded whenever
  `select` is not `NULL`.

- refresh:

  If `TRUE`, import an unchanged query again and re-download.

- api_key:

  A personal OpenAlex API key.

- verbose:

  Print the collection ID(s).

- progress:

  Show the steps and import progress.

- ...:

  Passed to
  [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
  when records are downloaded (e.g. `workers`, `compact_parquet`).

## Value

Invisibly, the path of the `.collection` folder, or a named character
vector of paths for a list of queries.

## Details

Each query gets a folder `<project_folder>/<name>.collection/` with

- `_collection.json`:

  the query (URL, OQL, OQO), the collection (`collection_id`,
  `display_name`, `entity_type`, `member_count`, ...), each import, the
  credits used and the `select` that was downloaded.

- `_query_oql.txt`, `_query_oql.html`:

  the query in readable OQL.

- `members/parquet/`:

  the member IDs (`id`, `added_at`).

- `records/`:

  the records when `select` asks for more than `id` (the
  [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
  layout).

**Running it again** with the same `project_folder` and `name`:

- Same query: the collection is kept (same ID). An import still running
  (e.g. after an interruption) is waited for. Only the downloads are
  brought in line with `select`: removed fields are dropped locally (no
  requests), added fields re-download the records. Credits are charged
  per request, not per field, so fetching only the new fields would cost
  the same.

- `refresh = TRUE`: the query is imported again into the same
  collection, adding works that match it now, and everything is
  downloaded again. An import only adds: members that no longer match
  stay.

- Changed query: the old collection is deleted and a new one is created
  under the same name (it gets a new ID).

**Costs:** creating and managing collections and downloading the member
IDs are free. An import costs the same credits as paging through the
results yourself (one list request per 200 results). Imports run at
about 200 results per second (measured November 2026), so a collection
of the maximum 1,000,000 members takes over an hour. Interrupting
`pro_collection()` does not stop the import on the server; running it
again waits for it.

**Limits:** 1,000,000 members per collection, 500 collections per
account, names up to 100 characters and unique per account. A collection
with more than 300,000 members (100,000 for authors) cannot be used as a
filter, so its records cannot be downloaded with `select`; its member
IDs can. Queries with `group_by` or `sample` cannot be imported.

**API key:** collections need a *personal* OpenAlex API key;
organisation keys and some older keys are refused (HTTP 401) even when
they work for queries.

## See also

[`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md),
[`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md),
[`vignette("collections")`](https://openalexpro.github.io/openalexPro/articles/collections.md).

## Examples

``` r
if (FALSE) { # \dontrun{
q <- pro_query(search = "coral bleaching", publication_year = 2024)
f <- pro_collection(q, name = "coral bleaching 2024", project_folder = "proj")
id <- jsonlite::read_json(file.path(f, "_collection.json"))$collection_id

# Later: records of the collection that are open access
pro_fetch(pro_query(collection = id, is_oa = TRUE), project_folder = "oa")

# Add titles to the download (re-downloads the records)
pro_collection(q, name = "coral bleaching 2024", project_folder = "proj",
               select = c("id", "title"))
} # }
```
