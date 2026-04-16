# snapshot_to_parquet -----------------------------------------------------------
#
# Two implementations are provided:
#   snapshot_to_parquet()   — thin wrapper around the openalex-snapshot binary
#   snapshot_to_parquet_R() — pure R / DuckDB fallback (original implementation)

# snapshot_to_parquet (binary wrapper) -----------------------------------------

#' Convert OA snapshot to Parquet format via openalex-snapshot
#'
#' Delegates conversion of OpenAlex snapshot `.json.gz` files to Parquet to the
#' external \code{openalex-snapshot} binary (the companion Rust CLI tool).
#' The binary derives all paths from a single root directory:
#' \describe{
#'   \item{\code{<root_dir>/openalex-snapshot/}}{Source snapshot data}
#'   \item{\code{<root_dir>/parquet/}}{Parquet output}
#'   \item{\code{<root_dir>/.openalex-snapshot_metadata/}}{Logs, schema cache, reports}
#' }
#'
#' The pure-R fallback implementation is available as [snapshot_to_parquet_R()].
#'
#' @param root_dir Root directory containing the snapshot and parquet
#'   subdirectories (see Details).
#' @param data_sets Character vector of dataset names to convert (e.g.
#'   \code{c("works", "authors")}). \code{NULL} converts all datasets.
#' @param workers Number of parallel worker threads. \code{NULL} uses the
#'   binary's default (4).
#' @param profile Performance/memory profile: \code{"safe"}, \code{"balanced"}
#'   (default), or \code{"fast"}.
#' @param max_memory_mb Optional per-worker memory cap in MB.
#' @param sample_size Number of source files to sample for schema inference.
#'   Default is \code{100}.
#' @param refresh_cache If \code{TRUE}, forces re-inference of the schema
#'   (ignores cached schema). Default is \code{FALSE}.
#' @param progress Show progress bars. Default is \code{TRUE}.
#' @param oas_bin Path to the \code{openalex-snapshot} binary. If \code{NULL}
#'   (default), checks \code{getOption("openalexPro.oas_bin")} then PATH.
#'
#' @return Invisibly returns \code{root_dir}.
#'
#' @seealso [snapshot_to_parquet_R()] for the pure-R fallback,
#'   [build_corpus_index()] for indexing the resulting Parquet files.
#'
#' @examples
#' \dontrun{
#' snapshot_to_parquet(root_dir = "/Volumes/openalex")
#'
#' snapshot_to_parquet(
#'   root_dir  = "/Volumes/openalex",
#'   data_sets = c("authors", "works"),
#'   workers   = 4,
#'   profile   = "safe"
#' )
#' }
#'
#' @importFrom cli cli_abort
#' @importFrom rlang caller_env
#' @export
#' @md
snapshot_to_parquet <- function(
  root_dir,
  data_sets     = NULL,
  workers       = NULL,
  profile       = c("balanced", "safe", "fast"),
  max_memory_mb = NULL,
  sample_size   = 100L,
  refresh_cache = FALSE,
  progress      = TRUE,
  oas_bin       = NULL
) {
  profile <- match.arg(profile)

  datasets_to_run <- if (is.null(data_sets)) "all" else data_sets

  for (ds in datasets_to_run) {
    args <- c(
      "convert",
      "--root-dir",    root_dir,
      "--dataset",     ds,
      "--profile",     profile,
      "--sample-size", as.integer(sample_size)
    )
    if (!is.null(workers))       args <- c(args, "--workers",        as.integer(workers))
    if (!is.null(max_memory_mb)) args <- c(args, "--max-memory-mb",  as.integer(max_memory_mb))
    if (isTRUE(refresh_cache))   args <- c(args, "--refresh-cache")
    if (!isTRUE(progress))       args <- c(args, "--no-progress")

    run_oas(args, oas_bin = oas_bin)
  }

  invisible(root_dir)
}


# snapshot_to_parquet_R (pure-R fallback) --------------------------------------

#' Convert OA snapshot to Parquet format (pure-R implementation)
#'
#' Pure-R / DuckDB implementation of snapshot-to-Parquet conversion. This is
#' the original implementation, preserved as a fallback for environments where
#' the \code{openalex-snapshot} binary is not available.
#'
#' For most users, [snapshot_to_parquet()] (which delegates to the binary) is
#' preferred as it is faster and includes additional features (verification,
#' repair, structured logging).
#'
#' @param snapshot_dir The directory path of the OA snapshot data.
#'   Default is \code{"Volumes/openalex/openalex-snapshot"}.
#' @param parquet_dir The directory path where the Parquet files will be saved.
#'   Default is \code{"Volumes/openalex/parquet"}.
#' @param data_sets A character vector specifying the data sets to process.
#'   Default is \code{NULL}, which processes all data sets.
#' @param sample_size Number of \code{.gz} files to sample for unified schema
#'   inference. Higher values give more accurate schemas but take longer.
#'   Default is \code{20}. Use \code{NULL} or \code{0} to use all files.
#' @param temp_directory Location of the temporary directory for DuckDB.
#'   Passed to each worker's DuckDB connection. Default is \code{NULL}
#'   (system default).
#' @param memory_limit DuckDB memory limit per worker (e.g., \code{"8GB"}).
#'   Default is \code{NULL} (DuckDB default).
#' @param workers Number of parallel workers for file conversion via
#'   [future.apply::future_lapply()]. Default is \code{NULL} (sequential).
#'
#' @return Invisibly returns \code{NULL}.
#'
#' @seealso [snapshot_to_parquet()] for the preferred binary-backed version.
#'
#' @importFrom DBI dbConnect dbDisconnect dbExecute
#' @importFrom duckdb duckdb
#' @importFrom future plan multisession sequential
#' @importFrom future.apply future_lapply
#' @importFrom progressr with_progress progressor handler_cli
#'
#' @examples
#' \dontrun{
#' snapshot_to_parquet_R()
#'
#' snapshot_to_parquet_R(
#'   snapshot_dir = "/path/to/snapshot",
#'   data_sets    = c("authors", "works"),
#'   workers      = 4,
#'   memory_limit = "8GB"
#' )
#' }
#'
#' @export
#' @md
snapshot_to_parquet_R <- function(
  snapshot_dir = file.path("", "Volumes", "openalex", "openalex-snapshot"),
  parquet_dir  = file.path("", "Volumes", "openalex", "parquet"),
  data_sets    = NULL,
  sample_size  = 20,
  temp_directory = NULL,
  memory_limit = NULL,
  workers      = NULL
) {
  if (is.null(data_sets)) {
    data_sets <- list.dirs(
      file.path(snapshot_dir, "data"),
      recursive = FALSE,
      full.names = FALSE
    )
    # Remove merged_ids ----
    data_sets <- data_sets[data_sets != "merged_ids"]
  }

  dir.create(parquet_dir, recursive = TRUE, showWarnings = FALSE)

  # Prevent macOS Spotlight from indexing parquet files ----
  file.create(file.path(parquet_dir, ".metadata_never_index"))

  # Set up parallel plan if workers > 1 ----
  if (!is.null(workers) && workers > 1) {
    oldPlan <- future::plan(future::multisession, workers = workers)
    on.exit(future::plan(oldPlan), add = TRUE)
  }

  for (data_set in data_sets) {
    parquet_ds <- file.path(parquet_dir, data_set)
    json_dir   <- file.path(snapshot_dir, "data", data_set)

    message("Processing ", data_set, " ...")
    ds_start <- Sys.time()

    # Enumerate all .gz files ----
    gz_files <- list.files(
      json_dir,
      pattern   = "\\.gz$",
      recursive = TRUE,
      full.names = TRUE
    )

    if (length(gz_files) == 0) {
      warning(
        "No .gz files found for '", data_set, "', skipping.",
        call. = FALSE
      )
      next
    }

    # Compute relative paths from json_dir.
    # normalizePath() uses \ on Windows; gsub ensures / on all platforms so
    # the %in% comparison with list.files() output is consistent. ----
    json_dir_norm <- normalizePath(json_dir)
    rel_paths <- vapply(gz_files, function(f) {
      gsub("\\\\", "/", substring(normalizePath(f), nchar(json_dir_norm) + 2))
    }, character(1), USE.NAMES = FALSE)

    # Resume support: skip already-converted files ----
    dir.create(parquet_ds, recursive = TRUE, showWarnings = FALSE)
    existing_parquets <- gsub("\\\\", "/", list.files(
      parquet_ds,
      pattern    = "\\.parquet$",
      recursive  = TRUE,
      full.names = FALSE
    ))
    expected_parquets <- sub("\\.gz$", ".parquet", rel_paths)
    todo_mask <- !(expected_parquets %in% existing_parquets)
    skipped <- sum(!todo_mask)
    if (skipped > 0) {
      message("  Skipping ", skipped, " already converted file(s)")
    }
    gz_files     <- gz_files[todo_mask]
    output_files <- file.path(parquet_ds, expected_parquets[todo_mask])

    if (length(gz_files) == 0) {
      message("  All files already converted.")
      next
    }

    message("  Converting ", length(gz_files), " file(s)...")

    # Stage 1: Infer unified schema ----
    ndjson_options <- if (data_set == "works") {
      ", maximum_object_size=1000000000"
    } else {
      ""
    }

    con <- DBI::dbConnect(duckdb::duckdb(), read_only = FALSE)
    DBI::dbExecute(conn = con, "INSTALL json; LOAD json;")
    if (!is.null(memory_limit)) {
      DBI::dbExecute(conn = con, paste0("SET memory_limit = '", memory_limit, "'"))
    }
    if (!is.null(temp_directory)) {
      DBI::dbExecute(conn = con, paste0("SET temp_directory = '", temp_directory, "'"))
    }
    columns_clause <- infer_json_schema(
      con            = con,
      files          = gz_files,
      sample_size    = sample_size,
      extra_options  = ndjson_options,
      verbose        = TRUE,
      schema_cache_dir = file.path(parquet_ds, ".schema_cache")
    )
    DBI::dbDisconnect(con, shutdown = TRUE)

    # For works: abstract_inverted_index has duplicate JSON keys ("as" vs "As")
    # that DuckDB case-folds to the same struct field name, causing a collision.
    # Override the type to VARCHAR so DuckDB reads the raw JSON text instead of
    # building a STRUCT, which avoids the collision entirely. ----
    if (data_set == "works" && !is.null(columns_clause)) {
      columns_clause <- gsub(
        "'abstract_inverted_index':\\s*'[^']*'",
        "'abstract_inverted_index': 'VARCHAR'",
        columns_clause
      )
      message("  Storing 'abstract_inverted_index' as VARCHAR (raw JSON string)")
    }

    # Stage 2: Per-file conversion ----
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

    message(
      "  done after ",
      round(difftime(Sys.time(), ds_start, units = "secs"), 2),
      " seconds"
    )
  }

  invisible(NULL)
}
