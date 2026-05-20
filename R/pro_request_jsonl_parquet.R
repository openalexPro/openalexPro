#' Convert JSON files to Apache Parquet files
#'
#' The function takes a directory of JSONL files as written from a call to
#' `pro_request_jsonl(...)` and converts each file individually to a Parquet file.
#' The subfolder structure from the input is preserved in the output, so files
#' in `Chunk_1/` will be written to `Chunk_1/` in the output directory.
#'
#' The `page` column (added by [pro_request_jsonl()]) is preserved as a regular
#' column in the Parquet data.
#'
#' When starting the conversion, a file `00_in.progress` is created which is
#' deleted upon completion.
#'
#' @param input_jsonl The directory of JSON files returned from
#'   `pro_request(..., json_dir = "FOLDER")`.
#' @param output output directory for the parquet dataset; default: temporary
#'   directory.
#' @param overwrite Logical indicating whether to overwrite `output`.
#' @param verbose Logical indicating whether to show verbose information.
#'   Defaults to `TRUE`
#' @param delete_input Determines if the `input_jsonl` should be deleted
#'   afterwards. Defaults to `FALSE`.
#' @param sample_size Number of records to sample from each file when inferring
#'   the unified schema. Higher values give more accurate schema inference but
#'   use more memory. Default is 1000. Set to -1 to read all records (may be slow
#'   for large files).
#' @param workers Number of parallel workers for file conversion via
#'   [future.apply::future_lapply()]. Default is `NULL` (sequential processing).
#'
#' @return The function returns the output path invisibly.
#'
#' @details The function uses DuckDB to read the JSON files and to create the
#'   Apache Parquet files. Each JSON file is converted individually using its own
#'   DuckDB connection, which enables parallel processing via
#'   [future.apply::future_lapply()].
#'
#'   To ensure consistent schemas across all Parquet files, the function first
#'   infers a unified schema by sampling records from all JSONL files. This
#'   prevents type mismatches (e.g., a column being `struct` in one file but
#'   `string` in another) that would cause errors when reading the combined
#'   Parquet dataset.
#'
#' @importFrom duckdb duckdb
#' @importFrom DBI dbConnect dbDisconnect dbExecute dbGetQuery
#' @importFrom future plan multisession sequential
#' @importFrom future.apply future_lapply
#' @importFrom progressr with_progress progressor handler_cli
#'
#' @md
#'
#' @export

pro_request_jsonl_parquet <- function(
  input_jsonl = NULL,
  output = NULL,
  overwrite = FALSE,
  verbose = TRUE,
  delete_input = FALSE,
  sample_size = 1000,
  workers = NULL
) {
  .Deprecated(
    new = "pro_request_parquet",
    msg = paste0(
      "`pro_request_jsonl()` + `pro_request_jsonl_parquet()` are deprecated.\n",
      "Use `pro_request_parquet()` instead: it converts JSON directly to Parquet\n",
      "in one step with no intermediate JSONL files on disk."
    )
  )

  # Argument Checks --------------------------------------------------------

  if (is.null(input_jsonl)) {
    stop("No `input_jsonl` to convert specified!")
  }

  if (is.null(output)) {
    stop("No output to convert to specified!")
  }

  # Preparations -----------------------------------------------------------

  if (file.exists(output)) {
    if (!(overwrite)) {
      stop(
        "output ",
        output,
        " exists.\n",
        "Either specify `overwrite = TRUE` or delete it."
      )
    } else {
      unlink(
        output,
        recursive = TRUE,
        force = TRUE
      )
    }
  }
  dir.create(
    output,
    recursive = TRUE,
    showWarnings = FALSE
  )
  progress_file <- file.path(output, "00_in.progress")
  file.create(progress_file)
  success <- FALSE
  on.exit(
    {
      if (isTRUE(success)) {
        unlink(progress_file)
      }
    },
    add = TRUE
  )

  # Read names of json files ----
  jsons <- list.files(
    input_jsonl,
    pattern = "*.json$",
    full.names = TRUE,
    recursive = TRUE
  )

  jsons <- jsons[
    order(
      as.numeric(
        sub(
          ".*_([0-9]+)\\.json$",
          "\\1",
          jsons
        )
      )
    )
  ]

  if (length(jsons) == 0) {
    stop("No JSON files found in `input_jsonl`!")
  }

  types <- jsons |>
    basename() |>
    strsplit(split = "_") |>
    vapply(
      FUN = '[[',
      1,
      FUN.VALUE = character(1)
    ) |>
    unique()

  if (length(types) > 1) {
    stop("All JSON files must be of the same type!")
  }

  if (types == "group") {
    types <- "group_by"
  }

  # Infer unified schema from all JSONL files ------------------------------
  con <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbExecute(conn = con, "INSTALL json; LOAD json;")

  sample_opt <- if (sample_size > 0) {
    sprintf(", sample_size = %d", sample_size)
  } else {
    ""
  }
  columns_clause <- infer_json_schema(
    con = con,
    files = jsons,
    sample_size = NULL,
    extra_options = sample_opt,
    verbose = verbose
  )

  DBI::dbDisconnect(con, shutdown = TRUE)

  # Compute output paths, converting subfolders to hive-partition format.
  # Use path-depth counting rather than string comparison of absolute paths.
  # On Windows, normalizePath() can return 8.3 short names (e.g. RUNNER~1)
  # for some calls and long names (runneradmin) for others, so comparing
  # dirname(normalizePath(f)) == normalizePath(input_jsonl) is unreliable.
  # Counting components is immune to this because 8.3 and long names occupy
  # the same depth in the hierarchy.
  #
  # Hive partition key naming by depth: depth 1 -> "query", depth N -> "query_lN"
  hive_key <- function(depth) if (depth == 1L) "query" else paste0("query_l", depth)

  input_depth <- length(strsplit(gsub("\\\\", "/", input_jsonl), "/")[[1]])
  output_files <- vapply(jsons, function(f) {
    f_parts  <- strsplit(gsub("\\\\", "/", f), "/")[[1]]
    fname    <- sub("\\.json$", ".parquet", basename(f))
    rel_parts <- if (length(f_parts) > input_depth + 1L) {
      f_parts[seq(input_depth + 1L, length(f_parts) - 1L)]
    } else {
      character(0)
    }
    if (length(rel_parts) > 0L) {
      hive_dirs <- mapply(
        function(depth, val) paste0(hive_key(depth), "=", val),
        seq_along(rel_parts), rel_parts
      )
      do.call(file.path, c(list(output), as.list(hive_dirs), list(fname)))
    } else {
      file.path(output, fname)
    }
  }, character(1), USE.NAMES = FALSE)

  # Set up parallel plan ----
  if (!is.null(workers) && workers > 1) {
    oldPlan <- future::plan(future::multisession, workers = workers)
    on.exit(future::plan(oldPlan), add = TRUE)
  }

  # Per-file conversion ----
  progressr::with_progress({
    p <- progressr::progressor(along = jsons)

    future.apply::future_lapply(seq_along(jsons), function(i) {
      result <- convert_json_to_parquet(
        input_file = jsons[i],
        output_file = output_files[i],
        columns_clause = columns_clause,
        extra_options = sample_opt
      )
      p()
      result
    })
  }, handlers = progressr::handler_cli())

  if (delete_input) {
    unlink(input_jsonl, recursive = TRUE, force = TRUE)
  }

  success <- TRUE

  return(invisible(normalizePath(output)))
}
