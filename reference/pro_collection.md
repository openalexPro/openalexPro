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
  access = NULL,
  fetch_first = FALSE,
  api_key,
  api_key_fetch = api_key,
  verbose = FALSE,
  progress = TRUE,
  ...
)
```

## Arguments

- query_url:

  A query from
  [`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md),
  or a named (nested) list of queries. Without `name`, each element of
  the list becomes its own collection, named after its list names
  (nested names joined with `_`). With `name`, all queries in the list
  go into one collection (see **Several queries in one collection**).

- name:

  Name of the collection (and of its folder). Required for a single
  query. For a list: `NULL` gives one collection per element, a name
  gives one collection for the whole list.

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

  If `TRUE`, make the members of the collection match the query now
  (adding and removing members; the ID stays) and download again. Also
  takes over a collection of the same name that is not recorded in
  `project_folder`.

- access:

  Who can see the collection: `"private"` (only you, the default for new
  collections), `"shared_by_link"` (anyone with its link or ID can view
  it and filter by it; it is not listed) or `"public"` (only OpenAlex
  can set this for now; OpenAlex refuses it with HTTP 403). `NULL`
  (default) leaves it as it is.

- fetch_first:

  If `TRUE`, fill a single query's collection by fetching its IDs with
  [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
  and adding them as members, instead of an import (see **Fetch
  first**). A list with `name` is always filled this way.

- api_key:

  A personal OpenAlex API key for the collection calls. Required.

- api_key_fetch:

  The OpenAlex API key for the queries that fill the collection.
  Defaults to `api_key`.

- verbose:

  Print the collection ID(s).

- progress:

  Show the steps and import progress.

- ...:

  Passed to
  [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
  when records are downloaded, and when the queries of a list with
  `name` are fetched (e.g. `workers`, `compact_parquet`).

## Value

Invisibly, the path of the `.collection` folder, or a named character
vector of paths for a list of queries without `name`.

## Details

Each query gets a folder `<project_folder>/<name>.collection/` with

- `_collection.json`:

  the query (URL, OQL, OQO), the collection (`collection_id`,
  `display_name`, `entity_type`, `member_count`, ...), each import, the
  credits used and the `select` that was downloaded.

- `_query_oql.txt`, `_query_oql.html`:

  the query in readable OQL.

- `_parts.parquet`:

  for a list of queries in one collection (see **Several queries in one
  collection**): the name and URL of each query. `_collection.json` then
  holds no queries, so it stays small however long the list is.

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

- `refresh = TRUE`, with the same or a changed query: the collection
  keeps its ID, and its members are made to match the query now: the
  query's IDs are fetched with
  [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
  (`select = "id"`, same credits as an import), new ones are added and
  members no longer found are removed (free, 10,000 added or 100 removed
  per request). Everything is then downloaded again.

- Changed query without `refresh`: the old collection is deleted and a
  new one is created under the same name (it gets a new ID).

So `refresh = TRUE` always keeps the ID (links and saved searches keep
working). Only when the collection is gone on OpenAlex, or holds another
entity, is a new one created.

**Local folder gone:** a collection with the same name that exists in
your account but is not recorded in `project_folder` is never deleted.
Without `refresh`, `pro_collection()` stops. With `refresh = TRUE` it
takes that collection over: the ID stays, its members are synced to the
query as above, and the folder is written again. Names match ignoring
case, and the collection must hold the same entity.

**Costs:** creating and managing collections and downloading the member
IDs are free. An import costs the same credits as paging through the
results yourself (one list request per 200 results). Imports run at
about 200 results per second (measured November 2026), so a collection
of the maximum 1,000,000 members takes over an hour. Interrupting
`pro_collection()` does not stop the import on the server; running it
again waits for it.

**Several queries in one collection:** OpenAlex imports a query of at
most 20,000 characters of OQL (about 600 to 800 DOIs); a longer single
query stops before anything is created. For long ID or DOI lists, split
them into chunks, e.g. `pro_query(doi = dois, chunk_limit = 200)`, and
pass the list with `name`. The queries are then not imported: they are
fetched with
[`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
(`select = "id"`, in parallel with `workers`) and the IDs are added to
the collection (`member_ids`, 10,000 per request, free). This costs the
same credits as imports and was about five times faster with
`workers = 8` (3,000 DOIs: 8.5 s instead of 45 to 55 s, November 2026).
Fields in `select` beyond `id` are fetched in the same pass, from the
queries themselves, so the records do not depend on the collection
filter limit. An interrupted run resumes the fetch and syncs the members
again (syncing is idempotent). A changed query re-creates the collection
unless `refresh = TRUE`, which keeps it, fetches everything again and
syncs the members.

**Fetch first:** the queries are fetched *before* the collection is
created, so a query that fails leaves no empty collection behind. This
is always the route for a list with `name`; `fetch_first = TRUE` takes
it for single queries too (and for each element of a list without
`name`) instead of an import. OpenAlex does not check that the IDs it is
given exist, but these come from the queries, so they do.

**Limits:** 1,000,000 members per collection, 500 collections per
account, names up to 100 characters and unique per account. A collection
with more than 300,000 members (100,000 for authors) cannot be used as a
filter, so its records cannot be downloaded with `select`; its member
IDs can. Queries with `group_by` or `sample` cannot be imported.

**Core and expansion works:** a collection holds all its members, and
the member IDs in `members/` include expansion works (DataCite,
repositories). A *filter* by a works collection returns only its core
works unless `corpus = "all"` is set, so the records in `records/` are
fetched with `corpus = "all"`, and later queries should set it too:
`pro_query(collection = id, options = list(corpus = "all"))`. Whether
expansion works get into the collection depends on the query that fills
it (`options = list(corpus = "all")` in
[`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)).

**API keys:** collections need a *personal* OpenAlex API key
(`api_key`); organisation keys and some older keys are refused (HTTP
401) even when they work for queries. The queries that fill the
collection can run with another key (`api_key_fetch`, e.g. one with a
larger daily budget); they cost credits, the collection calls do not.
Records downloaded through the collection filter (the import route) use
`api_key`: a private collection is visible only to its owner's key
(another key gets HTTP 404).

## See also

[`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md),
[`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md),
[`vignette("collections")`](https://openalexpro.github.io/openalexPro/articles/collections.md).

## Examples

``` r
if (FALSE) { # \dontrun{
key <- keyring::key_get("API_openalex_personal") # a personal key
q <- pro_query(search = "coral bleaching", publication_year = 2024)
f <- pro_collection(q, name = "coral bleaching 2024", project_folder = "proj",
                    api_key = key)
id <- jsonlite::read_json(file.path(f, "_collection.json"))$collection_id

# Later: records of the collection that are open access. corpus = "all":
# without it, the filter returns only the core works. A private collection
# is visible only with its owner's key
pro_fetch(pro_query(collection = id, is_oa = TRUE, options = list(corpus = "all")),
          project_folder = "oa", api_key = key)

# Let anyone with the link or ID use it
pro_collection(q, name = "coral bleaching 2024", project_folder = "proj",
               api_key = key, access = "shared_by_link")

# Add titles to the download (re-downloads the records)
pro_collection(q, name = "coral bleaching 2024", project_folder = "proj",
               api_key = key, select = c("id", "title"))

# A long DOI list in one collection: the chunks are fetched in parallel
# and their IDs added as members
pro_collection(pro_query(doi = dois, chunk_limit = 200), name = "my dois",
               project_folder = "proj", api_key = key,
               api_key_fetch = pro_api_key(), workers = 8)

# A single query, fetched first instead of imported
pro_collection(q, name = "coral 2024 fetched", project_folder = "proj",
               api_key = key, fetch_first = TRUE)
} # }
```
