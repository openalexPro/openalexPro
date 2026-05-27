# Working with OpenAlex Snapshots

## Introduction

OpenAlex provides complete data snapshots that can be downloaded and
processed locally. This approach offers several advantages over API
queries: - **No rate limits**: Process millions of records without API
restrictions - **Reproducibility**: Work with a fixed point-in-time
dataset - **Speed**: Local queries are significantly faster than API
calls (in many cases, especially what larger result corp\[ora
concerns)\]) - **Offline access**: No internet connection required after
download

This vignette guides you through:

1.  Setting up your environment
2.  Downloading the OpenAlex snapshot
3.  Converting to parquet format
4.  Building indexes for fast lookups
5.  Querying your local corpus

## Prerequisites

### Hardware Requirements

Working with the full OpenAlex snapshot requires significant resources:

| Resource   | Minimum | Recommended |
|------------|---------|-------------|
| Disk space | 2.5 TB  | 3+ TB       |
| RAM        | 16 GB   | 32+ GB      |
| CPU        | 2 cores | 4+ cores    |

The snapshot download is approximately 1.2 TB. The parquet conversion
adds another 100-200 GB depending on compression settings.

### Software Requirements

- **R** (\>= 4.1.2)
- **AWS CLI**: For downloading from S3
- **GNU Make**: For running the Makefile targets
- **openalexPro**: This package
- **openalex-snapshot** binary: Required for
  [`snapshot_to_parquet()`](https://rkrug.github.io/openalexPro/reference/snapshot_to_parquet.md),
  [`build_corpus_index()`](https://rkrug.github.io/openalexPro/reference/build_corpus_index.md),
  and
  [`lookup_by_id()`](https://rkrug.github.io/openalexPro/reference/lookup_by_id.md).
  Download from [GitHub
  releases](https://github.com/rkrug/openalex-snapshot/releases) or
  build with `cargo build --release`. Alternatively, use the pure-R
  `*_R()` variants.

#### Installing AWS CLI

``` bash
# macOS (with Homebrew)
brew install awscli

# Ubuntu/Debian
sudo apt install awscli

# Windows (with winget)
winget install Amazon.AWSCLI
```

Verify installation:

``` bash
aws --version
```

No AWS account is required - the OpenAlex bucket allows anonymous
access.

## Quick Start

The easiest way to get started is using
[`prepare_snapshot()`](https://rkrug.github.io/openalexPro/reference/prepare_snapshot.md):

``` r

library(openalexPro)

# Prepare a directory for your snapshot
prepare_snapshot("/path/to/openalex-data")
```

This creates:

- `Makefile`: Contains all commands for snapshot management
- `snapshot_guide.html`: This documentation

Then navigate to the directory and use Make:

``` bash
cd /path/to/openalex-data

# See available commands and current variable values
make help

# Download snapshot (WARNING: ~1TB, takes hours)
make snapshot

# Convert to parquet format
make parquet

# Build search indexes
make parquet_index
```

## Step-by-Step Guide

### 1. Prepare Your Directory

Choose a location with sufficient disk space:

``` r

library(openalexPro)

# Create and prepare the snapshot directory
snapshot_dir <- "/Volumes/external-drive/openalex"
prepare_snapshot(snapshot_dir)
```

### 2. Download the Snapshot

The OpenAlex snapshot is hosted on Amazon S3 and updated regularly. The
download uses `aws s3 sync` which:

- Downloads only new or changed files
- Resumes interrupted downloads
- Removes files deleted from the source

``` bash
cd /Volumes/external-drive/openalex
make snapshot
```

**Expected time**: 2-12 hours depending on your internet connection.

**Tip**: You can monitor progress in another terminal:

``` bash
watch -n 60 'du -sh openalex-snapshot/*'
```

#### Snapshot Structure

After download, you’ll have:

    openalex-snapshot/
    ├── RELEASE_NOTES.txt
    ├── data/
    │   ├── works/
    │   ├── authors/
    │   ├── institutions/
    │   ├── sources/
    │   ├── publishers/
    │   ├── funders/
    │   ├── topics/
    │   ├── fields/
    │   ├── subfields/
    │   └── domains/
    └── ...

Each entity type contains gzipped JSON files partitioned by update date.

### 3. Convert to Parquet Format

The JSON snapshot is not efficient for analytical queries. Converting to
parquet format provides:

- **Columnar storage**: Read only the columns you need
- **Compression**: Smaller files on disk
- **Fast filtering**: Predicate pushdown for efficient queries
- **Type safety**: Proper data types for each field

``` bash
make parquet MAX_MEMORY_MB=20000 WORKERS=4 PROFILE=balanced
```

This invokes the `openalex-snapshot convert` command which:

1.  **Deletes** the existing parquet directory first (depends on
    `clean_parquet`)
2.  Converts the JSON snapshot to parquet, using the specified worker
    count and memory limit
3.  Supports `PROFILE` values: `safe`, `balanced` (default), `fast`

**NB:** Set `MAX_MEMORY_MB` (memory cap in MB), `WORKERS`, and `PROFILE`
to values that work with your system. Since `parquet` unconditionally
deletes the existing parquet directory, call
[`snapshot_to_parquet()`](https://rkrug.github.io/openalexPro/reference/snapshot_to_parquet.md)
(or
[`snapshot_to_parquet_R()`](https://rkrug.github.io/openalexPro/reference/snapshot_to_parquet_R.md))
directly in R if you want resume behaviour.

**Expected time**: 2-8 hours depending on CPU and disk speed.

#### Parquet Structure

After conversion, each entity directory contains one `.parquet` file per
input `.gz` file:

    parquet/
    ├── works/
    │   ├── part_000.parquet
    │   ├── part_001.parquet
    │   └── ...
    ├── authors/
    ├── institutions/
    └── ...

### 4. Build Search Indexes

For fast ID-based lookups, build indexes:

``` bash
make parquet_index WORKERS=8
```

This creates a single index parquet file for each entity type, enabling
fast lookups by OpenAlex ID:

    parquet/
    ├── works/
    ├── works_id_idx.parquet
    └── ...

The index maps each ID to its physical location (file and row number) in
the corpus, so
[`lookup_by_id()`](https://rkrug.github.io/openalexPro/reference/lookup_by_id.md)
can retrieve specific records without scanning the entire corpus.

**NB:** Indexing is less memory-intensive than parquet conversion and
profits from higher `WORKERS`. To rebuild indexes without touching the
parquet files, use `make clean_index` followed by `make parquet_index`.

## Using Your Local Corpus

### Looking Up Records by ID

``` r

library(openalexPro)

# Look up specific works by OpenAlex ID using the binary wrapper
# Records are written to <project_dir>/snapshot_extract/
lookup_by_id(
  root_dir    = "/Volumes/external-drive/openalex",
  ids         = c("W2741809807", "W2100837269"),
  project_dir = "my_project",
  data_sets   = "works"
)

# Pure-R fallback (no binary required) — returns a data frame
works <- lookup_by_id_R(
  index_file = "/Volumes/external-drive/openalex/parquet/works_id_idx.parquet",
  ids        = c("W2741809807", "W2100837269")
)

# Pure-R fallback: write directly to parquet for millions of IDs
lookup_by_id_R(
  index_file = "/Volumes/external-drive/openalex/parquet/works_id_idx.parquet",
  ids        = large_id_vector,
  output     = "filtered_works",
  workers    = 3
)
```

### Direct DuckDB Queries

For complex analytical queries, use DuckDB directly:

``` r

library(duckdb)
library(DBI)

con <- dbConnect(duckdb())

# Register parquet files as a view
dbExecute(
  con,
  "
  CREATE VIEW works AS
  SELECT * FROM parquet_scan('/Volumes/external-drive/openalex/parquet/works/*.parquet')
"
)

# Run analytical queries
result <- dbGetQuery(
  con,
  "
  SELECT publication_year, COUNT(*) as n_works
  FROM works
  WHERE publication_year >= 2020
  GROUP BY publication_year
  ORDER BY publication_year
"
)

dbDisconnect(con)
```

## Managing Updates

OpenAlex releases new snapshots regularly. The Makefile supports update
workflows via dedicated timestamp targets.

### Checking for Updates

``` bash
make snapshot_info
```

This shows the current state of the S3 bucket including the total size
and file count.

``` bash
make help
```

This shows the current values of all configuration variables, including
`RELEASE_DATE` read from `RELEASE_NOTES.txt`.

### Update Workflow

``` bash
# 1. Archive the current snapshot with its release date
#    (renames openalex-snapshot → openalex-snapshot-YYYY-MM-DD)
make snapshot_timestamp

# 2. Download the new snapshot
make snapshot

# 3. Archive the current parquet directory with the old release date
make parquet_timestamp

# 4. Re-convert to parquet (deletes parquet dir first, then converts)
make parquet MAX_MEMORY_MB=20000 WORKERS=4

# 5. Rebuild indexes
make parquet_index
```

**Note:** `snapshot_timestamp` and `parquet_timestamp` read the release
date from `RELEASE_NOTES.txt` in the snapshot directory. Run
`snapshot_timestamp` *before* downloading the new snapshot, and
`parquet_timestamp` *before* re-converting, so the old release date is
still available.

## Troubleshooting

### Download Issues

**Interrupted download**: Simply run `make snapshot` again. The sync
will resume where it left off.

**Slow download**: OpenAlex uses CloudFront CDN. Speed depends on your
location and internet connection. Consider running overnight.

**Disk space errors**: Ensure you have at least 400 GB free before
starting.

### Conversion Issues

**Out of memory**: Reduce memory usage by overriding variables on the
command line:

``` bash
make parquet MAX_MEMORY_MB=4000 WORKERS=1 PROFILE=safe
```

**DuckDB errors** (when using `*_R()` fallback functions): Ensure you
have the latest version of the `duckdb` R package.

## Makefile Reference

| Target | Description |
|----|----|
| `help` | Show available targets and current variable values |
| `all` | Clean, download snapshot, and convert to parquet |
| `snapshot_info` | Display S3 bucket size and file count |
| `snapshot_timestamp` | Rename existing snapshot directory with its release date |
| `snapshot` | Download/sync snapshot from S3 |
| `parquet_timestamp` | Rename existing parquet directory with its release date |
| `parquet` | Delete parquet dir then convert snapshot to parquet |
| `parquet_index` | Build ID indexes for all datasets |
| `clean_index` | Remove index files (`*_idx.parquet`) from parquet directory |
| `clean_parquet` | Remove parquet directory (includes index files) |
| `clean_snapshot` | Remove snapshot directory |
| `clean` | Remove both snapshot and parquet directories |

### Customizing the Makefile

Variables can be overridden on the command line or by editing the
defaults at the top of the Makefile:

``` makefile
ROOTDIR=.          # Root directory (snapshot at <ROOTDIR>/openalex-snapshot, parquet at <ROOTDIR>/parquet)
MAX_MEMORY_MB=15000  # Memory cap per worker (in MB)
WORKERS=3            # Number of parallel workers
PROFILE=balanced     # Performance profile: safe / balanced / fast
```

Override on the command line without editing the file:

``` bash
make parquet MAX_MEMORY_MB=20000 WORKERS=4 PROFILE=fast
```

## Additional Resources

- [OpenAlex Documentation](https://docs.openalex.org/)
- [OpenAlex Snapshot
  Documentation](https://docs.openalex.org/download-all-data/openalex-snapshot)
- [DuckDB Documentation](https://duckdb.org/docs/)
- [Apache Parquet Format](https://parquet.apache.org/)
