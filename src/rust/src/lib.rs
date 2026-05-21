use extendr_api::prelude::*;

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

// Register all exported functions with R.
extendr_module! {
    mod openalex_pro;
    fn oa_works_abstract_sql;
    fn oa_works_citation_sql;
    fn oa_normalize_duckdb_type;
}
