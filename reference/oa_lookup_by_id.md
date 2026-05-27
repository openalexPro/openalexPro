# Look up records by OpenAlex ID using a pre-built index.

Reads the index file, filters to the requested IDs, and extracts
matching rows into the \`output\` directory (which must not already
exist).

## Usage

``` r
oa_lookup_by_id(index_file, ids, output, workers, verbose)
```

## Arguments

- index_file:

  Path to the index Parquet file (created by
  \[oa_build_corpus_index()\]).

- ids:

  Character vector of OpenAlex IDs (long or short form).

- output:

  Output directory path. Must not already exist.

- workers:

  Number of parallel workers for file extraction.

- verbose:

  Print progress to stderr.

## Value

Invisibly returns \`NULL\`.
