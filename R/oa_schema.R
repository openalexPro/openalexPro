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
# User-facing: oa_cache_schema() populates the persistent user cache from a
# mounted snapshot-metadata directory so the baseline survives volume unmounts.

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
#' @return A \code{data.frame} with columns \code{col_name} / \code{col_type}
#'   and attribute \code{"entity"}, or \code{NULL}.
#' @noRd
.resolve_baseline <- function(schema, present_cols) {
  if (is.null(schema) || identical(schema, "none")) return(NULL)

  if (identical(schema, "auto")) {
    entity <- oa_detect_entity(present_cols)
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
    entity <- oa_detect_entity(present_cols)
    if (is.null(entity)) return(NULL)
    csv_path <- file.path(schema, paste0(entity, ".csv"))
    if (!file.exists(csv_path)) return(NULL)
    df <- utils::read.csv(csv_path, stringsAsFactors = FALSE)
    attr(df, "entity") <- entity
    return(df)
  }

  NULL
}

# -- Public cache-population function ----------------------------------------

#' Populate the local baseline-schema cache from a snapshot metadata directory
#'
#' Copies \code{unified_schema.csv} files from an OpenAlex snapshot metadata
#' directory (e.g. \code{/Volumes/openalex/openalex-snapshot_metadata}) into
#' the user-level cache used by \code{\link{pro_request_parquet}(schema = "auto")}.
#'
#' Once cached, the schemas are used even when the source volume is not mounted.
#' Update the cache periodically to pick up new fields added by OpenAlex (run
#' with \code{overwrite = TRUE}).
#'
#' @param source Path to the snapshot metadata directory, e.g.
#'   \code{"/Volumes/openalex/openalex-snapshot_metadata"}.
#' @param entities Character vector of entity names to cache, or \code{"all"}
#'   (default) to cache every entity directory found under \code{source}.
#' @param overwrite Logical.  Overwrite an existing cached file?  Default
#'   \code{FALSE}.
#' @param verbose Logical.  Print progress messages?  Default \code{TRUE}.
#'
#' @return The path to the schemata cache directory (invisibly).
#'
#' @seealso \code{\link{pro_request_parquet}} for the \code{schema} parameter.
#'
#' @importFrom tools R_user_dir
#' @importFrom utils read.csv
#'
#' @export
oa_cache_schema <- function(
  source,
  entities  = "all",
  overwrite = FALSE,
  verbose   = TRUE
) {
  if (!dir.exists(source)) {
    stop("source directory does not exist: ", source, call. = FALSE)
  }

  schemata_dir <- file.path(
    tools::R_user_dir("openalexPro", "cache"),
    "schemata"
  )
  dir.create(schemata_dir, recursive = TRUE, showWarnings = FALSE)

  entities_to_cache <- if (identical(entities, "all")) {
    basename(list.dirs(source, recursive = FALSE))
  } else {
    entities
  }

  for (e in entities_to_cache) {
    src_file  <- file.path(source, e, "schemata", "unified_schema.csv")
    dest_file <- file.path(schemata_dir, paste0(e, ".csv"))

    if (!file.exists(src_file)) {
      if (verbose) message("No schema found for entity '", e, "' - skipping.")
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
    file.copy(src_file, dest_file, overwrite = TRUE)
    if (verbose) message("Cached schema for '", e, "'.")
  }

  invisible(schemata_dir)
}
