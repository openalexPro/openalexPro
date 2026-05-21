# snapshot_to_parquet -----------------------------------------------------------
#
# Pure-R implementation. Both snapshot_to_parquet() and snapshot_to_parquet_R()
# share the same argument signature and implementation; the _R suffix is kept as
# an alias for environments that relied on the previous naming convention.

#' Convert OA snapshot to Parquet format
#'
#' Converts OpenAlex snapshot \code{.json.gz} files to Parquet using DuckDB.
#' Paths can be supplied as a single \code{root_dir} (which derives
#' \code{snapshot_dir} and \code{parquet_dir} automatically) or as explicit
#' \code{snapshot_dir} and \code{parquet_dir} arguments.
#'
#' @param root_dir Root directory. If provided, \code{snapshot_dir} defaults to
#'   \code{<root_dir>/openalex-snapshot} and \code{parquet_dir} defaults to
#'   \code{<root_dir>/parquet}.
#' @param data_sets Character vector of dataset names to convert (e.g.
#'   \code{c("works", "authors")}). \code{NULL} converts all datasets found
#'   under \code{<snapshot_dir>/data/}.
#' @param workers Number of parallel workers for file conversion via
#'   [future.apply::future_lapply()]. Default is \code{NULL} (sequential).
#' @param sample_size Number of \code{.gz} files to sample for unified schema
#'   inference. Higher values give more accurate schemas but take longer.
#'   Default is \code{20}. Use \code{NULL} or \code{0} to use all files.
#' @param memory_limit DuckDB memory limit per worker (e.g., \code{"8GB"}).
#'   Default is \code{NULL} (DuckDB default).
#' @param temp_directory Location of the temporary directory for DuckDB.
#'   Passed to each worker's DuckDB connection. Default is \code{NULL}
#'   (system default).
#' @param progress Show progress bars. Default is \code{TRUE}.
#' @param verbose Print per-dataset progress messages. Default is \code{TRUE}.
#' @param snapshot_dir Explicit path to the snapshot data directory (the one
#'   containing a \code{data/} subfolder). Required when \code{root_dir} is not
#'   provided.
#' @param parquet_dir Explicit path to the Parquet output directory. Required
#'   when \code{root_dir} is not provided.
#'
#' @return Invisibly returns \code{NULL}.
#'
#' @seealso [snapshot_to_parquet_R()] (identical function, alternative name),
#'   [build_corpus_index()] for indexing the resulting Parquet files.
#'
#' @importFrom DBI dbConnect dbDisconnect dbExecute
#' @importFrom duckdb duckdb
#' @importFrom future plan multisession
#' @importFrom future.apply future_lapply
#' @importFrom progressr with_progress progressor handler_cli
#'
#' @examples
#' \dontrun{
#' snapshot_to_parquet(root_dir = "/Volumes/openalex")
#'
#' snapshot_to_parquet(
#'   root_dir     = "/Volumes/openalex",
#'   data_sets    = c("authors", "works"),
#'   workers      = 4,
#'   memory_limit = "8GB"
#' )
#'
#' # Explicit paths (no root_dir):
#' snapshot_to_parquet(
#'   snapshot_dir = "/data/openalex-snapshot",
#'   parquet_dir  = "/data/parquet",
#'   data_sets    = "authors"
#' )
#' }
#'
#' @export
#' @md
snapshot_to_parquet <- function(
  root_dir       = NULL,
  data_sets      = NULL,
  workers        = NULL,
  sample_size    = 20,
  memory_limit   = NULL,
  temp_directory = NULL,
  progress       = TRUE,
  verbose        = TRUE,
  snapshot_dir   = NULL,
  parquet_dir    = NULL
) {
  # Resolve paths from root_dir if provided ------------------------------------
  if (!is.null(root_dir)) {
    snapshot_dir <- file.path(root_dir, "openalex-snapshot")
    parquet_dir  <- file.path(root_dir, "parquet")
  }
  if (is.null(snapshot_dir) || is.null(parquet_dir)) {
    stop(
      "Provide either `root_dir` or both `snapshot_dir` and `parquet_dir`.",
      call. = FALSE
    )
  }

  # Enumerate datasets ---------------------------------------------------------
  if (is.null(data_sets)) {
    data_sets <- list.dirs(
      file.path(snapshot_dir, "data"),
      recursive  = FALSE,
      full.names = FALSE
    )
    data_sets <- data_sets[data_sets != "merged_ids"]
  }

  dir.create(parquet_dir, recursive = TRUE, showWarnings = FALSE)
  # Prevent macOS Spotlight from indexing parquet files
  file.create(file.path(parquet_dir, ".metadata_never_index"))

  # Set up parallel plan if workers > 1 ----------------------------------------
  if (!is.null(workers) && workers > 1) {
    oldPlan <- future::plan(future::multisession, workers = workers)
    on.exit(future::plan(oldPlan), add = TRUE)
  }

  # Per-dataset conversion ------------------------------------------------------
  for (data_set in data_sets) {
    parquet_ds <- file.path(parquet_dir, data_set)
    json_dir   <- file.path(snapshot_dir, "data", data_set)

    if (isTRUE(verbose)) message("Processing ", data_set, " ...")
    ds_start <- Sys.time()

    # Enumerate all .gz files
    gz_files <- list.files(
      json_dir,
      pattern    = "\\.gz$",
      recursive  = TRUE,
      full.names = TRUE
    )

    if (length(gz_files) == 0) {
      warning(
        "No .gz files found for '", data_set, "', skipping.",
        call. = FALSE
      )
      next
    }

    # Relative paths from json_dir (forward-slash normalised for cross-platform
    # consistency with list.files() output)
    json_dir_norm <- normalizePath(json_dir)
    rel_paths <- vapply(gz_files, function(f) {
      gsub("\\\\", "/", substring(normalizePath(f), nchar(json_dir_norm) + 2L))
    }, character(1L), USE.NAMES = FALSE)

    # Resume support: skip already-converted files
    dir.create(parquet_ds, recursive = TRUE, showWarnings = FALSE)
    existing_parquets <- gsub("\\\\", "/", list.files(
      parquet_ds,
      pattern    = "\\.parquet$",
      recursive  = TRUE,
      full.names = FALSE
    ))
    expected_parquets <- sub("\\.gz$", ".parquet", rel_paths)
    todo_mask         <- !(expected_parquets %in% existing_parquets)
    skipped           <- sum(!todo_mask)
    if (skipped > 0L) {
      message("  Skipping ", skipped, " already converted file(s)")
    }
    gz_files     <- gz_files[todo_mask]
    output_files <- file.path(parquet_ds, expected_parquets[todo_mask])

    if (length(gz_files) == 0L) {
      message("  All files already converted.")
      next
    }

    if (isTRUE(verbose)) message("  Converting ", length(gz_files), " file(s)...")

    # Works need a larger max object size for very long abstracts
    ndjson_options <- if (data_set == "works") {
      ", maximum_object_size=1000000000"
    } else {
      ""
    }

    # Stage 1: Infer unified schema
    con <- DBI::dbConnect(duckdb::duckdb(), read_only = FALSE)
    DBI::dbExecute(conn = con, "INSTALL json; LOAD json;")
    if (!is.null(memory_limit)) {
      DBI::dbExecute(conn = con, paste0("SET memory_limit = '", memory_limit, "'"))
    }
    if (!is.null(temp_directory)) {
      DBI::dbExecute(conn = con, paste0("SET temp_directory = '", temp_directory, "'"))
    }
    columns_clause <- infer_json_schema(
      con              = con,
      files            = gz_files,
      sample_size      = sample_size,
      extra_options    = ndjson_options,
      verbose          = isTRUE(verbose),
      schema_cache_dir = file.path(parquet_ds, ".schema_cache")
    )
    DBI::dbDisconnect(con, shutdown = TRUE)

    # Works: read abstract_inverted_index as raw VARCHAR to avoid DuckDB's
    # case-folding collision on duplicate JSON keys ("as" vs "As")
    if (data_set == "works" && !is.null(columns_clause)) {
      columns_clause <- gsub(
        "'abstract_inverted_index':\\s*'[^']*'",
        "'abstract_inverted_index': 'VARCHAR'",
        columns_clause
      )
      if (isTRUE(verbose)) {
        message("  Storing 'abstract_inverted_index' as VARCHAR (raw JSON string)")
      }
    }

    # Stage 2: Per-file conversion (parallel if workers > 1)
    progressr::with_progress(
      {
        p <- progressr::progressor(along = gz_files)
        future.apply::future_lapply(seq_along(gz_files), function(i) {
          result <- convert_json_to_parquet(
            input_file     = gz_files[i],
            output_file    = output_files[i],
            columns_clause = columns_clause,
            extra_options  = ndjson_options,
            memory_limit   = memory_limit,
            temp_directory = temp_directory
          )
          p()
          result
        })
      },
      handlers = progressr::handler_cli()
    )

    if (isTRUE(verbose)) {
      message(
        "  done after ",
        round(difftime(Sys.time(), ds_start, units = "secs"), 2),
        " seconds"
      )
    }
  }

  invisible(NULL)
}


#' Convert OA snapshot to Parquet format (pure-R implementation)
#'
#' Alias for [snapshot_to_parquet()]. Retained so code that referenced the
#' previous \code{snapshot_to_parquet_R()} name continues to work without
#' modification. Both functions share the same arguments and implementation.
#'
#' @inheritParams snapshot_to_parquet
#'
#' @return Invisibly returns \code{NULL}.
#'
#' @seealso [snapshot_to_parquet()]
#'
#' @export
#' @md
snapshot_to_parquet_R <- snapshot_to_parquet
