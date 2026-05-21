# lookup_by_id -----------------------------------------------------------------
#
# Pure-R implementation. Both lookup_by_id() and lookup_by_id_R() share the
# same argument signature and implementation; the _R suffix is kept as an alias
# for environments that relied on the previous naming convention.

#' Look up records by OpenAlex ID
#'
#' Uses a pre-built index (created by [build_corpus_index()]) to locate records
#' efficiently and extract them from the Parquet corpus.
#'
#' Paths can be supplied as a \code{root_dir} + \code{data_sets} pair (which
#' automatically locates the correct index files and writes output into
#' \code{project_dir}) or as an explicit \code{index_file} for direct use.
#'
#' @param root_dir Root directory containing \code{parquet/} and the dataset
#'   indexes produced by [build_corpus_index()]. Index files are expected at
#'   \code{<root_dir>/parquet/<dataset>_id_idx.parquet}.
#' @param ids Character vector of OpenAlex IDs to retrieve. Can be long form
#'   (e.g. \code{"https://openalex.org/W2741809807"}) or short form
#'   (e.g. \code{"W2741809807"}).
#' @param project_dir Project output directory. Extracted Parquet files are
#'   written to \code{<project_dir>/snapshot_extract/<dataset>.parquet}. Only
#'   used when \code{root_dir} is provided.
#' @param data_sets Character vector of dataset names to search (e.g.
#'   \code{c("works", "authors")}). \code{NULL} searches all indexed datasets
#'   under \code{<root_dir>/parquet/}. Ignored when \code{index_file} is
#'   provided.
#' @param workers Number of parallel workers for reading corpus files.
#'   Default is \code{NULL} (sequential).
#' @param progress Show progress bars. Default is \code{TRUE}.
#' @param verbose Print progress messages. Default is \code{TRUE}.
#' @param index_file Explicit path to an index parquet file created by
#'   [build_corpus_index()]. When provided, \code{root_dir}, \code{data_sets},
#'   and \code{project_dir} are ignored.
#' @param selected Path to save the selected index entries as a partitioned
#'   Parquet dataset. Ignored when \code{index_file} is not provided directly.
#'   Default is \code{NULL} (not saved).
#' @param output Path to an output directory for writing results as Parquet
#'   files when using \code{index_file} mode. If \code{NULL} (default),
#'   results are returned as a data frame. Ignored when \code{root_dir} is
#'   used (use \code{project_dir} instead).
#'
#' @return
#' * \code{index_file} mode, \code{output} not \code{NULL}: invisibly returns
#'   \code{output}.
#' * \code{index_file} mode, \code{output} is \code{NULL}: returns a data frame
#'   of matching records.
#' * \code{root_dir} mode: invisibly returns \code{project_dir}.
#'
#' @seealso [lookup_by_id_R()] (identical function, alternative name),
#'   [build_corpus_index()] for building the required index.
#'
#' @importFrom arrow open_dataset write_dataset
#' @importFrom DBI dbConnect dbDisconnect dbGetQuery dbExecute
#' @importFrom dplyr filter collect
#' @importFrom rlang .data
#' @importFrom duckdb duckdb
#' @importFrom future plan multisession
#' @importFrom future.apply future_lapply
#' @importFrom progressr with_progress progressor handler_cli
#'
#' @examples
#' \dontrun{
#' # root_dir mode (searches multiple datasets)
#' lookup_by_id(
#'   root_dir    = "/Volumes/openalex",
#'   ids         = c("W2741809807", "W1234567890"),
#'   project_dir = "my_project",
#'   data_sets   = "works"
#' )
#'
#' # index_file mode (direct access, returns data frame)
#' records <- lookup_by_id(
#'   index_file = "works_id_index.parquet",
#'   ids        = c("W2741809807", "W1234567890")
#' )
#'
#' # index_file mode (write to parquet)
#' lookup_by_id(
#'   index_file = "works_id_index.parquet",
#'   ids        = large_id_vector,
#'   output     = "filtered_works",
#'   workers    = 3
#' )
#' }
#'
#' @export
#' @md
lookup_by_id <- function(
  root_dir    = NULL,
  ids,
  project_dir = NULL,
  data_sets   = NULL,
  workers     = NULL,
  progress    = TRUE,
  verbose     = TRUE,
  index_file  = NULL,
  selected    = NULL,
  output      = NULL
) {
  if (missing(ids) || length(ids) == 0) {
    stop("'ids' must be provided and non-empty.", call. = FALSE)
  }

  # index_file mode: delegate to internal worker directly --------------------
  if (!is.null(index_file)) {
    return(.lookup_one_index(
      index_file = index_file,
      ids        = ids,
      selected   = selected,
      workers    = workers,
      output     = output,
      verbose    = verbose,
      progress   = progress
    ))
  }

  # root_dir mode: iterate over datasets -------------------------------------
  if (is.null(root_dir)) {
    stop(
      "Provide either `root_dir` or `index_file`.",
      call. = FALSE
    )
  }

  parquet_root <- file.path(root_dir, "parquet")

  if (is.null(data_sets)) {
    # Find all index files under parquet_root
    idx_files <- list.files(
      parquet_root,
      pattern    = "_id_idx\\.parquet$",
      full.names = FALSE,
      recursive  = FALSE
    )
    data_sets <- sub("_id_idx\\.parquet$", "", idx_files)
  }

  if (length(data_sets) == 0) {
    stop(
      "No index files found under ", parquet_root,
      ". Run build_corpus_index() first.",
      call. = FALSE
    )
  }

  if (!is.null(project_dir)) {
    dir.create(project_dir, recursive = TRUE, showWarnings = FALSE)
  }

  for (ds in data_sets) {
    idx_path <- file.path(parquet_root, paste0(ds, "_id_idx.parquet"))
    if (!file.exists(idx_path)) {
      if (isTRUE(verbose)) {
        message("No index for dataset '", ds, "', skipping.")
      }
      next
    }

    ds_output <- if (!is.null(project_dir)) {
      file.path(project_dir, paste0("snapshot_extract_", ds))
    } else {
      NULL
    }

    .lookup_one_index(
      index_file = idx_path,
      ids        = ids,
      selected   = NULL,
      workers    = workers,
      output     = ds_output,
      verbose    = verbose,
      progress   = progress
    )
  }

  invisible(project_dir)
}


# Internal worker: look up IDs in a single index file --------------------------
.lookup_one_index <- function(
  index_file,
  ids,
  selected,
  workers,
  output,
  verbose,
  progress
) {
  index_file    <- normalizePath(index_file, mustWork = FALSE)
  snapshot_path <- dirname(index_file)

  if (!file.exists(index_file)) {
    stop("Index file not found: ", index_file, call. = FALSE)
  }

  if (!is.null(output) && dir.exists(output)) {
    stop("Output directory already exists: ", output, call. = FALSE)
  }

  # Normalize IDs to long form
  if (isTRUE(verbose)) message("Normalizing ids to long form ...")
  ids <- ifelse(
    grepl("^https://openalex.org/", ids),
    ids,
    paste0("https://openalex.org/", ids)
  )

  if (isTRUE(verbose)) message("Looking up ", length(ids), " ...")

  # Query the index
  matches <- index_file |>
    arrow::open_dataset() |>
    dplyr::filter(.data$id %in% ids) |>
    dplyr::collect()

  if (is.null(matches) || nrow(matches) == 0) {
    message("No matching records found in index")
    if (!is.null(output)) return(invisible(output))
    return(data.frame())
  }

  if (isTRUE(verbose)) message("Found ", nrow(matches), " matching records in index")

  if (!is.null(selected)) {
    if (isTRUE(verbose)) message("Saving selected ids to ", selected)
    arrow::write_dataset(
      dataset      = matches,
      path         = selected,
      format       = "parquet",
      partitioning = "parquet_file"
    )
  }

  # Set up parallel plan if workers > 1
  if (!is.null(workers) && workers > 1) {
    old_plan <- future::plan(future::multisession, workers = workers)
    on.exit(future::plan(old_plan), add = TRUE)
  }

  if (isTRUE(verbose)) message("Splitting into parquet files ...")
  file_chunks <- split(matches$file_row_number, matches$parquet_file)
  # Normalise to forward slashes so DuckDB receives consistent paths
  names(file_chunks) <- gsub(
    "\\\\", "/",
    file.path(snapshot_path, names(file_chunks))
  )

  if (isTRUE(verbose)) message("Retrieving and saving records per parquet file ...")

  oopts <- options(future.globals.maxSize = 1.0 * 1e9)  # 1.0 GB
  on.exit(options(oopts), add = TRUE)

  if (!is.null(output)) {
    dir.create(output, recursive = TRUE, showWarnings = FALSE)
  }

  progressr::with_progress(
    {
      p <- progressr::progressor(along = file_chunks)
      results <- future.apply::future_lapply(
        names(file_chunks),
        function(pq_file) {
          row_numbers <- file_chunks[[pq_file]]
          row_filter  <- paste(row_numbers, collapse = ", ")

          worker_con <- DBI::dbConnect(duckdb::duckdb(), read_only = TRUE)
          on.exit(DBI::dbDisconnect(worker_con, shutdown = TRUE))

          result <- if (!is.null(output)) {
            out_file   <- file.path(output, paste0("part_", basename(pq_file)))
            copy_query <- paste0(
              "COPY (SELECT * FROM read_parquet('", pq_file,
              "', file_row_number = true) WHERE file_row_number IN (",
              row_filter, ")) ",
              "TO '", out_file, "' (FORMAT PARQUET, COMPRESSION SNAPPY)"
            )
            tryCatch(
              { DBI::dbExecute(worker_con, copy_query); length(row_numbers) },
              error = function(e) {
                warning("Failed to write from ", pq_file, ": ", e$message)
                0L
              }
            )
          } else {
            query <- paste0(
              "SELECT * FROM read_parquet('", pq_file,
              "', file_row_number = true) WHERE file_row_number IN (",
              row_filter, ")"
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
    },
    handlers = progressr::handler_cli()
  )

  if (!is.null(output)) {
    total <- sum(unlist(results))
    message("Written ", total, " records to ", output)
    return(invisible(output))
  }

  result <- do.call(rbind, results)
  if ("file_row_number" %in% names(result)) {
    result$file_row_number <- NULL
  }
  message("Retrieved ", nrow(result), " records")
  result
}


#' Look up records by ID using a pre-built index (pure-R implementation)
#'
#' Alias for [lookup_by_id()]. Retained so code that referenced the previous
#' \code{lookup_by_id_R()} name continues to work without modification.  Both
#' functions share the same arguments and implementation.
#'
#' @inheritParams lookup_by_id
#'
#' @return See [lookup_by_id()].
#'
#' @seealso [lookup_by_id()]
#'
#' @export
#' @md
lookup_by_id_R <- lookup_by_id
