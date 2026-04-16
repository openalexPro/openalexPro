# lookup_by_id -----------------------------------------------------------------
#
# Two implementations are provided:
#   lookup_by_id()   — thin wrapper around the openalex-snapshot binary
#   lookup_by_id_R() — pure R / DuckDB fallback (original implementation)

# lookup_by_id (binary wrapper) ------------------------------------------------

#' Look up records by ID and extract them into a project directory
#'
#' Delegates ID-based record extraction to the external
#' \code{openalex-snapshot} binary. The binary uses the pre-built index
#' (created by [build_corpus_index()]) to locate records efficiently and writes
#' them as Parquet files into \code{<project_dir>/snapshot_extract/}.
#'
#' The pure-R fallback is available as [lookup_by_id_R()].
#'
#' @param root_dir Root directory containing \code{parquet/} and the dataset
#'   indexes produced by [build_corpus_index()].
#' @param ids Character vector of OpenAlex IDs to retrieve. Can be long form
#'   (e.g. \code{"https://openalex.org/W2741809807"}) or short form
#'   (e.g. \code{"W2741809807"}).
#' @param project_dir Project output directory. Extracted Parquet files are
#'   written to \code{<project_dir>/snapshot_extract_<dataset>.parquet},
#'   consistent with the project-folder convention used by [pro_request()] and
#'   [pro_fetch()].
#' @param data_sets Character vector of dataset names to search (e.g.
#'   \code{c("works", "authors")}). \code{NULL} searches all datasets.
#' @param workers Number of parallel worker threads. \code{NULL} uses the
#'   binary's default (4).
#' @param profile Performance/memory profile: \code{"safe"}, \code{"balanced"}
#'   (default), or \code{"fast"}.
#' @param progress Show progress bars. Default is \code{TRUE}.
#' @param oas_bin Path to the \code{openalex-snapshot} binary. If \code{NULL}
#'   (default), checks \code{getOption("openalexPro.oas_bin")} then PATH.
#'
#' @return Invisibly returns \code{project_dir}.
#'
#' @seealso [lookup_by_id_R()] for the pure-R fallback,
#'   [build_corpus_index()] for building the required index.
#'
#' @examples
#' \dontrun{
#' lookup_by_id(
#'   root_dir    = "/Volumes/openalex",
#'   ids         = c("W2741809807", "W1234567890"),
#'   project_dir = "my_project"
#' )
#' }
#'
#' @importFrom cli cli_abort
#' @importFrom rlang caller_env
#' @export
#' @md
lookup_by_id <- function(
  root_dir,
  ids,
  project_dir,
  data_sets = NULL,
  workers   = NULL,
  profile   = c("balanced", "safe", "fast"),
  progress  = TRUE,
  oas_bin   = NULL
) {
  profile <- match.arg(profile)

  if (missing(ids) || length(ids) == 0) {
    cli::cli_abort("{.arg ids} must be provided and non-empty.")
  }

  # Normalise IDs to long form
  ids <- ifelse(
    grepl("^https://openalex\\.org/", ids),
    ids,
    paste0("https://openalex.org/", ids)
  )

  # Write IDs to a temporary CSV file
  tmp_csv <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp_csv), add = TRUE)
  writeLines(ids, tmp_csv)

  output_base <- file.path(project_dir, "snapshot_extract")
  dir.create(project_dir, recursive = TRUE, showWarnings = FALSE)

  ds <- if (is.null(data_sets)) "all" else paste(data_sets, collapse = ",")

  args <- c(
    "extract",
    "--root-dir", root_dir,
    "--ids",      tmp_csv,
    "--output",   output_base,
    "--dataset",  ds,
    "--profile",  profile
  )
  if (!is.null(workers))  args <- c(args, "--workers", as.integer(workers))
  if (!isTRUE(progress))  args <- c(args, "--no-progress")

  run_oas(args, oas_bin = oas_bin)

  invisible(project_dir)
}


# lookup_by_id_R (pure-R fallback) ---------------------------------------------

#' Look up records by ID using a pre-built index (pure-R implementation)
#'
#' Pure-R / DuckDB implementation of ID-based record retrieval. This is the
#' original implementation, preserved as a fallback for environments where the
#' \code{openalex-snapshot} binary is not available.
#'
#' For most users, [lookup_by_id()] (which delegates to the binary) is
#' preferred.
#'
#' @param index_file Path to the index parquet file created by
#'   [build_corpus_index_R()].
#' @param ids Character vector of OpenAlex IDs to look up. Can be in long form
#'   (e.g., \code{"https://openalex.org/W2741809807"}) or short form
#'   (e.g., \code{"W2741809807"}).
#' @param workers Number of parallel workers for reading corpus files.
#'   Default is \code{NULL} (sequential). If \code{> 1}, uses
#'   [future.apply::future_lapply()] with [future::multisession].
#' @param selected Path to the parquet dataset containing the selected indices,
#'   partitioned by \code{parquet_file} of the work. If \code{NULL}, not saved.
#' @param output Path to an output directory for writing results as parquet
#'   files. If \code{NULL} (default), results are returned as a data frame.
#'   If set, filtered records are written directly to parquet (one file per
#'   source corpus file) without loading them into R memory. The directory
#'   must not already exist.
#' @param verbose If \code{TRUE}, print progress messages. Default: \code{TRUE}.
#'
#' @return If \code{output} is \code{NULL}, a data frame containing the
#'   matching records. If \code{output} is set, the output directory path is
#'   returned invisibly.
#'
#' @seealso [lookup_by_id()] for the preferred binary-backed version.
#'
#' @importFrom arrow open_dataset write_dataset
#' @importFrom DBI dbConnect dbDisconnect dbGetQuery dbExecute
#' @importFrom dplyr filter collect
#' @importFrom rlang .data
#' @importFrom duckdb duckdb
#' @importFrom future plan multisession
#' @importFrom future.apply future_lapply
#' @importFrom progressr with_progress progressor
#'
#' @examples
#' \dontrun{
#' records <- lookup_by_id_R(
#'   index_file = "works_id_index.parquet",
#'   ids        = c("W2741809807", "W1234567890")
#' )
#'
#' lookup_by_id_R(
#'   index_file = "works_id_index.parquet",
#'   ids        = large_id_vector,
#'   output     = "filtered_works",
#'   workers    = 3
#' )
#' }
#'
#' @export
#' @md
lookup_by_id_R <- function(
  index_file,
  ids,
  selected = NULL,
  workers  = NULL,
  output   = NULL,
  verbose  = TRUE
) {
  ## Validate inputs
  if (missing(ids) || length(ids) == 0) {
    stop("'ids' must be provided")
  }

  ## Check index exists
  index_file    <- normalizePath(index_file, mustWork = FALSE)
  snapshot_path <- dirname(index_file)
  if (!file.exists(index_file)) {
    stop("Index file not found: ", index_file)
  }

  ## Validate output directory
  if (!is.null(output)) {
    if (dir.exists(output)) {
      stop("Output directory already exists: ", output)
    }
  }

  ## Normalize IDs - add prefix if missing
  if (verbose) {
    message("Normalizing ids to long form ...")
  }
  ids <- ifelse(
    grepl("^https://openalex.org/", ids),
    ids,
    paste0("https://openalex.org/", ids)
  )

  if (verbose) {
    message("Looking up ", length(ids), " ...")
  }

  ## Query each id_block partition separately
  matches <- index_file |>
    arrow::open_dataset() |>
    dplyr::filter(.data$id %in% ids) |>
    dplyr::collect()

  if (is.null(matches) || nrow(matches) == 0) {
    message("No matching records found in index")
    if (!is.null(output)) {
      return(invisible(output))
    }
    return(data.frame())
  }

  if (verbose) {
    message("Found ", nrow(matches), " matching records in index")
  }

  if (!is.null(selected)) {
    if (verbose) {
      message("Saving selected ids to ", selected)
    }
    arrow::write_dataset(
      dataset      = matches,
      path         = selected,
      format       = "parquet",
      partitioning = "parquet_file"
    )
  }

  ## Set up parallel plan if workers > 1
  if (!is.null(workers) && workers > 1) {
    old_plan <- future::plan(future::multisession, workers = workers)
    on.exit(future::plan(old_plan), add = TRUE)
  }

  ## Split matches by corpus file
  if (verbose) {
    message("Splitting into parquet files ...")
  }
  file_chunks <- split(matches$file_row_number, matches$parquet_file)
  # Normalise to forward slashes so DuckDB receives consistent paths on all
  # platforms (normalizePath on Windows may produce backslashes). ----
  names(file_chunks) <- gsub(
    "\\\\", "/",
    file.path(snapshot_path, names(file_chunks))
  )

  ## Read/write records from each corpus file (parallel if workers > 1)
  if (verbose) {
    message("Retrieving and saving works per parquet file ...")
  }

  ##### this is waiting for rewrite - stopgap solution!
  oopts <- options(future.globals.maxSize = 1.0 * 1e9) ## 1.0 GB
  on.exit(options(oopts), add = TRUE)
  #####

  if (!is.null(output)) {
    dir.create(output, recursive = TRUE, showWarnings = FALSE)
  }

  progressr::with_progress({
    p <- progressr::progressor(along = file_chunks)
    results <- future.apply::future_lapply(
      names(file_chunks),
      function(pq_file) {
        row_numbers <- file_chunks[[pq_file]]

        ## Each worker gets its own DuckDB connection
        worker_con <- DBI::dbConnect(duckdb::duckdb(), read_only = TRUE)
        on.exit(DBI::dbDisconnect(worker_con, shutdown = TRUE))

        row_filter <- paste(row_numbers, collapse = ", ")

        result <- if (!is.null(output)) {
          ## Write directly to parquet — never loads into R memory
          out_file   <- file.path(output, paste0("part_", basename(pq_file)))
          copy_query <- paste0(
            "COPY (SELECT * FROM read_parquet('",
            pq_file,
            "', file_row_number = true) ",
            "WHERE file_row_number IN (",
            row_filter,
            ")) ",
            "TO '",
            out_file,
            "' (FORMAT PARQUET, COMPRESSION SNAPPY)"
          )
          tryCatch(
            {
              DBI::dbExecute(worker_con, copy_query)
              length(row_numbers)
            },
            error = function(e) {
              warning("Failed to write from ", pq_file, ": ", e$message)
              0L
            }
          )
        } else {
          ## Return data frame (in-memory mode)
          query <- paste0(
            "SELECT * FROM read_parquet('",
            pq_file,
            "', file_row_number = true) ",
            "WHERE file_row_number IN (",
            row_filter,
            ")"
          )
          tryCatch(
            DBI::dbGetQuery(worker_con, query),
            error = function(e) {
              warning("Failed to read from ", pq_file, ": ", e$message)
              data.frame()
            }
          )
        }

        p()
        result
      }
    )
  }, handlers = progressr::handler_cli())

  if (!is.null(output)) {
    total <- sum(unlist(results))
    message("Written ", total, " records to ", output)
    return(invisible(output))
  }

  ## Combine results (in-memory mode)
  result <- do.call(rbind, results)

  ## Remove the file_row_number column we added for filtering
  if ("file_row_number" %in% names(result)) {
    result$file_row_number <- NULL
  }

  message("Retrieved ", nrow(result), " records")

  return(result)
}
