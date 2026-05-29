# Quick Start Guide

## Overview

`openalexPro` makes it easy to download and analyze large datasets from
[OpenAlex](https://openalex.org), a free and open catalog of the world’s
scholarly research.

``` mermaid
flowchart LR
    subgraph OpenAlex[OpenAlex API]
        API[(250M+ Works<br/>Authors, Institutions<br/>Journals, Concepts)]
    end

    subgraph openalexPro[openalexPro]
        Query[pro_query]
        Fetch[pro_fetch]
    end

    subgraph Local[Your Computer]
        Parquet[(Parquet Dataset)]
        DuckDB[DuckDB Analysis]
    end

    API --> Query
    Query --> Fetch
    Fetch --> Parquet
    %% Parquet --> DuckDB

    style OpenAlex fill:#e1f5e1
    style openalexPro fill:#cce5ff
    style Local fill:#fff3cd
```

## Installation

``` r

# Install stable version from r-universe (recommended)
install.packages(
  "openalexPro",
  repos = c("https://rkrug.r-universe.dev", "https://cloud.r-project.org")
)

# Or install development version from GitHub
# pak::pak("rkrug/openalexPro@dev")
```

## Setup Credentials

OpenAlex provides free API keys with higher rate limits. `openalexPro`
can run without a key, but for anything beyond very small tests you
should configure `openalexPro.apikey`. Get a key at
[openalex.org](https://openalex.org).

``` r

# Add to your .Renviron file (recommended)
# Run: usethis::edit_r_environ()
# Then add these lines:
#   openalexPro.apikey=your-api-key

# Or set temporarily in your session:
Sys.setenv(openalexPro.apikey = "your-api-key")

# Verify credentials (TRUE if key works, FALSE if missing/invalid)
library(openalexPro)
pro_validate_credentials()

# Check your current rate limit usage and remaining budget (key required)
pro_rate_limit_status()
```

## Quick Start: 3 Steps to Data

### Step 1: Build Your Query

``` r

library(openalexPro)

# Search for works about climate change in 2023
url <- pro_query(
  entity = "works",
  search = "climate change adaptation",
  from_publication_date = "2023-01-01",
  to_publication_date = "2023-12-31",
  type = "article",
  select = c("ids", "title", "publication_year", "cited_by_count", "authorships")
)
```

### Step 2: Check the Size (Optional but Recommended)

``` r

# See how many results before downloading
count <- pro_count(url)
count$count
# [1] 12543
```

### Step 3: Fetch Everything with `pro_fetch()`

``` r

# Download, transform, and convert to Parquet in one step!
parquet_path <- pro_fetch(
 query_url = url,
 project_folder = "my_climate_data",
 progress = TRUE
)
```

That’s it! Your data is now in `my_climate_data/parquet/`.

``` mermaid
flowchart TD
    subgraph pro_fetch["pro_fetch() does everything"]
        direction TB
        A[Download from API] --> B[Convert to JSONL]
        B --> C[Convert to Parquet]
    end

    subgraph Output[Project Folder Structure]
        JSON[json/]
        JSONL[jsonl/]
        PARQUET[parquet/]
    end

    pro_fetch --> Output

    style pro_fetch fill:#cce5ff
    style Output fill:#e1f5e1
```

## Analysis Example: Analyse with DuckDB

``` r

library(duckdb)
library(DBI)

# Connect and query
con <- dbConnect(duckdb())

# Top 10 most cited papers
results <- dbGetQuery(con, "
  SELECT title, publication_year, cited_by_count
  FROM read_parquet('my_climate_data/parquet/**/*.parquet')
  ORDER BY cited_by_count DESC
  LIMIT 10
")

print(results)

dbDisconnect(con)
```

## More Examples

### Search by Author

``` r

# Find works by a specific author
url <- pro_query(
  entity = "works",
  `author.id` = "A2208157607",
  select = c("ids", "title", "publication_year", "cited_by_count")
)

pro_fetch(query_url = url, project_folder = "author_works")
```

### Search by Institution

``` r

# Find recent articles from MIT
url <- pro_query(
  entity = "works",
  `institutions.id` = "I63966007",
  from_publication_date = "2023-01-01",
  type = "article",
  select = c("ids", "title", "publication_year", "authorships")
)

pro_fetch(query_url = url, project_folder = "mit_articles")
```

### Bulk DOI Lookup

``` r

# Look up a list of DOIs
dois <- c(
  "10.1038/nature12373",
  "10.1126/science.1259855",
  "10.1073/pnas.1900194116"
)

url <- pro_query(
  entity = "works",
  doi = dois,
  select = c("ids", "title", "cited_by_count", "publication_year")
)

pro_fetch(query_url = url, project_folder = "my_dois")
```

### Open Access Articles Only

``` r

url <- pro_query(
  entity = "works",
  search = "machine learning healthcare",
  is_oa = TRUE,
  oa_status = c("gold", "green"),
  from_publication_date = "2022-01-01",
  select = c("ids", "title", "oa_status", "cited_by_count")
)

pro_fetch(query_url = url, project_folder = "ml_healthcare_oa")
```

## What’s in the Parquet Dataset?

The Parquet files contain your selected fields plus some extras added
during processing:

| Field | Description |
|----|----|
| Your selected fields | Whatever you specified in `select` |
| `abstract` | Reconstructed from `abstract_inverted_index` |
| `citation` | Generated citation string (e.g., “Smith et al. (2023)”) |
| `page` | Data provenance tracking |

## Next Steps

For more control over the download process, see the **[Workflow
Guide](https://openalexpro.github.io/openalexPro/articles/Workflow.md)**
which covers:

- Using
  [`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md),
  `pro_request_jsonl()`, and
  [`pro_request_jsonl_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl_parquet.md)
  separately
- Parallel processing with multiple workers
- Handling very large datasets
- Intermediate file management
- Advanced DuckDB queries

For detailed technical documentation, see:

- **[pro_query() Technical
  Documentation](https://openalexpro.github.io/openalexPro/articles/pro_query.md)** -
  Query building, filtering, chunking
- **[pro_request() Technical
  Documentation](https://openalexpro.github.io/openalexPro/articles/pro_request.md)** -
  Download pipeline, error handling, progress tracking

## Function Reference

| Function | Purpose |
|----|----|
| [`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md) | Build OpenAlex API query URLs |
| [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md) | **One-step download + transform + convert** |
| [`pro_count()`](https://openalexpro.github.io/openalexPro/reference/pro_count.md) | Get result count without downloading |
| [`pro_validate_credentials()`](https://openalexpro.github.io/openalexPro/reference/pro_validate_credentials.md) | Test your API credentials |
| [`pro_rate_limit_status()`](https://openalexpro.github.io/openalexPro/reference/pro_rate_limit_status.md) | Check current rate limit usage and remaining budget |
| [`opt_filter_names()`](https://openalexpro.github.io/openalexPro/reference/opt_filter_names.md) | List available filter names |
| [`opt_select_fields()`](https://openalexpro.github.io/openalexPro/reference/opt_select_fields.md) | List available select fields |

## Getting Help

- **GitHub Issues**:
  [github.com/rkrug/openalexPro/issues](https://github.com/rkrug/openalexPro/issues)
- **OpenAlex Documentation**:
  [docs.openalex.org](https://docs.openalex.org)
