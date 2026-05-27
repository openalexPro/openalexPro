use extendr_api::prelude::*;

// ── SQL-string helpers (always available) ────────────────────────────────────

/// Return the DuckDB SQL expression that reconstructs a plain-text abstract
/// from the `abstract_inverted_index` MAP column in OpenAlex works data.
///
/// The expression walks the map, collects (position, word) pairs, sorts by
/// position ascending, and joins words with single spaces.  Returns NULL when
/// `abstract_inverted_index` is NULL.
///
/// @return A character scalar containing the SQL expression.
/// @export
#[extendr]
fn oa_works_abstract_sql() -> &'static str {
    openalex_core::works_abstract_expr()
}

/// Return the DuckDB SQL expression that builds a short citation string from
/// the `authorships` and `publication_year` columns in OpenAlex works data.
///
/// Format: `"Author (year)"` / `"A & B (year)"` / `"A et al. (year)"`.
/// Null year renders as `"(n.d.)"`.  Null or empty `authorships` yields NULL.
///
/// @return A character scalar containing the SQL expression.
/// @export
#[extendr]
fn oa_works_citation_sql() -> String {
    openalex_core::works_citation_expr()
}

/// Canonicalise a DuckDB type string.
///
/// Uppercases SQL type keywords (`BIGINT`, `VARCHAR`, `STRUCT`, …) while
/// preserving the case of struct field identifiers.  This matches DuckDB's
/// own behaviour: type keywords are case-insensitive but struct field names
/// used in `read_json(columns = …)` are matched case-sensitively.
///
/// @param t A character scalar: a raw DuckDB type string, e.g.
///   `"struct(author struct(display_name varchar))"`.
/// @return A character scalar with normalised type keywords.
/// @export
#[extendr]
fn oa_normalize_duckdb_type(t: &str) -> String {
    openalex_core::normalize_duckdb_type(t)
}

// ── Conversion pipeline ──────────────────────────────────────────────────────

/// Convert an OpenAlex snapshot to Parquet format.
///
/// Full pipeline: schema inference (per-dataset, cached in
/// `<parquet_dir>/<dataset>/.schema_cache/unified_schema.csv`) plus parallel
/// per-file COPY via rayon.
///
/// @param snapshot_dir Path to the snapshot root (contains a `data/` subdir).
/// @param parquet_dir  Output directory for Parquet files.
/// @param data_sets    Character vector of dataset names, or `character(0)` for
///   all datasets found under `snapshot_dir/data/` (excluding `merged_ids`).
/// @param workers      Number of parallel workers (`1` = sequential).
/// @param sample_size  Files to sample for schema inference (`0` = all).
/// @param memory_limit DuckDB memory limit, e.g. `"8GB"` (`""` = no limit).
/// @param temp_dir     DuckDB temp directory (`""` = system default).
/// @param verbose      Print progress to stderr.
/// @return Invisibly returns `NULL`.
/// @export
#[extendr]
fn oa_snapshot_to_parquet(
    snapshot_dir: &str,
    parquet_dir: &str,
    data_sets: Vec<String>,
    workers: i32,
    sample_size: i32,
    memory_limit: &str,
    temp_dir: &str,
    verbose: bool,
) -> extendr_api::Result<()> {
    openalex_core::conversion::snapshot_to_parquet(
        snapshot_dir,
        parquet_dir,
        data_sets,
        workers.max(1) as usize,
        sample_size.max(0) as usize,
        memory_limit,
        temp_dir,
        verbose,
    )
    .map_err(|e| extendr_api::Error::Other(e.to_string()))
}

/// Infer the DuckDB schema for OpenAlex API JSON response files.
///
/// Runs a `DESCRIBE` query with `ignore_errors = true` on a sample of
/// `files` and returns the inferred schema.  `abstract_inverted_index` is
/// always stored as `VARCHAR` (raw JSON string) to avoid DuckDB's
/// case-folding collision on duplicate JSON keys (e.g. `"the"` / `"The"`).
///
/// @param files        Character vector of JSON file paths to sample
///   (at most 20 are used).
/// @param array_field  Name of the JSON array key (`"results"`, `"group_by"`),
///   or `""` for single-record files.
/// @param sample_size  Records per file for DuckDB's `sample_size` option.
///   Use `0L` to read all records.  Default `1000L`.
/// @return A named list:
///   \describe{
///     \item{`list_type`}{`"STRUCT(...)[]"` string for paginated files, or
///       `""` for single-record files and on inference failure.}
///     \item{`columns`}{Character vector of inferred column names.}
///   }
/// @export
#[extendr]
fn oa_infer_api_list_type(
    files: Vec<String>,
    array_field: &str,
    sample_size: i32,
) -> extendr_api::Result<List> {
    let (list_type, columns) = openalex_core::infer_api_list_type(
        &files,
        array_field,
        sample_size.max(0) as usize,
    );
    Ok(list!(list_type = list_type, columns = columns))
}

/// Parallel per-file conversion for OpenAlex API JSON responses.
///
/// When `list_type` is `""` and `array_field` is non-empty, schema inference
/// is performed internally in Rust (up to 20 sampled files, 1000 records
/// each, `ignore_errors = true`, `abstract_inverted_index` forced to
/// `VARCHAR`).  For best performance, pre-compute `list_type` via
/// [oa_infer_api_list_type()] so that schema inference runs only once and
/// its result can also be used to decide which enrichment columns to add.
///
/// @param input_files  Character vector of input JSON file paths.
/// @param output_files Character vector of output Parquet file paths
///   (same length as `input_files`).
/// @param array_field  Name of the JSON array key (`"results"`, `"group_by"`),
///   or `""` for single-record files.
/// @param list_type    DuckDB STRUCT type string for array items, e.g.
///   `"STRUCT(id VARCHAR, title VARCHAR)[]"`.  `""` = infer internally
///   (paginated) or fall back to `read_json_auto` (single-record).
/// @param extra_select SQL fragment appended after `SELECT *`, e.g.
///   `", abstract_expr AS abstract, 'p1' AS page"`.
/// @param workers      Number of parallel workers.
/// @param verbose      Print failures to stderr.
/// @return Invisibly returns `NULL`.
/// @export
#[extendr]
fn oa_api_files_to_parquet(
    input_files: Vec<String>,
    output_files: Vec<String>,
    array_field: &str,
    list_type: &str,
    extra_select: &str,
    workers: i32,
    verbose: bool,
) -> extendr_api::Result<()> {
    openalex_core::conversion::api_files_to_parquet(
        &input_files,
        &output_files,
        array_field,
        list_type,
        extra_select,
        workers.max(1) as usize,
        verbose,
    )
    .map_err(|e| extendr_api::Error::Other(e.to_string()))
}

/// Build a two-stage ID-lookup index for a single Parquet corpus directory.
///
/// Stage 1: per-file shard indexes (parallel via rayon).
/// Stage 2: combine shards into `<corpus_name>_id_idx.parquet`.
///
/// Returns the path to the created index file as a character scalar.
///
/// @param corpus_dir   Path to a single dataset Parquet directory.
/// @param workers      Number of parallel workers for Stage 1.
/// @param memory_limit DuckDB memory limit (`""` = no limit).
/// @param overwrite    If `TRUE`, rebuild an existing index.
/// @param verbose      Print progress to stderr.
/// @return Character scalar: path to the index file.
/// @export
#[extendr]
fn oa_build_corpus_index(
    corpus_dir: &str,
    workers: i32,
    memory_limit: &str,
    overwrite: bool,
    verbose: bool,
) -> extendr_api::Result<String> {
    openalex_core::conversion::build_corpus_index(
        corpus_dir,
        workers.max(1) as usize,
        memory_limit,
        overwrite,
        verbose,
    )
    .map_err(|e| extendr_api::Error::Other(e.to_string()))
}

/// Look up records by OpenAlex ID using a pre-built index.
///
/// Reads the index file, filters to the requested IDs, and extracts matching
/// rows into the `output` directory (which must not already exist).
///
/// @param index_file Path to the index Parquet file (created by
///   [oa_build_corpus_index()]).
/// @param ids        Character vector of OpenAlex IDs (long or short form).
/// @param output     Output directory path.  Must not already exist.
/// @param workers    Number of parallel workers for file extraction.
/// @param verbose    Print progress to stderr.
/// @return Invisibly returns `NULL`.
/// @export
#[extendr]
fn oa_lookup_by_id(
    index_file: &str,
    ids: Vec<String>,
    output: &str,
    workers: i32,
    verbose: bool,
) -> extendr_api::Result<()> {
    openalex_core::conversion::lookup_by_id(
        index_file,
        &ids,
        output,
        workers.max(1) as usize,
        verbose,
    )
    .map(|_| ())
    .map_err(|e| extendr_api::Error::Other(e.to_string()))
}

// ── Module registration ──────────────────────────────────────────────────────

// Register all exported functions with R.
extendr_module! {
    mod openalex_pro;
    fn oa_works_abstract_sql;
    fn oa_works_citation_sql;
    fn oa_normalize_duckdb_type;
    fn oa_snapshot_to_parquet;
    fn oa_infer_api_list_type;
    fn oa_api_files_to_parquet;
    fn oa_build_corpus_index;
    fn oa_lookup_by_id;
}
