# Package index

## All functions

- [`build_corpus_index()`](https://openalexpro.github.io/openalexPro/reference/build_corpus_index.md)
  : Build a Parquet ID-lookup index

- [`compatibility_report()`](https://openalexpro.github.io/openalexPro/reference/compatibility_report.md)
  : Render and open the compatibility report

- [`extract_doi()`](https://openalexpro.github.io/openalexPro/reference/extract_doi.md)
  : Extract DOIs or Components from Character Vectors

- [`id_block()`](https://openalexpro.github.io/openalexPro/reference/id_block.md)
  : Compute ID block from OpenAlex IDs

- [`infer_json_schema()`](https://openalexpro.github.io/openalexPro/reference/infer_json_schema.md)
  : Infer unified JSON schema using DuckDB

- [`jq_execute()`](https://openalexpro.github.io/openalexPro/reference/jq_execute.md)
  : Execute a jq transformation from an OpenAlex-style JSON to JSONL

- [`lookup_by_id()`](https://openalexpro.github.io/openalexPro/reference/lookup_by_id.md)
  : Look up records by OpenAlex ID

- [`oa_cache_schema()`](https://openalexpro.github.io/openalexPro/reference/oa_cache_schema.md)
  : Populate the local baseline-schema cache from a snapshot metadata
  directory

- [`oa_normalize_duckdb_type()`](https://openalexpro.github.io/openalexPro/reference/oa_normalize_duckdb_type.md)
  : Canonicalise a DuckDB type string.

- [`oa_works_abstract_sql()`](https://openalexpro.github.io/openalexPro/reference/oa_works_abstract_sql.md)
  :

  Return the DuckDB SQL expression that reconstructs a plain-text
  abstract from the `abstract_inverted_index` column in OpenAlex works
  data.

- [`oa_works_citation_sql()`](https://openalexpro.github.io/openalexPro/reference/oa_works_citation_sql.md)
  :

  Return the DuckDB SQL expression that builds a short citation string
  from the `authorships` and `publication_year` columns in OpenAlex
  works data.

- [`opt_api_key()`](https://openalexpro.github.io/openalexPro/reference/opt_api_key.md)
  : Get API key for OpenAlex API

- [`opt_filter_names()`](https://openalexpro.github.io/openalexPro/reference/opt_filter_names.md)
  : Get available filter names from OpenAlex API

- [`opt_select_fields()`](https://openalexpro.github.io/openalexPro/reference/opt_select_fields.md)
  : Get available select fields from OpenAlex API

- [`prepare_snapshot()`](https://openalexpro.github.io/openalexPro/reference/prepare_snapshot.md)
  : Prepare a directory for OpenAlex snapshot management

- [`pro_api_key()`](https://openalexpro.github.io/openalexPro/reference/pro_api_key.md)
  : Retrieve the OpenAlex Pro API key

- [`pro_download_content()`](https://openalexpro.github.io/openalexPro/reference/pro_download_content.md)
  : Download full-text PDFs or TEI XML for OpenAlex works

- [`pro_fetch()`](https://openalexpro.github.io/openalexPro/reference/pro_fetch.md)
  : Fetch and convert OpenAlex data to Parquet

- [`pro_query()`](https://openalexpro.github.io/openalexPro/reference/pro_query.md)
  : Build an OpenAlex request (httr2)

- [`pro_rate_limit_status()`](https://openalexpro.github.io/openalexPro/reference/pro_rate_limit_status.md)
  : Check OpenAlex rate limit status

- [`pro_request()`](https://openalexpro.github.io/openalexPro/reference/pro_request.md)
  : Fetch works from OpenAlex

- [`pro_request_jsonl_R()`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl_R.md)
  : Convert JSON files to jsonl files

- [`pro_request_jsonl_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_jsonl_parquet.md)
  : Convert JSON files to Apache Parquet files

- [`pro_request_parquet()`](https://openalexpro.github.io/openalexPro/reference/pro_request_parquet.md)
  : Convert JSON files from pro_request() directly to Apache Parquet

- [`pro_validate_credentials()`](https://openalexpro.github.io/openalexPro/reference/pro_validate_credentials.md)
  : Validate OpenAlex credentials

- [`read_corpus()`](https://openalexpro.github.io/openalexPro/reference/read_corpus.md)
  : Read corpus from Parquet Dataset

- [`sample_parquet_n()`](https://openalexpro.github.io/openalexPro/reference/sample_parquet_n.md)
  : Sample rows from Parquet files using DuckDB reservoir sampling

- [`snapshot_to_parquet()`](https://openalexpro.github.io/openalexPro/reference/snapshot_to_parquet.md)
  : Convert OA snapshot to Parquet format
