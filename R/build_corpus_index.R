# build_corpus_index -----------------------------------------------------------
#
# Pure-R implementation. Both build_corpus_index() and build_corpus_index_R()
# share the same argument signature and implementation; the _R suffix is kept as
# an alias for environments that relied on the previous naming convention.

#' Build a Parquet ID-lookup index
#'
#' Builds a \code{<dataset>_id_idx.parquet} index from the Parquet corpus
#' produced by [snapshot_to_parquet()], enabling fast record retrieval by
#' OpenAlex ID using [lookup_by_id()].
#'
#' The function is memory-efficient and can handle 300M+ records via a
#' two-stage approach:
#' \enumerate{
#'   \item Index each parquet file individually (bounded memory, optionally
#'         parallel, with resume support).
#'   \item Combine the per-file shard indexes into a single parquet index.
#' }
#'
#' Paths can be supplied as a single \code{root_dir} (which iterates over all
#' requested \code{data_sets}) or as an explicit \code{corpus_dir} pointing to
#' a single dataset directory.
#'
#' @param root_dir Root directory containing a \code{parquet/} subdirectory
#'   produced by [snapshot_to_parquet()]. If provided, the index for each
#'   dataset in \code{data_sets} is created at
#'   \code{<root_dir>/parquet/<dataset>_id_idx.parquet}.
#' @param data_sets Character vector of dataset names to index (e.g.
#'   \code{c("works", "authors")}). \code{NULL} indexes all datasets found
#'   under \code{<root_dir>/parquet/}. Ignored when \code{corpus_dir} is
#'   provided.
#' @param workers Number of parallel workers for Stage 1 indexing.
#'   Default is \code{NULL} (sequential).
#' @param memory_limit DuckDB memory limit (e.g., \code{"20GB"}).
#'   Default is \code{NULL}.
#' @param overwrite If \code{TRUE}, rebuilds existing indexes. Default is
#'   \code{FALSE} (skip if the index already exists).
#' @param verbose Print progress messages. Default is \code{TRUE}.
#' @param corpus_dir Explicit path to a single dataset Parquet directory (e.g.
#'   \code{"/Volumes/openalex/parquet/works"}). The index is written as a
#'   sibling file: \code{<parent>/<basename>_id_idx.parquet}. When this is
#'   provided, \code{root_dir} and \code{data_sets} are ignored.
#'
#' @return When \code{corpus_dir} is provided, invisibly returns the path to the
#'   created index file. When \code{root_dir} is used, invisibly returns
#'   \code{root_dir}.
#'
#' @details The index contains columns:
#' \describe{
#'   \item{id}{The OpenAlex ID}
#'   \item{id_block}{Block number computed as \code{floor(numeric_id / 10000)}}
#'   \item{parquet_file}{Relative path to the Parquet file in the corpus}
#'   \item{file_row_number}{Row number within the file (0-indexed)}
#' }
#'
#' @seealso [build_corpus_index_R()] (identical function, alternative name),
#'   [lookup_by_id()] for ID-based record retrieval.
#'
#' @importFrom DBI dbConnect dbDisconnect dbExecute
#' @importFrom duckdb duckdb
#' @importFrom future plan multisession
#' @importFrom future.apply future_lapply
#' @importFrom progressr with_progress progressor handler_cli
#'
#' @examples
#' \dontrun{
#' build_corpus_index(root_dir = "/Volumes/openalex")
#'
#' build_corpus_index(
#'   root_dir  = "/Volumes/openalex",
#'   data_sets = "works",
#'   workers   = 4
#' )
#'
#' # Single explicit directory:
#' build_corpus_index(
#'   corpus_dir   = "/Volumes/openalex/parquet/works",
#'   memory_limit = "20GB"
#' )
#' }
#'
#' @export
#' @md
build_corpus_index <- function(
  root_dir     = NULL,
  data_sets    = NULL,
  workers      = NULL,
  memory_limit = NULL,
  overwrite    = FALSE,
  verbose      = TRUE,
  corpus_dir   = NULL
) {
  # corpus_dir mode: index a single explicit directory -----------------------
  if (!is.null(corpus_dir)) {
    return(invisible(.build_one_index(
      corpus_dir   = corpus_dir,
      workers      = workers,
      memory_limit = memory_limit,
      overwrite    = overwrite,
      verbose      = verbose
    )))
  }

  # root_dir mode: iterate over datasets -------------------------------------
  if (is.null(root_dir)) {
    stop(
      "Provide either `root_dir` or `corpus_dir`.",
      call. = FALSE
    )
  }

  parquet_root <- file.path(root_dir, "parquet")

  if (is.null(data_sets)) {
    data_sets <- list.dirs(parquet_root, recursive = FALSE, full.names = FALSE)
    # Exclude index files and hidden directories
    data_sets <- data_sets[!grepl("^\\.", data_sets)]
  }

  for (ds in data_sets) {
    .build_one_index(
      corpus_dir   = file.path(parquet_root, ds),
      workers      = workers,
      memory_limit = memory_limit,
      overwrite    = overwrite,
      verbose      = verbose
    )
  }

  invisible(root_dir)
}


# Internal worker: build the index for one corpus directory --------------------
.build_one_index <- function(
  corpus_dir,
  workers,
  memory_limit,
  overwrite,
  verbose
) {
  if (!dir.exists(corpus_dir)) {
    stop("corpus_dir does not exist: ", corpus_dir, call. = FALSE)
  }

  corpus_dir  <- normalizePath(corpus_dir)
  parent_dir  <- dirname(corpus_dir)
  corpus_name <- basename(corpus_dir)
  index_file  <- file.path(parent_dir, paste0(corpus_name, "_id_idx.parquet"))

  if (file.exists(index_file)) {
    if (!isTRUE(overwrite)) {
      message(
        "index_file exists - creation skipped",
        " - delete manually or use overwrite = TRUE to re-create: ",
        index_file
      )
      return(invisible(index_file))
    }
    unlink(index_file)
  }

  con <- DBI::dbConnect(duckdb::duckdb(), read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbExecute(conn = con, "SET preserve_insertion_order = false")
  if (!is.null(memory_limit)) {
    DBI::dbExecute(conn = con, paste0("SET memory_limit = '", memory_limit, "'"))
  }
  if (!is.null(workers)) {
    DBI::dbExecute(conn = con, paste0("SET threads = ", workers))
  }

  if (isTRUE(verbose)) {
    message("Building index from: ", corpus_dir)
    message("    Writing to: ", index_file)
  }

  total_start <- Sys.time()

  # Temporary directory for Stage 1 shard files
  temp_dir <- paste0(index_file, "_tmp")
  dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
  file.create(file.path(temp_dir, ".metadata_never_index"))

  parquet_files <- list.files(
    corpus_dir,
    pattern    = "\\.parquet$",
    recursive  = TRUE,
    full.names = TRUE
  )

  # Depth used to extract relative paths inside future_lapply without
  # embedding absolute paths (immune to Windows 8.3 short-name mismatches)
  parent_dir_fwd  <- gsub("\\\\", "/", parent_dir)
  parent_depth    <- length(strsplit(parent_dir_fwd, "/")[[1]])

  # Stage 1: index each file individually (parallel)
  if (isTRUE(verbose)) {
    message(
      "Stage 1: Indexing ", length(parquet_files), " parquet files",
      if (!is.null(workers) && workers > 1) paste0(" with ", workers, " workers...") else " sequentially..."
    )
  }

  if (!is.null(workers) && workers > 1) {
    old_plan <- future::plan(future::multisession, workers = workers)
    on.exit(future::plan(old_plan), add = TRUE)
  }

  progressr::with_progress({
    p <- progressr::progressor(along = parquet_files)

    future.apply::future_lapply(seq_along(parquet_files), function(i) {
      pf       <- parquet_files[i]
      out_file <- file.path(temp_dir, paste0("idx_", sprintf("%05d", i), ".parquet"))

      # Resume support
      if (file.exists(out_file)) {
        p()
        return(invisible(NULL))
      }

      worker_con <- DBI::dbConnect(duckdb::duckdb(), read_only = FALSE)
      on.exit(DBI::dbDisconnect(worker_con, shutdown = TRUE))
      DBI::dbExecute(conn = worker_con, "SET threads = 1")
      DBI::dbExecute(conn = worker_con, "SET preserve_insertion_order = false")
      if (!is.null(memory_limit)) {
        DBI::dbExecute(
          conn = worker_con,
          paste0("SET memory_limit = '", memory_limit, "'")
        )
      }

      # Relative path from parent_dir using component depth
      pf_parts <- strsplit(gsub("\\\\", "/", pf), "/")[[1]]
      rel_path <- paste(
        pf_parts[seq(parent_depth + 1L, length(pf_parts))],
        collapse = "/"
      )

      stage1_query <- paste0(
        "COPY (",
        "SELECT ",
        "  id, ",
        "  CAST(FLOOR(CAST(regexp_extract(id, '(\\d+)$', 1) AS BIGINT) / 10000) AS INTEGER) ",
        "    AS id_block, ",
        "  '", rel_path, "' AS parquet_file,",
        "  file_row_number ",
        "FROM read_parquet('", pf, "', file_row_number = true)",
        ") TO '", out_file, "' (FORMAT PARQUET, COMPRESSION SNAPPY)"
      )
      DBI::dbExecute(conn = worker_con, stage1_query)
      p()
      invisible(NULL)
    })
  }, handlers = progressr::handler_cli())

  if (isTRUE(verbose)) message("    Stage 1 complete.")

  # Stage 2: combine shard files into a single index
  if (isTRUE(verbose)) message("Stage 2: Combining into single index file ", index_file)

  copy_query <- paste0(
    "COPY (SELECT * FROM read_parquet('", temp_dir, "'))",
    " TO '", index_file, "' (FORMAT PARQUET, COMPRESSION SNAPPY)"
  )
  DBI::dbExecute(con, copy_query)

  unlink(temp_dir, recursive = TRUE)

  if (isTRUE(verbose)) {
    total_size   <- sum(file.info(index_file)$size)
    file_size_gb <- round(total_size / 1024^3, 2)
    message("Done! Index size: ", file_size_gb, " GB")
    message(
      "Total time: ",
      round(difftime(Sys.time(), total_start, units = "mins"), 2),
      " minutes"
    )
  }

  invisible(index_file)
}


#' Build a Parquet ID-lookup index (pure-R implementation)
#'
#' Alias for [build_corpus_index()]. Retained so code that referenced the
#' previous \code{build_corpus_index_R()} name continues to work without
#' modification. Both functions share the same arguments and implementation.
#'
#' @inheritParams build_corpus_index
#'
#' @return When \code{corpus_dir} is provided, invisibly returns the path to the
#'   created index file. When \code{root_dir} is used, invisibly returns
#'   \code{root_dir}.
#'
#' @seealso [build_corpus_index()]
#'
#' @export
#' @md
build_corpus_index_R <- build_corpus_index
