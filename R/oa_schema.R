# oa_schema.R ---------------------------------------------------------------
#
# Baseline schema helpers for pro_request_parquet().
#
# Flow:
#   pro_request_parquet(schema = "auto")
#     +-- .resolve_baseline()
#           +-- oa_detect_entity()        # which entity is this JSON?
#           +-- oa_load_baseline_schema() # load CSV from user cache or inst/extdata
#
# User-facing: oa_schema() reads (update = FALSE) or refreshes (update = TRUE)
# the persistent schema cache from a Parquet corpus directory.

# -- Entity detection --------------------------------------------------------

#' Detect the OpenAlex entity type from top-level column names
#'
#' Uses discriminating column signatures to map a set of observed top-level
#' column names to one of the bundled entity names.
#'
#' @param col_names Character vector of top-level column names (as returned by
#'   DuckDB DESCRIBE or \code{schema_df$column_name}).
#' @return A character scalar (entity name matching the bundled CSV filenames,
#'   e.g. \code{"works"}) or \code{NULL} if detection fails.
#' @noRd
oa_detect_entity <- function(col_names) {
  if ("abstract_inverted_index" %in% col_names) return("works")
  if ("orcid" %in% col_names)                   return("authors")
  if ("issn_l" %in% col_names)                  return("sources")
  if ("ror" %in% col_names)                     return("institutions")
  if ("wikidata" %in% col_names)                return("concepts")
  if ("funder_groups" %in% col_names)           return("funders")
  if ("publisher" %in% col_names)               return("publishers")
  if ("domain" %in% col_names)                  return("topics")   # best guess
  NULL
}

# -- Schema loading ------------------------------------------------------------

#' Load a baseline schema data frame for a given entity
#'
#' Checks the user cache first, then falls back to the schemas bundled in
#' \code{inst/extdata/schemata/}.
#'
#' @param entity Character scalar, e.g. \code{"works"}.
#' @return A \code{data.frame} with columns \code{col_name} and \code{col_type},
#'   or \code{NULL} if no schema is found.
#' @noRd
oa_load_baseline_schema <- function(entity) {
  # 1. User cache
  user_path <- file.path(
    tools::R_user_dir("openalexPro", "cache"),
    "schemata",
    paste0(entity, ".csv")
  )
  if (file.exists(user_path)) {
    df <- utils::read.csv(user_path, stringsAsFactors = FALSE)
    attr(df, "entity") <- entity
    return(df)
  }

  # 2. Package-bundled
  pkg_path <- system.file(
    "extdata", "schemata", paste0(entity, ".csv"),
    package = "openalexPro"
  )
  if (nchar(pkg_path) > 0L && file.exists(pkg_path)) {
    df <- utils::read.csv(pkg_path, stringsAsFactors = FALSE)
    attr(df, "entity") <- entity
    return(df)
  }

  NULL
}

# -- Internal resolution helper ------------------------------------------------

#' Resolve a baseline schema data frame from the `schema` argument
#'
#' Called by \code{pro_request_parquet()} after runtime schema inference.
#'
#' @param schema Value of the \code{schema} argument.
#' @param present_cols Character vector of top-level column names from runtime
#'   inference (used for entity auto-detection).
#' @param entity Entity name; detected from \code{present_cols} by default.
#' @return A \code{data.frame} with columns \code{col_name} / \code{col_type}
#'   and attribute \code{"entity"}, or \code{NULL}.
#' @noRd
.resolve_baseline <- function(schema, present_cols,
                              entity = oa_detect_entity(present_cols)) {
  if (is.null(schema) || identical(schema, "none")) return(NULL)

  if (identical(schema, "auto")) {
    if (is.null(entity)) return(NULL)
    return(oa_load_baseline_schema(entity))
  }

  # Explicit path to a CSV file
  if (file.exists(schema) && !dir.exists(schema)) {
    df <- utils::read.csv(schema, stringsAsFactors = FALSE)
    attr(df, "entity") <- basename(tools::file_path_sans_ext(schema))
    return(df)
  }

  # Explicit path to a directory - auto-detect entity, look for <entity>.csv
  if (dir.exists(schema)) {
    if (is.null(entity)) return(NULL)
    csv_path <- file.path(schema, paste0(entity, ".csv"))
    if (!file.exists(csv_path)) return(NULL)
    df <- utils::read.csv(csv_path, stringsAsFactors = FALSE)
    attr(df, "entity") <- entity
    return(df)
  }

  NULL
}

# -- Public schema function ---------------------------------------------------

#' Get or refresh an OpenAlex entity schema
#'
#' Returns the baseline column schema for an OpenAlex entity (used by
#' \code{\link{pro_request_parquet}(schema = "auto")} to resolve ambiguous
#' DuckDB JSON types), and optionally refreshes the user-level cache from a
#' local Parquet corpus.
#'
#' @section Resolution order (\code{update = FALSE}):
#' \enumerate{
#'   \item User cache (\code{tools::R_user_dir("openalexPro","cache")/schemata/<entity>.csv})
#'   \item Schemas bundled with the package (\code{inst/extdata/schemata/<entity>.csv})
#' }
#'
#' @section Refreshing the cache (\code{update = TRUE}):
#' Reads the schema of each entity corpus from \code{parquet_dir} using
#' DuckDB and writes the result to the user cache.  After updating, the new
#' schema is available to subsequent calls with \code{update = FALSE} and to
#' \code{pro_request_parquet(schema = "auto")}.  Run periodically to pick up
#' new fields added by OpenAlex.
#'
#' @param entity Character scalar.  Entity name, e.g. \code{"works"}.
#'   Required when \code{update = FALSE}; ignored when \code{update = TRUE}
#'   and \code{entities != "all"} is a vector.
#' @param parquet_dir Character scalar.  Root Parquet directory containing one
#'   sub-directory per entity, e.g. \code{"/Volumes/openalex/parquet"}.
#'   Required when \code{update = TRUE}; ignored otherwise.
#' @param entities Character vector or \code{"all"} (default).  Entities to
#'   refresh when \code{update = TRUE}.  \code{"all"} auto-discovers
#'   sub-directories of \code{parquet_dir}, excluding \code{*_aws} staging
#'   directories.
#' @param overwrite Logical.  When \code{update = TRUE}, overwrite an existing
#'   cached CSV?  Default \code{FALSE}.
#' @param update Logical.  When \code{TRUE}, read schema from \code{parquet_dir}
#'   and write to the user cache.  Default \code{FALSE}.
#' @param verbose Logical.  Print progress messages?  Default \code{TRUE}.
#'
#' @return
#'   \code{update = FALSE}: a \code{data.frame} with columns \code{col_name}
#'   and \code{col_type}, or \code{NULL} if no schema is found for
#'   \code{entity}.\cr
#'   \code{update = TRUE}: the path to the schemata cache directory
#'   (invisibly).
#'
#' @seealso \code{\link{pro_request_parquet}} for the \code{schema} parameter.
#'
#' @importFrom tools R_user_dir
#' @importFrom utils read.csv write.csv
#' @importFrom DBI dbConnect dbDisconnect dbGetQuery
#' @importFrom duckdb duckdb
#'
#' @export
oa_schema <- function(
  entity     = NULL,
  parquet_dir = NULL,
  entities   = "all",
  overwrite  = FALSE,
  update     = FALSE,
  verbose    = TRUE
) {
  schemata_dir <- file.path(
    tools::R_user_dir("openalexPro", "cache"),
    "schemata"
  )

  # -- Read mode ---------------------------------------------------------------
  if (!update) {
    if (is.null(entity) || !nzchar(entity)) {
      stop("`entity` must be provided when update = FALSE.", call. = FALSE)
    }
    return(oa_load_baseline_schema(entity))
  }

  # -- Update mode -------------------------------------------------------------
  if (is.null(parquet_dir) || !nzchar(parquet_dir)) {
    stop("`parquet_dir` must be provided when update = TRUE.", call. = FALSE)
  }
  if (!dir.exists(parquet_dir)) {
    stop("parquet_dir does not exist: ", parquet_dir, call. = FALSE)
  }

  dir.create(schemata_dir, recursive = TRUE, showWarnings = FALSE)

  entities_to_update <- if (identical(entities, "all")) {
    subdirs <- list.dirs(parquet_dir, recursive = FALSE, full.names = FALSE)
    # Exclude _aws staging dirs (e.g. works_aws) and any stray files
    subdirs[!grepl("_aws$", subdirs)]
  } else {
    entities
  }

  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  for (e in entities_to_update) {
    entity_dir <- file.path(parquet_dir, e)
    dest_file  <- file.path(schemata_dir, paste0(e, ".csv"))

    if (!dir.exists(entity_dir)) {
      if (verbose) message("No parquet directory for entity '", e, "' - skipping.")
      next
    }
    if (file.exists(dest_file) && !overwrite) {
      if (verbose) {
        message(
          "Schema for '", e, "' already cached ",
          "(use overwrite = TRUE to replace)."
        )
      }
      next
    }

    pq_glob <- file.path(entity_dir, "**", "*.parquet")
    sql <- sprintf(
      "DESCRIBE SELECT * FROM read_parquet('%s', union_by_name = true)",
      gsub("'", "\\'", pq_glob, fixed = TRUE)
    )
    tryCatch({
      desc <- DBI::dbGetQuery(con, sql)
      schema_df <- data.frame(
        col_name = desc$column_name,
        col_type = desc$column_type,
        stringsAsFactors = FALSE
      )
      utils::write.csv(schema_df, dest_file, row.names = FALSE)
      if (verbose) message("Updated schema for '", e, "'.")
    }, error = function(err) {
      if (verbose) message("Failed to read schema for '", e, "': ", conditionMessage(err))
    })
  }

  invisible(schemata_dir)
}
