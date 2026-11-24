#' Sample rows from Parquet files using DuckDB reservoir sampling
#'
#' @description
#' Draw a uniform random sample of \code{n} rows from one or more Parquet files
#' using DuckDB's SQL \code{USING SAMPLE reservoir(n ROWS)} clause.
#' The sampling is performed entirely inside DuckDB, so the full dataset
#' is never loaded into R.
#'
#' This is well-suited for large Parquet corpora (e.g. OpenAlex works) where
#' you want a random subset of rows without materialising the whole table.
#'
#' @param path Character scalar. Path or glob pointing to one or more Parquet
#'   files, as understood by DuckDB's \code{parquet_scan()} table function.
#'   For example, \code{"spc_corpus/output/chapter_3/corpus/*.parquet"}.
#'
#' @param n Integer scalar. Number of rows to sample. If \code{n} is larger
#'   than the total number of rows in the dataset, DuckDB returns all rows.
#'
#' @param seed Optional integer scalar. If supplied, a \code{REPEATABLE(seed)}
#'   clause is added to the DuckDB query so that repeated calls with the same
#'   input data and seed return the same sample. If \code{NULL} (default),
#'   the sample is not forced to be reproducible at the DuckDB level.
#'
#' @param con Optional \code{\link[DBI:DBIConnection-class]{DBIConnection}} to
#'   an existing DuckDB database. If \code{NULL} (the default), the function
#'   creates a temporary in-memory DuckDB instance, uses it for the query,
#'   and shuts it down before returning. If a connection is supplied, it is
#'   left open and not modified beyond running the sampling query.
#'
#' @param select Optional character vector of column names to return. If
#'   \code{NULL} (default), all columns are returned (equivalent to
#'   \code{SELECT *}). Column names are passed through
#'   \code{\link[DBI:dbQuoteIdentifier]{DBI::dbQuoteIdentifier()}} to safely
#'   handle special characters. If any requested column does not exist in the
#'   Parquet schema, DuckDB will raise an error.
#'
#' @return
#' A \code{data.frame} with up to \code{n} rows, containing a uniform random
#' sample from the union of all Parquet files matched by \code{path}, restricted
#' to the columns specified in \code{select} (or all columns if \code{select} is
#' \code{NULL}).
#'
#' @details
#' The function delegates to the following SQL pattern (simplified):
#'
#' \preformatted{
#' SELECT [columns]
#' FROM parquet_scan('path/to/files/*.parquet')
#' USING SAMPLE reservoir(n ROWS)
#' [REPEATABLE (seed)]
#' }
#'
#' Using \code{reservoir(n ROWS)} gives an exact uniform sample of size
#' \code{n} from all rows in the dataset (unless \code{n} exceeds the total
#' row count, in which case all rows are returned).
#'
#' Note that the \code{path} argument is passed directly to DuckDB's
#' \code{parquet_scan()} function, so you can use:
#'
#' \itemize{
#'   \item A single Parquet file:
#'     \itemize{\item \code{"works.parquet"}}
#'   \item A glob for many files:
#'     \itemize{\item \code{"works/*.parquet"}}
#'   \item A directory, depending on your DuckDB version/configuration.
#' }
#'
#' When \code{con} is \code{NULL}, the function creates an in-memory DuckDB
#' database. If you want to reuse the same DuckDB instance for multiple queries
#' (for performance reasons or to control pragmas), you can create a DuckDB
#' connection yourself and pass it via \code{con}.
#'
#' @examples
#' \dontrun{
#' # Sample 1,000 rows from a directory of Parquet files
#' sample_df <- sample_parquet_duckdb(
#'   path = "spc_corpus/output/chapter_3/corpus/*.parquet",
#'   n = 10000L,
#'   seed = 1234
#' )
#'
#' # Sample only a subset of columns
#' sample_df_small <- sample_parquet_duckdb(
#'   path = "spc_corpus/output/chapter_3/corpus/*.parquet",
#'   n = 10000L,
#'   seed = 1234,
#'   select = c("id", "doi", "citation", "author_abbr", "display_name", "ab")
#' )
#'
#' # Reuse a DuckDB connection for multiple samples
#' con <- DBI::dbConnect(duckdb::duckdb())
#' on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
#'
#' s1 <- sample_parquet_duckdb(
#'   path = "openalex_works/*.parquet",
#'   n = 500L,
#'   seed = 42,
#'   con = con
#' )
#'
#' s2 <- sample_parquet_duckdb(
#'   path = "openalex_works/*.parquet",
#'   n = 500L,
#'   seed = 777,
#'   con = con
#' )
#' }
#'
#' @export
#'
#' @importFrom DBI dbConnect dbDisconnect dbGetQuery dbQuoteString dbQuoteIdentifier
#' @importFrom duckdb duckdb
sample_parquet_n <- function(
  path,
  n,
  seed = NULL,
  con = NULL,
  select = NULL
) {
  # Basic argument checks
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    stop("`path` must be a non-missing character scalar.", call. = FALSE)
  }

  if (length(n) != 1L || is.na(n)) {
    stop("`n` must be a single non-missing numeric value.", call. = FALSE)
  }
  n_int <- as.integer(n)
  if (!is.finite(n_int) || n_int <= 0L) {
    stop("`n` must be a positive integer.", call. = FALSE)
  }

  if (!is.null(seed)) {
    if (length(seed) != 1L || is.na(seed)) {
      stop(
        "`seed` must be a single non-missing numeric value or NULL.",
        call. = FALSE
      )
    }
    seed_int <- as.integer(seed)
    if (!is.finite(seed_int)) {
      stop("`seed` must be coercible to a finite integer.", call. = FALSE)
    }
  } else {
    seed_int <- NULL
  }

  if (!is.null(select)) {
    if (!is.character(select) || length(select) == 0L || anyNA(select)) {
      stop(
        "`select` must be NULL or a non-empty character vector of column names.",
        call. = FALSE
      )
    }
  }

  # Create a temporary DuckDB connection if needed
  local_con <- is.null(con)
  if (local_con) {
    con <- DBI::dbConnect(.pro_duckdb())
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  }

  # Quote path for use inside parquet_scan()
  path_quoted <- DBI::dbQuoteString(con, path)

  # Build the SELECT list
  select_sql <- if (is.null(select)) {
    "*"
  } else {
    quoted_cols <- DBI::dbQuoteIdentifier(con, select)
    paste(as.character(quoted_cols), collapse = ", ")
  }

  # Build the SQL query
  query <- paste0(
    "SELECT ",
    select_sql,
    " FROM parquet_scan(",
    path_quoted,
    ") USING SAMPLE reservoir(",
    n_int,
    " ROWS)",
    if (!is.null(seed_int)) paste0(" REPEATABLE (", seed_int, ")") else ""
  )

  # Execute and return the sampled rows
  DBI::dbGetQuery(con, query)
}
