# Workflow Guide

## Introduction

The `openalexPro` package enables downloading and processing large
scholarly datasets from [OpenAlex](https://openalex.org). Unlike
`openalexR` which processes everything in memory, `openalexPro` writes
results to disk, enabling analysis of datasets too large to fit in RAM.

Processing uses [DuckDB](https://duckdb.org) for efficient queries
without loading entire datasets into memory.

## Architecture Overview

``` mermaid
flowchart TD
    OA[("OpenAlex<br/>api.openalex.org · content.openalex.org")]
    SNAP[("OpenAlex Snapshot<br/>bulk ndjson.gz")]

    PQ["pro_query()<br/>build URL · validate filters · chunk IDs"]
    PC["pro_count()"]
    PRL["pro_rate_limit_status()<br/>pro_validate_credentials()"]

    AC["api_call()  ·  internal helper<br/>retry · backoff · error handling"]

    subgraph PF["pro_fetch()  —  convenience wrapper"]
        PR["pro_request()<br/>download metadata pages → JSON"]
        PRJ["pro_request_jsonl()<br/>JSON → JSONL<br/>reconstruct abstract · build citation"]
        PRJP["pro_request_jsonl_parquet()<br/>JSONL → partitioned Parquet"]
        PR --> PRJ --> PRJP
    end

    PDC["pro_download_content()<br/>download PDFs / TEI XML"]

    STP["snapshot_to_parquet()"]
    BCI["build_corpus_index()"]
    LBI["lookup_by_id()<br/>snapshot_filter_ids()"]

    OUT[("Parquet dataset<br/>read_corpus() · DuckDB · arrow")]
    FILES[("PDF / TEI XML files<br/>on disk")]

    OA <--> AC
    PQ -->|URL| PR
    PQ -->|URL| PC

    PR -.->|via| AC
    PDC -.->|via| AC
    PRL -.->|via| AC
    PC -.->|via| AC

    PRJP --> OUT
    PDC --> FILES

    SNAP --> STP --> BCI --> LBI --> OUT

    style OA    fill:#e3f2fd,stroke:#1565c0,stroke-width:2px
    style SNAP  fill:#fff3e0,stroke:#e65100,stroke-width:2px
    style OUT   fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style FILES fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px
    style AC    fill:#cce5ff,stroke:#0066cc,stroke-width:2px
```

| Colour | Meaning |
|----|----|
| Blue | OpenAlex online resource |
| Orange | OpenAlex Snapshot (local bulk input) |
| Green | Output data (Parquet dataset, PDF/XML files) |
| Light blue | `api_call()` — internal HTTP helper shared by all API-calling functions |

## Two Approaches

`openalexPro` offers two approaches depending on your needs:

``` mermaid
flowchart TD
    Start([Start]) --> Choice{Need fine<br/>control?}

    Choice -->|No| Simple[Simple Approach:<br/>pro_fetch]
    Choice -->|Yes| Advanced[Advanced Approach:<br/>Individual functions]

    Simple --> Result1[Parquet Dataset]
    Advanced --> Result2[Parquet Dataset]

    style Simple fill:#e1f5e1
    style Advanced fill:#cce5ff
```

| Approach | When to Use |
|----|----|
| **Simple**: [`pro_fetch()`](https://rkrug.github.io/openalexPro/reference/pro_fetch.md) | Quick analysis, standard workflow, getting started |
| **Advanced**: Individual functions | Custom processing from downloaded json, more control, advanced workflows |

## Simple Approach: `pro_fetch()`

For most use cases,
[`pro_fetch()`](https://rkrug.github.io/openalexPro/reference/pro_fetch.md)
handles everything in one call:

``` mermaid
flowchart LR
    subgraph Input
        URL[Query URL]
    end

    subgraph pro_fetch[pro_fetch]
        PR[pro_request<br/>Download JSON]
        PRJ[pro_request_jsonl<br/>Transform]
        PRJP[pro_request_jsonl_parquet<br/>Convert]
        PR --> PRJ --> PRJP
    end

    subgraph Output[Project Folder]
        JSON[json/]
        JSONL[jsonl/]
        PARQUET[parquet/]
    end

    URL --> pro_fetch
    pro_fetch --> Output

    style pro_fetch fill:#cce5ff
    style Output fill:#e1f5e1
```

### Example

``` r

library(openalexPro)

# Build query
url <- pro_query(
  entity = "works",
  search = "climate change adaptation",
  from_publication_date = "2023-01-01",
  type = "article",
  select = c(
    "ids",
    "title",
    "publication_year",
    "cited_by_count",
    "authorships"
  )
)

# Fetch everything in one call
parquet_path <- pro_fetch(
  query_url = url,
  project_folder = "climate_research",
  progress = TRUE
)

# Analyze with DuckDB
library(duckdb)
con <- dbConnect(duckdb())
results <- dbGetQuery(
  con,
  "
  SELECT title, cited_by_count
  FROM read_parquet('climate_research/parquet/**/*.parquet')
  ORDER BY cited_by_count DESC
  LIMIT 10
"
)
dbDisconnect(con)
```

## Advanced Approach: Individual Functions

For more control, use the functions separately:

``` mermaid
flowchart TD
    subgraph Step1[Step 1: Query]
        PQ[pro_query]
        PC[pro_count]
    end

    subgraph Step2[Step 2: Download]
        PR[pro_request]
    end

    subgraph Step3[Step 3: Transform]
        PRJ[pro_request_jsonl]
    end

    subgraph Step4[Step 4: Convert]
        PRJP[pro_request_jsonl_parquet]
    end

    subgraph Step5[Step 5: Analyze]
        DB[(DuckDB)]
    end

    PQ -->|URL| PC
    PC -->|Check size| PR
    PQ -->|URL| PR
    PR -->|JSON files| PRJ
    PRJ -->|JSONL files| PRJP
    PRJP -->|Parquet dataset| DB

    style Step1 fill:#e1f5e1
    style Step2 fill:#cce5ff
    style Step3 fill:#fff3cd
    style Step4 fill:#f8d7da
    style Step5 fill:#e1f5e1
```

### Step 1: Build and Validate Query

``` r

library(openalexPro)

# Build the query URL
url <- pro_query(
  entity = "works",
  search = "CRISPR gene therapy",
  from_publication_date = "2020-01-01",
  type = "article",
  is_oa = TRUE,
  select = c(
    "ids",
    "title",
    "abstract_inverted_index",
    "publication_year",
    "cited_by_count",
    "authorships",
    "concepts"
  )
)

# Check how many results (recommended before large downloads)
count <- pro_count(url)
print(paste("Results:", count$count))
```

### Step 2: Download JSON from API

``` r

# Download with progress bar
pro_request(
  query_url = url,
  output = "data/json",
  pages = 10000, # Max pages (default)
  progress = TRUE, # Show progress bar
  workers = 1 # Parallel workers for chunked queries
)
```

#### Output Structure

    data/json/
    ├── 00_in.progress      # Deleted when complete
    ├── results_page_1.json
    ├── results_page_2.json
    ├── results_page_3.json
    └── ...

### Step 3: Transform to JSONL

``` r

# Convert JSON to JSONL with parallel processing
pro_request_jsonl(
  input_json = "data/json",
  output = "data/jsonl",
  progress = TRUE,
  workers = 4, # Use 4 parallel workers
  delete_input = FALSE # Keep JSON files
)
```

#### What Happens During Transformation

``` mermaid
flowchart LR
    subgraph Input[JSON from OpenAlex]
        IAI[abstract_inverted_index]
        Auth[authorships]
        Other[other fields...]
    end

    subgraph Transform[jq_execute]
        T1[Reconstruct abstract<br/>from inverted index]
        T2[Generate citation string<br/>Smith et al. 2023]
        T3[Add page field<br/>for provenance]
    end

    subgraph Output[JSONL Output]
        Abstract[abstract: full text]
        Citation[citation: string]
        Page[page: identifier]
        OtherOut[other fields...]
    end

    IAI --> T1 --> Abstract
    Auth --> T2 --> Citation
    Other --> T3 --> Page
    Other --> OtherOut

    style Transform fill:#fff3cd
```

### Step 4: Convert to Parquet

``` r

# Convert JSONL to Parquet with schema harmonization
pro_request_jsonl_parquet(
  input_jsonl = "data/jsonl",
  output = "data/parquet",
  progress = TRUE,
  sample_size = 1000, # Records to sample for schema inference
  delete_input = FALSE # Keep JSONL files
)
```

#### Schema Harmonization

Different OpenAlex records can have different field structures. The
function automatically infers a unified schema:

``` mermaid
flowchart TD
    subgraph Input[JSONL Files with Varying Schemas]
        F1["File 1: location = struct"]
        F2["File 2: location = string"]
        F3["File 3: location = null"]
    end

    subgraph Process[Schema Harmonization]
        Sample[Sample records<br/>from all files]
        Infer[Infer unified schema<br/>using DuckDB]
        Apply[Apply schema<br/>to all files]
    end

    subgraph Output[Parquet Dataset]
        Unified["Unified schema<br/>location = struct"]
    end

    F1 --> Sample
    F2 --> Sample
    F3 --> Sample
    Sample --> Infer
    Infer --> Apply
    Apply --> Unified

    style Process fill:#cce5ff
    style Output fill:#e1f5e1
```

### Step 5: Analyze with DuckDB

``` r

library(duckdb)
library(DBI)

con <- dbConnect(duckdb())

# Top cited papers
top_cited <- dbGetQuery(
  con,
  "
  SELECT title, publication_year, cited_by_count
  FROM read_parquet('data/parquet/**/*.parquet')
  WHERE cited_by_count IS NOT NULL
  ORDER BY cited_by_count DESC
  LIMIT 20
"
)

# Papers per year
by_year <- dbGetQuery(
  con,
  "
  SELECT publication_year, COUNT(*) as count
  FROM read_parquet('data/parquet/**/*.parquet')
  GROUP BY publication_year
  ORDER BY publication_year
"
)

# Search abstracts
keyword_search <- dbGetQuery(
  con,
  "
  SELECT title, abstract, cited_by_count
  FROM read_parquet('data/parquet/**/*.parquet')
  WHERE abstract LIKE '%machine learning%'
  ORDER BY cited_by_count DESC
  LIMIT 10
"
)

dbDisconnect(con)
```

## Handling Large Datasets

### Parallel Processing

``` mermaid
flowchart TD
    subgraph Chunked[Chunked Query: 150 DOIs]
        C1[chunk_1: 50 DOIs]
        C2[chunk_2: 50 DOIs]
        C3[chunk_3: 50 DOIs]
    end

    subgraph Workers[4 Parallel Workers]
        W1[Worker 1]
        W2[Worker 2]
        W3[Worker 3]
        W4[Worker 4]
    end

    subgraph Output[Output Folders]
        O1[chunk_1/]
        O2[chunk_2/]
        O3[chunk_3/]
    end

    C1 --> W1
    C2 --> W2
    C3 --> W3
    W1 --> O1
    W2 --> O2
    W3 --> O3

    style Workers fill:#cce5ff
```

``` r

# Large DOI list - automatically chunked
dois <- readLines("my_dois.txt") # 1000+ DOIs

urls <- pro_query(
  entity = "works",
  doi = dois,
  select = c("ids", "title", "cited_by_count")
)

# Parallel download
pro_request(
  query_url = urls,
  output = "data/json",
  workers = 4, # 4 parallel downloads
  progress = TRUE
)

# Parallel JSONL conversion
pro_request_jsonl(
  input_json = "data/json",
  output = "data/jsonl",
  workers = 4, # 4 parallel conversions
  progress = TRUE
)
```

### Managing Disk Space

For very large datasets, delete intermediate files:

``` r

# Delete JSON after JSONL conversion
pro_request_jsonl(
  input_json = "data/json",
  output = "data/jsonl",
  delete_input = TRUE # Remove JSON files
)

# Delete JSONL after Parquet conversion
pro_request_jsonl_parquet(
  input_jsonl = "data/jsonl",
  output = "data/parquet",
  delete_input = TRUE # Remove JSONL files
)
```

### Progress Tracking

All functions create a `00_in.progress` file during processing:

``` mermaid
flowchart LR
    Start([Start]) --> Create[Create<br/>00_in.progress]
    Create --> Process[Processing...]
    Process --> Success{Success?}
    Success -->|Yes| Delete[Delete<br/>00_in.progress]
    Success -->|No| Keep[Keep file<br/>indicates incomplete]

    style Delete fill:#e1f5e1
    style Keep fill:#f8d7da
```

Check if processing completed:

``` r

# Check if download is complete
if (file.exists("data/json/00_in.progress")) {
  message("Download still in progress or was interrupted!")
} else {
  message("Download complete")
}
```

## Workflow Examples

### Example 1: Institution Analysis

Analyze research output from multiple institutions:

``` r

# MIT, Stanford, Harvard
institutions <- c("I63966007", "I97018004", "I136199984")

# Build queries for each
urls <- lapply(institutions, function(inst) {
  pro_query(
    entity = "works",
    `institutions.id` = inst,
    from_publication_date = "2020-01-01",
    type = "article",
    select = c("ids", "title", "publication_year", "cited_by_count", "concepts")
  )
})
names(urls) <- c("MIT", "Stanford", "Harvard")

# Download each
for (name in names(urls)) {
  pro_fetch(
    query_url = urls[[name]],
    project_folder = file.path("institutions", name),
    progress = TRUE
  )
}

# Compare with DuckDB
library(duckdb)
con <- dbConnect(duckdb())

comparison <- dbGetQuery(
  con,
  "
  SELECT
    'MIT' as institution,
    COUNT(*) as papers,
    AVG(cited_by_count) as avg_citations
  FROM read_parquet('institutions/MIT/parquet/**/*.parquet')
  UNION ALL
  SELECT
    'Stanford',
    COUNT(*),
    AVG(cited_by_count)
  FROM read_parquet('institutions/Stanford/parquet/**/*.parquet')
  UNION ALL
  SELECT
    'Harvard',
    COUNT(*),
    AVG(cited_by_count)
  FROM read_parquet('institutions/Harvard/parquet/**/*.parquet')
"
)

dbDisconnect(con)
```

### Example 2: Citation Network

Build a citation network for a set of papers:

``` r

# Start with seed papers
seed_dois <- c(
  "10.1038/nature12373",
  "10.1126/science.1259855"
)

# Get seed papers
seed_url <- pro_query(
  entity = "works",
  doi = seed_dois,
  select = c("ids", "title", "cited_by_count", "referenced_works")
)

pro_fetch(
  query_url = seed_url,
  project_folder = "citation_network/seeds"
)

# Get papers that cite the seeds
for (doi in seed_dois) {
  citing_url <- pro_query(
    entity = "works",
    cites = paste0("https://doi.org/", doi),
    select = c("ids", "title", "publication_year", "cited_by_count")
  )

  pro_fetch(
    query_url = citing_url,
    project_folder = paste0("citation_network/citing_", gsub("/", "_", doi))
  )
}
```

### Example 3: Time Series Analysis

Track research trends over time:

``` r

# Get publication counts by year using group_by
url <- pro_query(
  entity = "works",
  search = "artificial intelligence",
  from_publication_date = "2000-01-01",
  group_by = "publication_year"
)

# For group_by queries, use pro_request directly
pro_request(
  query_url = url,
  output = "ai_trends/json",
  progress = TRUE
)

# The JSON contains aggregated counts, not individual works
```

### Example 4: Concept Co-occurrence

Analyze which concepts appear together:

``` r

url <- pro_query(
  entity = "works",
  search = "climate change",
  from_publication_date = "2023-01-01",
  type = "article",
  select = c("ids", "title", "concepts")
)

pro_fetch(
  query_url = url,
  project_folder = "concept_analysis"
)

# Analyze concept co-occurrence with DuckDB
library(duckdb)
con <- dbConnect(duckdb())

# Unnest concepts and count
concept_counts <- dbGetQuery(
  con,
  "
  WITH unnested AS (
    SELECT
      id,
      unnest(concepts) as concept
    FROM read_parquet('concept_analysis/parquet/**/*.parquet')
  )
  SELECT
    concept.display_name as concept_name,
    concept.level as concept_level,
    COUNT(*) as count
  FROM unnested
  GROUP BY concept.display_name, concept.level
  ORDER BY count DESC
  LIMIT 50
"
)

dbDisconnect(con)
```

### Example 5: Downloading Full-Text Content

OpenAlex provides full-text PDFs (~60 M works) and Grobid TEI XML (~43 M
works) via `content.openalex.org`. Use
[`pro_download_content()`](https://rkrug.github.io/openalexPro/reference/pro_download_content.md)
to retrieve them. Each file costs **\$0.01**.

``` r

# Step 1: find works that have a PDF available
url <- pro_query(
  entity = "works",
  `has_content.pdf` = TRUE,
  `best_oa_location.license` = c("cc-by", "cc-by-sa"),
  from_publication_date = "2023-01-01",
  type = "article",
  select = c("ids", "title", "publication_year")
)

# Step 2: download metadata to get the work IDs
pro_fetch(
  query_url = url,
  project_folder = "oa_works"
)

# Step 3: read IDs from the parquet dataset
library(duckdb)
con <- dbConnect(duckdb())
ids <- dbGetQuery(
  con,
  "SELECT id FROM read_parquet('oa_works/parquet/**/*.parquet')"
)$id
dbDisconnect(con)

# Step 4: download full-text PDFs
results <- pro_download_content(
  ids     = ids,
  output  = "oa_works/pdfs",
  format  = "pdf",
  workers = 4         # parallel downloads
)

# results is a data frame: id | file | status | message
table(results$status)
# ok        not_found  error
# 892       45         3
```

[`pro_download_content()`](https://rkrug.github.io/openalexPro/reference/pro_download_content.md)
never aborts on partial failures — inspect the `status` column to
identify any files that need retrying.

For TEI XML (structured full text parsed by Grobid):

``` r

results_xml <- pro_download_content(
  ids    = ids,
  output = "oa_works/xml",
  format = "grobid-xml"
)
```

## Data Pipeline Summary

``` mermaid
flowchart TD
    subgraph API[OpenAlex API]
        OA[(250M+ Works)]
    end

    subgraph Query[1. Query Building]
        PQ[pro_query]
        PC[pro_count]
        PQ --> PC
    end

    subgraph Download[2. Download]
        PR[pro_request]
        JSON[(JSON Files<br/>~200 records/file)]
    end

    subgraph Transform[3. Transform]
        PRJ[pro_request_jsonl]
        JSONL[(JSONL Files<br/>1 record/line)]
        Abstract[Abstract reconstruction]
        Citation[Citation generation]
    end

    subgraph Convert[4. Convert]
        PRJP[pro_request_jsonl_parquet]
        Schema[Schema harmonization]
        PARQUET[(Parquet Dataset<br/>Columnar, compressed)]
    end

    subgraph Analyze[5. Analyze]
        DUCK[(DuckDB)]
        R[R/tidyverse]
        Python[Python/pandas]
    end

    OA --> PR
    PQ --> PR
    PR --> JSON
    JSON --> PRJ
    PRJ --> Abstract
    PRJ --> Citation
    Abstract --> JSONL
    Citation --> JSONL
    JSONL --> PRJP
    PRJP --> Schema
    Schema --> PARQUET
    PARQUET --> DUCK
    PARQUET --> R
    PARQUET --> Python

    style API fill:#e1f5e1
    style Query fill:#cce5ff
    style Download fill:#fff3cd
    style Transform fill:#f8d7da
    style Convert fill:#e1f5e1
    style Analyze fill:#cce5ff
```

## Function Quick Reference

| Function | Purpose | Key Parameters |
|----|----|----|
| [`pro_query()`](https://rkrug.github.io/openalexPro/reference/pro_query.md) | Build API URL | entity, search, filters, select |
| [`pro_count()`](https://rkrug.github.io/openalexPro/reference/pro_count.md) | Get result count | query_url |
| [`pro_fetch()`](https://rkrug.github.io/openalexPro/reference/pro_fetch.md) | **All-in-one download** | query_url, project_folder |
| [`pro_request()`](https://rkrug.github.io/openalexPro/reference/pro_request.md) | Download JSON | query_url, output, pages, workers |
| `pro_request_jsonl()` | Convert to JSONL | input_json, output, workers |
| [`pro_request_jsonl_parquet()`](https://rkrug.github.io/openalexPro/reference/pro_request_jsonl_parquet.md) | Convert to Parquet | input_jsonl, output, sample_size |
| [`pro_validate_credentials()`](https://rkrug.github.io/openalexPro/reference/pro_validate_credentials.md) | Test credentials (optional helper) | api_key |
| [`pro_rate_limit_status()`](https://rkrug.github.io/openalexPro/reference/pro_rate_limit_status.md) | Check rate limit usage & remaining budget | api_key, verbose |
| [`pro_download_content()`](https://rkrug.github.io/openalexPro/reference/pro_download_content.md) | Download full-text PDFs or TEI XML | ids, output, format, workers |

## See Also

- **[Quick Start
  Guide](https://rkrug.github.io/openalexPro/articles/Quick_Start.md)** -
  Get started in 5 minutes
- **[pro_query()
  Documentation](https://rkrug.github.io/openalexPro/articles/pro_query.md)** -
  Query building details
- **[pro_request()
  Documentation](https://rkrug.github.io/openalexPro/articles/pro_request.md)** -
  Download pipeline details
- **[OpenAlex Documentation](https://docs.openalex.org)** - API
  reference
