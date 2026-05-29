# `pro_query()` - Background and Technical Documentation

## Introduction

The
[`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)
function is the foundation of the `openalexPro` workflow. It constructs
well-formed URLs for querying the OpenAlex API, handling parameter
validation, filter construction, and automatic request chunking for
large queries.

This vignette provides a comprehensive guide to using
[`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md),
including:

- OpenAlex API concepts and URL structure
- Basic usage patterns
- Advanced filtering and selection
- Automatic chunking for large queries
- Error handling and validation
- Internal architecture and flow diagrams
- Helper function documentation

## OpenAlex API Concepts

### Entities

OpenAlex organizes scholarly data into seven main entity types:

| Entity         | Description                                     | Example ID  |
|----------------|-------------------------------------------------|-------------|
| `works`        | Scholarly documents (articles, books, datasets) | W2741809807 |
| `authors`      | People who create works                         | A2208157607 |
| `institutions` | Universities, research organizations            | I4200000001 |
| `venues`       | Journals, repositories, conferences             | V123456789  |
| `concepts`     | Topics and fields of study                      | C12345678   |
| `publishers`   | Organizations that publish venues               | P4310319965 |
| `funders`      | Organizations that fund research                | F1234567    |

### URL Structure

OpenAlex API URLs follow this pattern:

    https://api.openalex.org/{entity}[/{id}]?[filter=...][&search=...][&select=...][&group_by=...][&options...]

``` mermaid
flowchart LR
    subgraph URL[URL Components]
        Base[api.openalex.org]
        Entity["/works"]
        ID["/{id}"]
        Filter["?filter=..."]
        Search["&search=..."]
        Select["&select=..."]
        GroupBy["&group_by=..."]
        Options["&per_page=..."]
    end

    Base --> Entity
    Entity --> ID
    Entity --> Filter
    ID --> Filter
    Filter --> Search
    Search --> Select
    Select --> GroupBy
    GroupBy --> Options

    style Base fill:#e1f5e1
    style Entity fill:#cce5ff
    style Filter fill:#fff3cd
    style Select fill:#f8d7da
```

#### Example URLs

    # All works (paginated)
    https://api.openalex.org/works

    # Single work by ID
    https://api.openalex.org/works/W2741809807

    # Filtered works
    https://api.openalex.org/works?filter=from_publication_date:2020-01-01,type:article

    # With search and select
    https://api.openalex.org/works?search=climate+change&select=ids,title,publication_year

## Function Parameters Reference

| Parameter | Type | Default | Description |
|----|----|----|----|
| `entity` | character | required | Entity type: “works”, “authors”, “venues”, “institutions”, “concepts”, “publishers”, “funders” |
| `id` | character | NULL | Single entity ID for direct retrieval. Multiple IDs are moved to `ids.openalex` filter |
| `search` | character | NULL | Full-text search string |
| `group_by` | character | NULL | Field to group by for faceted counts |
| `select` | character vector | NULL | Fields to return (validated against [`opt_select_fields()`](https://openalexpro.github.io/openalexPro/reference/opt_select_fields.md)) |
| `options` | named list | NULL | Additional query parameters (per_page, sort, cursor, sample) |
| `endpoint` | character | “https://api.openalex.org” | Base API URL |
| `chunk_limit` | integer | 50 | Maximum items per chunk for chunkable filters |
| `...` | named arguments | \- | Filters (validated against [`opt_filter_names()`](https://openalexpro.github.io/openalexPro/reference/opt_filter_names.md)) |

## Basic Usage

### Simple Query

The most basic query requires only an entity type:

``` r

library(openalexPro)

# Query for works
url <- pro_query(entity = "works")
url
# [1] "https://api.openalex.org/works"
```

### Search Modes

[`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)
supports three mutually exclusive search parameters, each with different
matching behaviour and cost:

| Parameter | Matching | Max results | Cost |
|----|----|----|----|
| `search` | Stemmed keyword (stop-words removed) | Unlimited | \$0.0001/call |
| `search.exact` | Unstemmed, supports boolean/phrase/wildcard | Unlimited | \$0.0001/call |
| `search.semantic` | AI embedding similarity | 50 per call | \$0.001/call |

#### `search` — Standard Keyword Search

Searches title, abstract, and full text with stemming and stop-word
removal. Supports the same boolean/phrase syntax as `search.exact` but
also applies stemming (e.g. “run” also matches “running”, “ran”):

``` r

url <- pro_query(
  entity = "works",
  search = "climate change biodiversity"
)
url
# [1] "https://api.openalex.org/works?search=climate%20change%20biodiversity"
```

#### `search.exact` — Unstemmed / Boolean Search

Searches without stemming or stop-word removal. Supports:

- Boolean operators: `AND`, `OR`, `NOT`
- Quoted phrases: `"deep learning"`
- Proximity: `"climate change"~5` (within 5 words)
- Wildcards: `microbio*`

``` r

# Exact phrase search
url <- pro_query(
  entity = "works",
  search.exact = '"large language models" AND (safety OR alignment)'
)

# Wildcard — matches microbiology, microbiome, microbiota, …
url <- pro_query(
  entity = "works",
  search.exact = "microbio*",
  from_publication_date = "2020-01-01"
)
```

#### `search.semantic` — AI-Powered Similarity Search (Find Similar Works)

Converts your query to a 1 024-dimension embedding and returns the most
conceptually similar works — regardless of whether they share any
keywords. This is OpenAlex’s [“find similar
works”](https://docs.openalex.org/how-to-use-the-api/find-similar-works)
feature.

**Constraints:**

- Maximum **50 results** per call (the API hard-codes this).
- Requires an API key (costs \$0.001 per call).
- Rate-limited to **1 request per second**.
- Pass a sentence or short paragraph — not just a keyword.

``` r

# Find works conceptually similar to an abstract or research question
url <- pro_query(
  entity = "works",
  search.semantic = paste(
    "Large language models trained on scientific text can assist researchers",
    "in hypothesis generation and literature synthesis."
  )
)

# Combine with filters to narrow the similarity search
url <- pro_query(
  entity = "works",
  search.semantic = "CRISPR base editing for treating sickle cell disease",
  from_publication_date = "2019-01-01",
  type = "article",
  select = c("ids", "title", "publication_year", "cited_by_count")
)
```

> **Note:** Semantic search returns at most 50 results. For large-scale
> retrieval, combine `search` or `search.exact` with
> [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md).

### Field Selection

Use the `select` parameter to specify which fields to return. This
reduces response size and improves performance:

``` r

url <- pro_query(
  entity = "works",
  search = "machine learning",
  select = c("ids", "title", "publication_year", "cited_by_count")
)
url
# [1] "https://api.openalex.org/works?search=machine%20learning&select=ids,title,publication_year,cited_by_count"
```

#### Available Select Fields

Use
[`opt_select_fields()`](https://openalexpro.github.io/openalexPro/reference/opt_select_fields.md)
to see all available fields:

``` r

opt_select_fields()
# [1] "abstract_inverted_index" "authorships"
# [3] "biblio"                  "cited_by_count"
# [5] "concepts"                "corresponding_author_ids"
# ...
```

### Single Entity Retrieval

Fetch a specific entity by its OpenAlex ID:

``` r

url <- pro_query(
  entity = "works",
  id = "W2741809807"
)
url
# [1] "https://api.openalex.org/works/W2741809807"
```

#### External Identifiers

You can use any identifier listed in an entity’s `ids` field — not just
the OpenAlex ID. The API accepts three formats:

| Format            | Example                              |
|-------------------|--------------------------------------|
| Full URL          | `https://doi.org/10.7717/peerj.4375` |
| `namespace:value` | `doi:10.7717/peerj.4375`             |
| OpenAlex key      | `W2741809807`                        |

**Works** — DOI:

``` r

# By DOI (full URL format)
url <- pro_query(
  entity = "works",
  id = "https://doi.org/10.7717/peerj.4375"
)

# By DOI (namespace format)
url <- pro_query(
  entity = "works",
  id = "doi:10.7717/peerj.4375"
)
```

**Authors** — ORCID:

``` r

url <- pro_query(
  entity = "authors",
  id = "orcid:0000-0003-1613-5981"
)
```

**Institutions** — ROR:

``` r

url <- pro_query(
  entity = "institutions",
  id = "ror:02mhbdp94" # MIT
)
```

**Sources (journals)** — ISSN:

``` r

url <- pro_query(
  entity = "sources",
  id = "issn:0028-0836" # Nature
)
```

> **Tip:** For bulk lookup of multiple DOIs or IDs, use a filter
> (`doi = c(...)`) rather than the `id` parameter —
> [`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)
> will automatically chunk them into batches of up to 50.

## Filtering

Filters are the primary way to narrow down query results. They are
passed as named arguments via `...`.

### Filter Syntax

``` mermaid
flowchart TD
    subgraph FilterSyntax[Filter Syntax in URL]
        Single["filter=type:article"]
        Multiple["filter=type:article,language:en"]
        OR["filter=type:article|preprint"]
        Combined["filter=type:article|preprint,language:en|de"]
    end

    subgraph RCode[R Code Equivalent]
        RSingle["type = 'article'"]
        RMultiple["type = 'article',<br/>language = 'en'"]
        ROR["type = c('article', 'preprint')"]
        RCombined["type = c('article', 'preprint'),<br/>language = c('en', 'de')"]
    end

    RSingle --> Single
    RMultiple --> Multiple
    ROR --> OR
    RCombined --> Combined

    style FilterSyntax fill:#cce5ff
    style RCode fill:#e1f5e1
```

### Basic Filters

Filters use AND logic between different filter types:

``` r

url <- pro_query(
  entity = "works",
  from_publication_date = "2020-01-01",
  to_publication_date = "2023-12-31",
  type = "article"
)
url
# filter=from_publication_date:2020-01-01,to_publication_date:2023-12-31,type:article
```

### Multiple Values (OR Logic)

Pass a vector to express OR logic within a single filter:

``` r

url <- pro_query(
  entity = "works",
  language = c("en", "de", "fr"), # English OR German OR French
  type = c("article", "preprint") # Article OR Preprint
)
url
# filter=language:en|de|fr,type:article|preprint
```

### Common Filter Patterns

#### Date Ranges

``` r

# Works from 2020 onwards
pro_query(entity = "works", from_publication_date = "2020-01-01")

# Works in a specific year
pro_query(entity = "works", publication_year = 2023)

# Works in a date range
pro_query(
  entity = "works",
  from_publication_date = "2020-01-01",
  to_publication_date = "2020-12-31"
)
```

#### Citation Counts

``` r

# Highly cited works (100+ citations)
pro_query(entity = "works", from_cited_by_count = 100)

# Citation range
pro_query(
  entity = "works",
  from_cited_by_count = 10,
  to_cited_by_count = 100
)
```

#### Open Access

``` r

# Only open access works
pro_query(entity = "works", is_oa = TRUE)

# Specific OA status
pro_query(entity = "works", oa_status = "gold")
pro_query(entity = "works", oa_status = c("gold", "green"))
```

#### By Author or Institution

``` r

# Works by a specific author (use backticks for dots)
pro_query(entity = "works", `author.id` = "A2208157607")

# Works from a specific institution
pro_query(entity = "works", `institutions.id` = "I4200000001")

# Works with a specific affiliation country
pro_query(entity = "works", `institutions.country_code` = "US")
```

#### By Concept/Topic

``` r

# Works about machine learning
pro_query(entity = "works", `concepts.id` = "C119857082")

# Works in multiple fields
pro_query(entity = "works", `concepts.id` = c("C119857082", "C41008148"))
```

### Filter Reference Table

| Filter | Description | Example Values |
|----|----|----|
| `publication_year` | Exact year | 2023 |
| `from_publication_date` | Start date | “2020-01-01” |
| `to_publication_date` | End date | “2023-12-31” |
| `type` | Work type | “article”, “book”, “dataset” |
| `language` | ISO language code | “en”, “de”, “fr” |
| `is_oa` | Open access status | TRUE, FALSE |
| `oa_status` | OA type | “gold”, “green”, “hybrid”, “bronze” |
| `from_cited_by_count` | Minimum citations | 100 |
| `to_cited_by_count` | Maximum citations | 1000 |
| `doi` | Digital Object Identifier | “10.1234/example” |
| `openalex` | OpenAlex ID | “W2741809807” |
| `author.id` | Author OpenAlex ID | “A2208157607” |
| `institutions.id` | Institution ID | “I4200000001” |
| `concepts.id` | Concept ID | “C119857082” |
| `cites` | Works that cite this ID | “W2741809807” |
| `cited_by` | Works cited by this ID | “W2741809807” |

Use
[`opt_filter_names()`](https://openalexpro.github.io/openalexPro/reference/opt_filter_names.md)
to see all available filters.

## Advanced Features

### Grouping (Facets)

Use `group_by` to get aggregate counts instead of individual records:

``` r

url <- pro_query(
  entity = "works",
  search = "artificial intelligence",
  group_by = "publication_year"
)
# Returns counts per year instead of individual works
```

#### Grouping Options

| Group By                      | Description          |
|-------------------------------|----------------------|
| `publication_year`            | Count by year        |
| `type`                        | Count by work type   |
| `oa_status`                   | Count by OA status   |
| `language`                    | Count by language    |
| `is_oa`                       | Count by open access |
| `authorships.institutions.id` | Count by institution |
| `authorships.countries`       | Count by country     |
| `primary_topic.id`            | Count by topic       |

#### Response Structure

A `group_by` query returns a list of groups rather than individual
records. Each group has three fields:

| Field              | Description                                     |
|--------------------|-------------------------------------------------|
| `key`              | The raw value (e.g. `"2023"`, an OpenAlex ID)   |
| `key_display_name` | Human-readable name (e.g. `"2023"`, `"Nature"`) |
| `count`            | Number of entities in this group                |

The API returns at most 200 groups per page.

#### Including Unknown Values

By default, entities with no value for the grouped field are hidden.
Append `:include_unknown` to expose them as a separate group with
`key = "unknown"`:

``` r

# Count works by OA status, including works with unknown status
url <- pro_query(
  entity = "works",
  search = "climate change",
  group_by = "oa_status:include_unknown"
)
```

### Additional Options

The `options` parameter accepts additional query parameters:

``` r

url <- pro_query(
  entity = "works",
  search = "quantum computing",
  options = list(
    per_page = 200, # Results per page (max 200)
    sort = "cited_by_count:desc", # Sort by citations descending
    cursor = "*", # Enable cursor pagination
    sample = 100 # Random sample of 100 works
  )
)
```

#### Options Reference

| Option     | Description              | Values                      |
|------------|--------------------------|-----------------------------|
| `per_page` | Results per page         | 1-200 (default 25)          |
| `sort`     | Sort field and order     | “field:asc” or “field:desc” |
| `cursor`   | Cursor pagination        | “\*” for first page         |
| `sample`   | Random sample size       | Integer                     |
| `seed`     | Random seed for sampling | Integer                     |

#### Sorting Options

``` r

# Sort by publication date (newest first)
pro_query(entity = "works", options = list(sort = "publication_date:desc"))

# Sort by citation count (highest first)
pro_query(entity = "works", options = list(sort = "cited_by_count:desc"))

# Sort by relevance (default for search queries)
pro_query(
  entity = "works",
  search = "climate",
  options = list(sort = "relevance_score:desc")
)
```

#### XPAC — Expansion Pack Works

OpenAlex XPAC (“expansion pack”) adds approximately 190 million
additional works from DataCite and institutional/subject repositories to
the standard ~278 million works, bringing the total to ~470 million.
These works are excluded from API responses by default to avoid
disrupting existing queries; they tend to have lower metadata quality
than the standard corpus, though quality is improving over time.

Enable XPAC by passing `include_xpac = TRUE` via the `options`
parameter:

``` r

# Include XPAC works in results (~470 M total instead of ~278 M)
url <- pro_query(
  entity = "works",
  search = "grey literature",
  options = list(include_xpac = TRUE)
)
```

To retrieve **only** XPAC works (excluding standard works), combine
`include_xpac = TRUE` with the `is_xpac` filter:

``` r

# Query XPAC-only works (must also set include_xpac = TRUE)
url <- pro_query(
  entity = "works",
  is_xpac = TRUE,
  from_publication_date = "2024-01-01",
  options = list(include_xpac = TRUE)
)
```

XPAC works can be combined with any other filter or search mode,
including semantic search:

``` r

# Semantic search across the full XPAC-inclusive corpus
url <- pro_query(
  entity = "works",
  search.semantic = "institutional repository preprint data management",
  options = list(include_xpac = TRUE)
)
```

XPAC work IDs can be passed directly to
[`pro_download_content()`](https://openalexpro.github.io/openalexPro/reference/pro_download_content.md)
— `include_xpac` is a discovery-phase parameter and is not needed at
download time. To find XPAC works that also have downloadable full-text,
combine the filters:

``` r

# Find XPAC works with PDFs, then download them
urls <- pro_query(
  entity = "works",
  has_content.pdf = TRUE,
  is_xpac = TRUE,
  from_publication_date = "2024-01-01",
  options = list(include_xpac = TRUE)
)
# After fetching and extracting IDs from the metadata:
# result <- pro_download_content(ids = xpac_ids, format = "pdf")
```

See the [OpenAlex XPAC
documentation](https://docs.openalex.org/how-to-use-the-api/xpac) for
more details.

## Automatic Chunking

When querying with large lists of DOIs or IDs,
[`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)
automatically splits the request into chunks to avoid API URL length
limits (max ~4094 characters).

### Chunking Overview

``` mermaid
flowchart TD
    Input[Input: 150 DOIs] --> Check{Length > chunk_limit?}
    Check -->|Yes| Split[Split into chunks of 50]
    Check -->|No| SingleURL[Return single URL]

    Split --> Chunk1[Chunk 1: DOIs 1-50]
    Split --> Chunk2[Chunk 2: DOIs 51-100]
    Split --> Chunk3[Chunk 3: DOIs 101-150]

    Chunk1 --> URL1[URL 1]
    Chunk2 --> URL2[URL 2]
    Chunk3 --> URL3[URL 3]

    URL1 --> Output[Named list:<br/>chunk_1, chunk_2, chunk_3]
    URL2 --> Output
    URL3 --> Output

    SingleURL --> SingleOutput[Single URL string]

    style Input fill:#e1f5e1
    style Output fill:#cce5ff
    style SingleOutput fill:#cce5ff
    style Split fill:#fff3cd
```

### Chunkable Filters

The following filters trigger automatic chunking when they exceed
`chunk_limit`:

| Filter         | Description                  |
|----------------|------------------------------|
| `openalex`     | OpenAlex IDs                 |
| `ids.openalex` | OpenAlex IDs (explicit)      |
| `doi`          | DOIs                         |
| `cites`        | IDs of works that cite these |
| `cited_by`     | IDs of works cited by these  |

### Chunking Examples

#### Basic Chunking

``` r

# Create a list of 120 DOIs
dois <- paste0("10.1234/example", 1:120)

# This returns a named list of URLs
urls <- pro_query(
  entity = "works",
  doi = dois,
  chunk_limit = 50 # Default
)

# Check the result
length(urls) # 3 chunks (50 + 50 + 20)
names(urls) # "chunk_1", "chunk_2", "chunk_3"
class(urls) # "list"
```

#### Custom Chunk Size

``` r

urls <- pro_query(
  entity = "works",
  doi = dois,
  chunk_limit = 100 # Larger chunks
)

length(urls) # 2 chunks (100 + 20)
```

#### Multiple Chunkable Filters

When multiple chunkable filters exceed the limit, chunking creates a
cross-product:

``` r

# Both DOI and cites will be chunked
urls <- pro_query(
  entity = "works",
  doi = paste0("10.1234/example", 1:75), # 75 DOIs → 2 chunks
  cites = paste0("W", 1000:1089) # 90 IDs → 2 chunks
)

# Result: 2 × 2 = 4 total URL batches
length(urls) # 4
names(urls) # "chunk_1", "chunk_2", "chunk_3", "chunk_4"
```

``` mermaid
flowchart TD
    subgraph Input[Input Filters]
        DOIs[75 DOIs]
        Cites[90 Cites IDs]
    end

    subgraph DOIChunks[DOI Chunks]
        D1[DOIs 1-50]
        D2[DOIs 51-75]
    end

    subgraph CitesChunks[Cites Chunks]
        C1[Cites 1-50]
        C2[Cites 51-90]
    end

    subgraph Output[Cross Product: 4 URLs]
        URL1["chunk_1: D1 × C1"]
        URL2["chunk_2: D1 × C2"]
        URL3["chunk_3: D2 × C1"]
        URL4["chunk_4: D2 × C2"]
    end

    DOIs --> D1
    DOIs --> D2
    Cites --> C1
    Cites --> C2

    D1 --> URL1
    D1 --> URL2
    D2 --> URL3
    D2 --> URL4
    C1 --> URL1
    C1 --> URL3
    C2 --> URL2
    C2 --> URL4

    style Input fill:#e1f5e1
    style Output fill:#cce5ff
```

#### Multiple IDs Parameter

When passing multiple IDs to the `id` parameter, they are automatically
moved to `ids.openalex` filter:

``` r

# Multiple IDs are converted to filter
urls <- pro_query(
  entity = "works",
  id = c("W2741809807", "W2100837269", "W1234567890")
)
# Equivalent to: ids.openalex = c("W2741809807", ...)
```

## Supported Entities

### Works

Scholarly documents including articles, books, datasets, and more:

``` r

pro_query(entity = "works", search = "CRISPR gene editing")
pro_query(
  entity = "works",
  type = "dataset",
  from_publication_date = "2023-01-01"
)
```

### Authors

Researchers and their metadata:

``` r

pro_query(entity = "authors", search = "Marie Curie")
pro_query(entity = "authors", `last_known_institution.id` = "I4200000001")
```

### Institutions

Universities, research organizations, companies:

``` r

pro_query(entity = "institutions", search = "MIT")
pro_query(entity = "institutions", type = "education", country_code = "US")
```

### Venues

Journals, repositories, conferences:

``` r

pro_query(entity = "venues", search = "Nature")
pro_query(entity = "venues", is_oa = TRUE, type = "journal")
```

### Concepts

Topics and fields of study:

``` r

pro_query(entity = "concepts", search = "machine learning")
pro_query(entity = "concepts", level = 0) # Top-level concepts only
```

### Publishers

Organizations that publish venues:

``` r

pro_query(entity = "publishers", search = "Springer")
pro_query(entity = "publishers", country_codes = "US")
```

### Funders

Organizations that fund research:

``` r

pro_query(entity = "funders", search = "NSF")
pro_query(entity = "funders", country_code = "US")
```

## Validation System

[`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)
validates all inputs to catch errors early and provide helpful
suggestions.

### Validation Flow

``` mermaid
flowchart TD
    Start([Input parameters]) --> ValidateEntity{Valid entity?}

    ValidateEntity -->|No| EntityError["Error: 'arg' should be<br/>one of 'works', 'authors'..."]
    ValidateEntity -->|Yes| GatherFilters[Gather filters from ...]

    GatherFilters --> ValidateFilters{Valid filter names?}

    ValidateFilters -->|No| FilterError[Build error with<br/>fuzzy suggestions]
    ValidateFilters -->|Yes| ValidateSelect{Valid select fields?}

    ValidateSelect -->|No| SelectError[Build error with<br/>fuzzy suggestions]
    ValidateSelect -->|Yes| Continue([Continue to URL building])

    FilterError --> ShowFilter["Error: Invalid filter name(s): xyz<br/>Did you mean: xyz → abc?"]
    SelectError --> ShowSelect["Error: Invalid select field(s): id<br/>Did you mean: id → ids?"]

    style Start fill:#e1f5e1
    style Continue fill:#e1f5e1
    style EntityError fill:#f8d7da
    style ShowFilter fill:#f8d7da
    style ShowSelect fill:#f8d7da
    style ValidateFilters fill:#fff3cd
    style ValidateSelect fill:#fff3cd
```

### Filter Validation

Filter names are validated against
[`opt_filter_names()`](https://openalexpro.github.io/openalexPro/reference/opt_filter_names.md):

``` r

# This will error with suggestions
try(
  pro_query(
    entity = "works",
    publiction_year = 2023 # Typo: should be "publication_year"
  )
)
# Error: Invalid filter name(s): publiction_year.
# Did you mean: publiction_year → publication_year?
# Valid filter names are defined in `opt_filter_names()`.
```

### Select Field Validation

Select fields are validated against
[`opt_select_fields()`](https://openalexpro.github.io/openalexPro/reference/opt_select_fields.md):

``` r

# This will error with suggestions
try(
  pro_query(
    entity = "works",
    select = c("id", "titel") # "id" should be "ids", "titel" should be "title"
  )
)
# Error: Invalid select field(s): id, titel.
# Did you mean: id → ids, titel → title?
# Valid select fields are defined in `opt_select_fields()`.
```

### Entity Validation

Entity type is validated using
[`match.arg()`](https://rdrr.io/r/base/match.arg.html):

``` r

try(pro_query(entity = "paper"))
# Error: 'arg' should be one of "works", "authors", "venues",
#        "institutions", "concepts", "publishers", "funders"
```

## Function Architecture

### High-Level Flow

``` mermaid
flowchart TD
    Start([pro_query called]) --> ValidateEntity[Validate entity type<br/>using match.arg]
    ValidateEntity --> GatherFilters[Gather filters from ...<br/>into named list]
    GatherFilters --> CheckMultipleID{Multiple IDs<br/>in id param?}

    CheckMultipleID -->|Yes| MoveToFilter[Move IDs to<br/>ids.openalex filter]
    CheckMultipleID -->|No| ValidateInputs[Validate filters<br/>and select fields]
    MoveToFilter --> ValidateInputs

    ValidateInputs --> CheckChunking{Filters contain<br/>chunkable fields<br/>> chunk_limit?}

    CheckChunking -->|No| SingleBatch[Single batch:<br/>filter_batches = list<br/>containing one filter]
    CheckChunking -->|Yes| ChunkLoop[Split large filters<br/>into multiple chunks]

    ChunkLoop --> ProcessTargets[For each chunk target:<br/>openalex, doi, cites, cited_by]
    ProcessTargets --> SplitValues[Split values into<br/>groups of chunk_limit]
    SplitValues --> CreateBatches[Create cross-product<br/>of all chunks]

    SingleBatch --> BuildURLs
    CreateBatches --> BuildURLs[Build URLs for<br/>each batch]

    BuildURLs --> ForEachBatch[For each batch:<br/>1. .oa_build_filter<br/>2. Build select string<br/>3. Assemble query params<br/>4. Create httr2 request<br/>5. Extract URL]

    ForEachBatch --> CheckCount{Multiple<br/>batches?}

    CheckCount -->|Yes| ReturnList[Return named list:<br/>chunk_1, chunk_2, ...]
    CheckCount -->|No| ReturnSingle[Return single<br/>URL string]

    ReturnList --> End([Return])
    ReturnSingle --> End

    style Start fill:#e1f5e1
    style End fill:#e1f5e1
    style ValidateInputs fill:#fff3cd
    style ChunkLoop fill:#cce5ff
    style BuildURLs fill:#f8d7da
```

### URL Building Process

``` mermaid
flowchart TD
    subgraph Inputs[Input Components]
        Entity[entity = "works"]
        ID[id = NULL or single ID]
        Search[search = "climate"]
        Select[select = c&#40;"ids", "title"&#41;]
        GroupBy[group_by = "year"]
        Options[options = list<br/>per_page = 200]
        Filters[... filters]
    end

    subgraph Building[URL Building]
        Base["httr2::request(endpoint)"]
        Path["req_url_path_append(entity)"]
        PathID["req_url_path_append(id)"]
        FilterStr[".oa_build_filter(filters)"]
        SelectStr["paste(select, collapse=',')"]
        Query["req_url_query(...)"]
    end

    subgraph Output[Final URL]
        URL["https://api.openalex.org/works<br/>?filter=type:article<br/>&search=climate<br/>&select=ids,title"]
    end

    Entity --> Base
    Base --> Path
    ID -->|if single| PathID
    Path --> PathID
    PathID --> FilterStr

    Filters --> FilterStr
    Select --> SelectStr
    FilterStr --> Query
    SelectStr --> Query
    Search --> Query
    GroupBy --> Query
    Options --> Query

    Query --> URL

    style Inputs fill:#e1f5e1
    style Building fill:#cce5ff
    style Output fill:#fff3cd
```

### Chunking Algorithm

The chunking algorithm handles multiple chunkable filters by creating
batches:

``` mermaid
flowchart TD
    Start([Start with filter_batches<br/>= list containing<br/>original filter]) --> IdentifyTargets[Identify chunk targets<br/>in current filters:<br/>openalex, doi, cites, cited_by]

    IdentifyTargets --> LoopTargets{For each<br/>chunk target key}

    LoopTargets --> InitNewBatches[new_batches = empty list]
    InitNewBatches --> LoopBatches{For each batch<br/>in filter_batches}

    LoopBatches --> GetValues[Get values for<br/>this target key]
    GetValues --> RemoveNA[Remove NA values]

    RemoveNA --> CheckSize{length > chunk_limit?}

    CheckSize -->|Yes| Split[split values into<br/>groups of chunk_limit]
    Split --> CreateNewBatches[For each chunk:<br/>create new batch with<br/>chunked values]
    CreateNewBatches --> AddToNew[Append to new_batches]

    CheckSize -->|No| Keep[Keep batch unchanged]
    Keep --> AddToNew

    AddToNew --> MoreBatches{More batches<br/>to process?}
    MoreBatches -->|Yes| LoopBatches
    MoreBatches -->|No| UpdateBatches[filter_batches = new_batches]

    UpdateBatches --> MoreTargets{More target keys<br/>to process?}
    MoreTargets -->|Yes| LoopTargets
    MoreTargets -->|No| Return([Return filter_batches])

    style Start fill:#e1f5e1
    style Return fill:#e1f5e1
    style CheckSize fill:#fff3cd
    style Split fill:#f8d7da
    style LoopTargets fill:#cce5ff
```

## Internal Helper Functions

The function uses several internal helpers for clean, maintainable code.

### `.is_empty(x)`

Checks if an object is NULL or has zero length:

``` r

.is_empty(NULL) # TRUE
.is_empty(character()) # TRUE
.is_empty(list()) # TRUE
.is_empty("value") # FALSE
.is_empty(c(1, 2, 3)) # FALSE
```

**Implementation:**

``` r

.is_empty <- function(x) {
  is.null(x) || !length(x)
}
```

### `.oa_collapse(x)`

Collapses vectors into pipe-separated strings for the OpenAlex API:

``` r

.oa_collapse(c("en", "de", "fr")) # "en|de|fr"
.oa_collapse("single") # "single"
.oa_collapse(c(TRUE, FALSE)) # "true|false"
.oa_collapse(c("a", NA, "b")) # "a|b" (NA removed)
.oa_collapse(NULL) # character(0)
```

**Flow:**

``` mermaid
flowchart TD
    Input[Input vector] --> CheckNull{NULL?}
    CheckNull -->|Yes| ReturnEmpty[Return character0]
    CheckNull -->|No| RemoveNA[Remove NA values]

    RemoveNA --> CheckEmpty{Empty after<br/>NA removal?}
    CheckEmpty -->|Yes| ReturnEmpty

    CheckEmpty -->|No| CheckLogical{Logical vector?}
    CheckLogical -->|Yes| ConvertLogical[Convert to<br/>"true"/"false"]
    CheckLogical -->|No| CheckLength{Length == 1?}

    ConvertLogical --> CheckLength
    CheckLength -->|Yes| ReturnSingle[Return as character]
    CheckLength -->|No| Collapse[paste with "|"]

    Collapse --> ReturnCollapsed[Return collapsed string]

    style Input fill:#e1f5e1
    style ReturnEmpty fill:#f8d7da
    style ReturnSingle fill:#cce5ff
    style ReturnCollapsed fill:#cce5ff
```

### `.oa_build_filter(fl)`

Constructs the filter query string from a named list:

``` r

filters <- list(
  from_publication_date = "2020-01-01",
  language = c("en", "de"),
  type = "article"
)
.oa_build_filter(filters)
# "from_publication_date:2020-01-01,language:en|de,type:article"

# Empty/NULL handling
.oa_build_filter(NULL) # NULL
.oa_build_filter(list()) # NULL
.oa_build_filter(list(a = NA)) # NULL (all-NA entries dropped)
```

**Flow:**

``` mermaid
flowchart TD
    Input[Named list of filters] --> CheckEmpty1{Empty or NULL?}
    CheckEmpty1 -->|Yes| ReturnNull1[Return NULL]

    CheckEmpty1 -->|No| FilterEmpty[Filter out empty<br/>and all-NA entries]
    FilterEmpty --> CheckEmpty2{Empty after<br/>filtering?}
    CheckEmpty2 -->|Yes| ReturnNull2[Return NULL]

    CheckEmpty2 -->|No| MapFilters[For each filter:<br/>collapse values with |<br/>create "key:value"]
    MapFilters --> JoinFilters[Join with commas]
    JoinFilters --> ReturnString[Return filter string]

    style Input fill:#e1f5e1
    style ReturnNull1 fill:#f8d7da
    style ReturnNull2 fill:#f8d7da
    style ReturnString fill:#cce5ff
```

### `.fuzzy_suggest(bad, allowed, max_dist)`

Provides spelling suggestions for invalid field names using Levenshtein
edit distance:

``` r

.fuzzy_suggest("titel", c("title", "author", "year"))
# "title" (edit distance 1)

.fuzzy_suggest("publiction_year", opt_filter_names())
# "publication_year" (edit distance 1)

.fuzzy_suggest("xyz", c("title", "author"))
# NA (no match within max_dist of 3)
```

**Algorithm:** 1. Calculate edit distance from `bad` to each `allowed`
value 2. Find minimum distance 3. Return suggestion if distance ≤
`max_dist` (default 3) 4. Return `NA` if no close match found

### `.validate_select(select)` and `.validate_filter(fl)`

Validate field and filter names against allowed values:

``` mermaid
flowchart TD
    Input[Input names] --> GetAllowed[Get allowed values<br/>from opt_* function]
    GetAllowed --> FindBad[Find names not<br/>in allowed set]

    FindBad --> CheckBad{Any invalid<br/>names?}
    CheckBad -->|No| ReturnTrue[Return TRUE invisibly]

    CheckBad -->|Yes| BuildError[.build_validation_error:<br/>1. Get fuzzy suggestions<br/>2. Format error message<br/>3. Include "Did you mean?"]
    BuildError --> StopError[stop with error message]

    style Input fill:#e1f5e1
    style ReturnTrue fill:#cce5ff
    style StopError fill:#f8d7da
```

### `.build_validation_error(bad, allowed, field_type, helper_fn_name)`

Constructs helpful error messages with fuzzy suggestions:

``` r

.build_validation_error(
  bad = c("id", "titel"),
  allowed = opt_select_fields(),
  field_type = "select field(s)",
  helper_fn_name = "opt_select_fields()"
)
# "Invalid select field(s): id, titel.
#  Did you mean: id → ids, titel → title?
#  Valid select field(s) are defined in `opt_select_fields()`."
```

## Error Handling

### Common Errors and Solutions

#### Invalid Entity

``` r

try(pro_query(entity = "paper"))
# Error: 'arg' should be one of "works", "authors", "venues",
#        "institutions", "concepts", "publishers", "funders"
```

**Solution:** Use a valid entity name.

#### Invalid Filter Name

``` r

try(pro_query(entity = "works", invalid_filter = "value"))
# Error: Invalid filter name(s): invalid_filter.
# Valid filter names are defined in `opt_filter_names()`.
```

**Solution:** Check
[`opt_filter_names()`](https://openalexpro.github.io/openalexPro/reference/opt_filter_names.md)
for valid filter names.

#### Invalid Select Field

``` r

try(pro_query(entity = "works", select = c("id", "titel")))
# Error: Invalid select field(s): id, titel.
# Did you mean: id → ids, titel → title?
# Valid select fields are defined in `opt_select_fields()`.
```

**Solution:** Use suggested corrections or check
[`opt_select_fields()`](https://openalexpro.github.io/openalexPro/reference/opt_select_fields.md).

#### URL Too Long

When a query URL exceeds ~4094 characters, the API returns an error.
[`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)
prevents this through automatic chunking, but if you manually construct
very long URLs:

``` r

# This would fail at the API level
very_long_url <- pro_query(
  entity = "works",
  doi = paste0("10.1234/", 1:1000),
  chunk_limit = 1000 # Disabling chunking
)
# URL too long → API error
```

**Solution:** Use appropriate `chunk_limit` (default 50 works well).

## Best Practices

### 1. Always Use Field Selection

Reduce response size and improve performance:

``` r

# Good: Only request needed fields
pro_query(
  entity = "works",
  search = "climate",
  select = c("ids", "title", "publication_year", "cited_by_count")
)

# Avoid: Requesting all fields (large responses)
pro_query(entity = "works", search = "climate")
```

### 2. Use Date Filters for Large Queries

Narrow down results to manageable sizes:

``` r

# Good: Filtered by date
pro_query(
  entity = "works",
  search = "machine learning",
  from_publication_date = "2023-01-01"
)

# Risky: Potentially millions of results
pro_query(entity = "works", search = "machine learning")
```

### 3. Check Counts Before Downloading

Use
[`pro_count()`](https://openalexpro.github.io/openalexPro/reference/pro_count.md)
to check query size:

``` r

url <- pro_query(entity = "works", search = "CRISPR")
count <- pro_count(url)
count$count
# [1] 234567  # Consider adding filters if too large
```

### 4. Leverage Automatic Chunking

Let
[`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)
handle large ID lists:

``` r

# Good: Automatic chunking
urls <- pro_query(entity = "works", doi = large_doi_vector)
# Returns list of manageable URLs

# Then process with pro_request()
pro_request(query_url = urls, output = "data/json")
```

### 5. Validate Early

Check your parameters before long-running downloads:

``` r

# Check available filters
head(opt_filter_names(), 20)

# Check available select fields
opt_select_fields()

# Test query with small sample
test_url <- pro_query(
  entity = "works",
  search = "test",
  options = list(per_page = 5)
)
```

## Common Use Cases

### Finding Recent Publications in a Field

``` r

url <- pro_query(
  entity = "works",
  search = "CRISPR gene therapy",
  from_publication_date = "2023-01-01",
  type = "article",
  is_oa = TRUE,
  select = c(
    "ids",
    "title",
    "publication_date",
    "authorships",
    "cited_by_count"
  ),
  options = list(
    per_page = 200,
    sort = "publication_date:desc"
  )
)
```

### Analyzing Highly Cited Works

``` r

url <- pro_query(
  entity = "works",
  from_cited_by_count = 1000,
  from_publication_date = "2020-01-01",
  type = "article",
  select = c(
    "ids",
    "title",
    "cited_by_count",
    "publication_year",
    "authorships"
  ),
  options = list(
    sort = "cited_by_count:desc",
    per_page = 200
  )
)
```

### Author Publication List

``` r

url <- pro_query(
  entity = "works",
  `author.id` = "A2208157607",
  select = c("ids", "title", "publication_year", "type", "cited_by_count"),
  options = list(sort = "publication_date:desc")
)
```

### Institution Research Output

``` r

url <- pro_query(
  entity = "works",
  `institutions.id` = "I4200000001",
  from_publication_date = "2020-01-01",
  type = "article",
  select = c("ids", "title", "authorships", "publication_year", "concepts")
)
```

### Bulk DOI Lookup

``` r

# Read DOIs from file
dois <- readLines("my_dois.txt")

# Query with automatic chunking
urls <- pro_query(
  entity = "works",
  doi = dois,
  select = c("ids", "title", "cited_by_count", "abstract_inverted_index")
)

# Download all chunks
pro_request(query_url = urls, output = "data/json")
```

### Citation Network Analysis

``` r

# Find works that cite a specific paper
url_citing <- pro_query(
  entity = "works",
  cites = "W2741809807",
  select = c("ids", "title", "publication_year")
)

# Find works cited by a specific paper
url_cited <- pro_query(
  entity = "works",
  cited_by = "W2741809807",
  select = c("ids", "title", "publication_year")
)
```

### Publication Year Distribution

``` r

url <- pro_query(
  entity = "works",
  search = "artificial intelligence",
  from_publication_date = "2000-01-01",
  group_by = "publication_year"
)
# Returns counts per year for visualization
```

## Authentication

OpenAlex offers limited API access without credentials. Free API keys
with substantially higher rate limits can be obtained from the [OpenAlex
website](https://openalex.org). Premium API access with even higher
limits can also be purchased.

`openalexPro` uses environment variables for credentials (recommended):

``` r

# Set credentials (typically in your .Renviron file)
Sys.setenv(openalexPro.apikey = "your-api-key-here")

# Validate your credentials
pro_validate_credentials()
```

Credentials are used by API-calling functions
([`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md),
[`pro_count()`](https://openalexpro.github.io/openalexPro/reference/pro_count.md),
[`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md),
[`pro_download_content()`](https://openalexpro.github.io/openalexPro/reference/pro_download_content.md))
and are optional. If `api_key` is `NULL` or `""`, those functions call
OpenAlex without authentication.
[`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)
itself only builds URLs and does not require credentials.

## Integration with openalexPro Workflow

[`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)
is the first step in the typical `openalexPro` data pipeline:

``` mermaid
flowchart LR
    subgraph Step1[Step 1: Query]
        PQ[pro_query]
    end

    subgraph Step2[Step 2: Download]
        PR[pro_request]
    end

    subgraph Step3[Step 3: Transform]
        PRJL[pro_request_jsonl]
    end

    subgraph Step4[Step 4: Convert]
        PRJLP[pro_request_jsonl_parquet]
    end

    subgraph Step5[Step 5: Analyze]
        DB[(DuckDB)]
    end

    PQ -->|URL/URLs| PR
    PR -->|JSON files| PRJL
    PRJL -->|JSONL files| PRJLP
    PRJLP -->|Parquet dataset| DB

    style Step1 fill:#e1f5e1
    style Step2 fill:#cce5ff
    style Step3 fill:#fff3cd
    style Step4 fill:#f8d7da
    style Step5 fill:#e1f5e1
```

### Complete Example

``` r

library(openalexPro)

# Step 1: Build query
urls <- pro_query(
  entity = "works",
  search = "machine learning healthcare",
  from_publication_date = "2020-01-01",
  type = "article",
  select = c("ids", "title", "abstract", "publication_year", "authorships")
)

# Step 2: Retrieve data (with progress bar)
pro_request(
  query_url = urls,
  output = "data/json",
  pages = 10000,
  progress = TRUE,
  workers = 1
)

# Step 3: Convert to JSONL (with parallelization)
pro_request_jsonl(
  input_json = "data/json",
  output = "data/jsonl",
  progress = TRUE,
  workers = 4
)

# Step 4: Convert to Parquet (with schema harmonization)
pro_request_jsonl_parquet(
  input_jsonl = "data/jsonl",
  output = "data/parquet",
  progress = TRUE,
  sample_size = 1000
)

# Step 5: Query with DuckDB
library(duckdb)
con <- dbConnect(duckdb())
results <- dbGetQuery(
  con,
  "
  SELECT title, publication_year, cited_by_count
  FROM read_parquet('data/parquet/**/*.parquet')
  ORDER BY cited_by_count DESC
  LIMIT 10
"
)
dbDisconnect(con)
```

## See Also

- [`opt_filter_names()`](https://openalexpro.github.io/openalexPro/reference/opt_filter_names.md) -
  List available filter names
- [`opt_select_fields()`](https://openalexpro.github.io/openalexPro/reference/opt_select_fields.md) -
  List available select fields
- [`pro_validate_credentials()`](https://openalexpro.github.io/openalexPro/reference/pro_validate_credentials.md) -
  Validate API credentials (optional helper)
- [`pro_count()`](https://openalexpro.github.io/openalexPro/reference/pro_count.md) -
  Get count of results without downloading
- [`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md) -
  Execute API requests and save results
- `pro_request_jsonl()` - Convert JSON to JSONL format
- [`pro_request_jsonl_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl_parquet.md) -
  Convert JSONL to Parquet format (with schema harmonization)

## References

- [OpenAlex API Documentation](https://docs.openalex.org/)
- [OpenAlex
  Filters](https://docs.openalex.org/how-to-use-the-api/get-lists-of-entities/filter-entity-lists)
- [OpenAlex Select
  Fields](https://docs.openalex.org/how-to-use-the-api/get-lists-of-entities/select-fields)
- [OpenAlex Entity
  Types](https://docs.openalex.org/api-entities/entities-overview)
- [OpenAlex Rate
  Limits](https://docs.openalex.org/how-to-use-the-api/rate-limits-and-authentication)
