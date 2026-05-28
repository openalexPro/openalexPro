# sql_helpers -------------------------------------------------------------------
#
# Pure-R implementations of DuckDB SQL expression helpers.
# These were previously backed by Rust (via extendr / openalex-core); the
# strings are identical so all call sites continue to work unchanged.

#' Return the DuckDB SQL expression that reconstructs a plain-text abstract
#' from the \code{abstract_inverted_index} column in OpenAlex works data.
#'
#' The expression walks the map, collects (position, word) pairs, sorts by
#' position ascending, and joins words with single spaces.  Returns NULL when
#' \code{abstract_inverted_index} is NULL.
#'
#' \code{abstract_inverted_index} is normalised to \code{MAP(VARCHAR, BIGINT[])}
#' via a double JSON cast (\code{::JSON::MAP(VARCHAR, BIGINT[])}) before
#' \code{map_entries()} is called.  This makes the expression safe regardless
#' of whether DuckDB inferred the column as \code{MAP}, \code{STRUCT}, or
#' \code{VARCHAR} (raw JSON text): all three round-trip through the JSON
#' representation identically.
#'
#' @return A character scalar containing the SQL expression.
#' @export
oa_works_abstract_sql <- function() {
  paste0(
    "CASE WHEN abstract_inverted_index IS NULL THEN NULL ",
    "ELSE array_to_string( ",
    "list_transform( ",
    "list_sort( ",
    "flatten( ",
    "apply( ",
    "map_entries(abstract_inverted_index::JSON::MAP(VARCHAR, BIGINT[])), ",
    "x -> apply(x.value, p -> {pos: p, word: x.key}) ",
    ") ",
    ") ",
    "), ",
    "e -> e.word ",
    "), ",
    "' ' ",
    ") END"
  )
}

#' Return the DuckDB SQL expression that builds a short citation string from
#' the \code{authorships} and \code{publication_year} columns in OpenAlex
#' works data.
#'
#' Format: \code{"Author (year)"} / \code{"A & B (year)"} /
#' \code{"A et al. (year)"}.
#' Null year renders as \code{"(n.d.)"}.
#' Null or empty \code{authorships} yields NULL.
#'
#' @return A character scalar containing the SQL expression.
#' @export
oa_works_citation_sql <- function() {
  year <- "COALESCE(publication_year::VARCHAR, 'n.d.')"
  paste0(
    "CASE ",
    "WHEN authorships IS NULL OR len(authorships) = 0 THEN NULL ",
    "WHEN len(authorships) = 1 THEN ",
    "authorships[1].author.display_name || ' (' || ", year, " || ')' ",
    "WHEN len(authorships) = 2 THEN ",
    "authorships[1].author.display_name || ' & ' || ",
    "authorships[2].author.display_name || ' (' || ", year, " || ')' ",
    "ELSE ",
    "authorships[1].author.display_name || ' et al. (' || ", year, " || ')' ",
    "END"
  )
}

#' Canonicalise a DuckDB type string.
#'
#' Uppercases SQL type keywords (\code{BIGINT}, \code{VARCHAR},
#' \code{STRUCT}, \ldots) while preserving the case of struct field
#' identifiers.
#'
#' @param t A character scalar: a raw DuckDB type string, e.g.
#'   \code{"struct(author struct(display_name varchar))"}.
#' @return A character scalar with normalised type keywords.
#' @export
oa_normalize_duckdb_type <- function(t) {
  keywords <- c(
    "ARRAY", "BIGINT", "BLOB", "BOOLEAN", "DATE", "DOUBLE", "ENUM",
    "FLOAT", "HUGEINT", "INTEGER", "INTERVAL", "JSON", "LIST", "MAP",
    "SMALLINT", "STRUCT", "TIME", "TIMESTAMP", "TINYINT", "UBIGINT",
    "UINTEGER", "UNION", "USMALLINT", "UTINYINT", "VARCHAR"
  )
  pattern <- paste0("(?i)\\b(", paste(keywords, collapse = "|"), ")\\b")
  gsub(pattern, "\\U\\1", t, perl = TRUE)
}
