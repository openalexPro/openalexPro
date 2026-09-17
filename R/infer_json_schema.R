#' Infer unified JSON schema using DuckDB
#'
#' Infers the schema of each JSON/NDJSON file individually via DuckDB's
#' `read_json_auto()` and merges the results using type-widening rules.
#' Processing files one at a time avoids the out-of-memory errors that occur
#' when opening all files in a single DuckDB query.
#'
#' The returned columns clause can be passed directly to
#' `read_json(..., columns = <result>)` or
#' `read_json_auto(..., columns = <result>)` in subsequent DuckDB queries to
#' enforce a consistent schema across all files.
#'
#' @section Caching:
#' When `schema_cache_dir` is provided, two levels of caching apply:
#' - **Unified schema** (`unified_schema.csv`): if present, loaded and returned
#'   immediately — no DuckDB queries needed. Delete this file to force
#'   re-inference.
#' - **Per-file schemas** (`<update_date>_<part_name>.csv`): each file's schema
#'   is saved as it is inferred. On restart, already-cached files are skipped,
#'   enabling mid-run resume for large file sets.
#'
#' @section Type-widening rules:
#' When a column has different types across files, the unified type is chosen
#' by these rules (in order):
#' 1. All identical → keep as-is.
#' 2. Any `STRUCT`/`LIST`/`MAP` vs simpler type → complex type wins.
#' 3. Multiple `STRUCT` types → pick the one with the most fields.
#' 4. Numeric conflicts → widest type wins
#'    (`TINYINT < SMALLINT < INTEGER < BIGINT < HUGEINT < FLOAT < DOUBLE`).
#' 5. Fallback → `VARCHAR`.
#'
#' @param con An active DuckDB connection (`DBI::dbConnect(duckdb::duckdb())`)
#'   with the JSON extension loaded (`LOAD json`).
#' @param files Character vector of paths to JSON or NDJSON (`.gz`) files.
#' @param sample_size Number of files to sample for schema inference.
#'   Higher values give more accurate schemas but take longer. Use `0` or
#'   `NULL` to use all files. Default is `20`.
#' @param extra_options Additional options appended to the `read_json_auto`
#'   SQL call, e.g. `", maximum_object_size=1000000000"` for large JSON
#'   objects. Default is `""`.
#' @param verbose If `TRUE`, print progress messages and a progress bar.
#'   Default is `TRUE`.
#' @param schema_cache_dir Path to a directory for caching per-file and unified
#'   schemas. The directory is created if it does not exist. `NULL` (default)
#'   disables caching.
#'
#' @return A DuckDB columns clause string (e.g.
#'   \code{"{'col1': 'VARCHAR', 'col2': 'BIGINT', ...}"}) suitable for use as
#'   the `columns` argument to `read_json()`. Returns `NULL` if schema
#'   inference fails for all files.
#'
#' @importFrom utils read.csv write.csv
#'
#' @seealso [snapshot_to_parquet()] which uses this function internally.
#'
#' @examples
#' \dontrun{
#' con <- DBI::dbConnect(duckdb::duckdb())
#' DBI::dbExecute(con, "LOAD json")
#' files <- list.files("path/to/snapshot/works", pattern = "\\.gz$",
#'                     recursive = TRUE, full.names = TRUE)
#' schema <- infer_json_schema(con, files, sample_size = 50,
#'                             schema_cache_dir = "path/to/cache")
#' DBI::dbDisconnect(con, shutdown = TRUE)
#' # schema is now a string like: {'id': 'VARCHAR', 'title': 'VARCHAR', ...}
#' }
#'
#' @export
infer_json_schema <- function(
  con,
  files,
  sample_size = 20,
  extra_options = "",
  verbose = TRUE,
  schema_cache_dir = NULL
) {
  if (length(files) == 0) {
    if (verbose) message("No files provided for schema inference.")
    return(NULL)
  }

  # Ensure cache dir exists ----
  if (!is.null(schema_cache_dir)) {
    dir.create(schema_cache_dir, recursive = TRUE, showWarnings = FALSE)

    # Level 1: unified schema cache ----
    unified_cache <- file.path(schema_cache_dir, "unified_schema.csv")
    if (file.exists(unified_cache)) {
      unified <- read.csv(unified_cache, stringsAsFactors = FALSE)
      if (verbose) {
        message(
          "Loaded cached unified schema with ", nrow(unified), " columns",
          " (delete ", unified_cache, " to re-infer)"
        )
      }
      col_defs <- paste0("'", unified$col_name, "': '", unified$col_type, "'")
      return(paste0("{", paste(col_defs, collapse = ", "), "}"))
    }
  }

  # Sample files if requested ----
  if (!is.null(sample_size) && sample_size > 0 && length(files) > sample_size) {
    files <- sample(files, sample_size)
  }

  if (verbose) message("Inferring unified schema from ", length(files), " files...")

  # Level 2: per-file schema inference with per-file caching ----
  schemas <- vector("list", length(files))

  # Use cli directly for in-place progress in a sequential for loop.
  # progressr + handler_cli is designed for async/future contexts and does not
  # update in place in a plain for loop. ----
  if (verbose) {
    pb <- cli::cli_progress_bar(total = length(files), .envir = environment())
  }

  for (i in seq_along(files)) {
    f <- files[i]
    if (verbose) cli::cli_progress_update(id = pb, .envir = environment())

    # Check per-file cache ----
    if (!is.null(schema_cache_dir)) {
      update_date <- sub("^updated_date=", "", basename(dirname(f)))
      part_name   <- sub("\\.gz$", "", basename(f))
      cache_file  <- file.path(schema_cache_dir, paste0(update_date, "_", part_name, ".csv"))
      if (file.exists(cache_file)) {
        schemas[[i]] <- read.csv(cache_file, stringsAsFactors = FALSE)
        next
      }
    }

    # Run single-file DESCRIBE ----
    # ignore_errors=true skips records with malformed JSON (e.g. duplicate
    # struct field names in OpenAlex works data) so schema inference succeeds.
    schema_sql <- sprintf(
      "DESCRIBE SELECT * FROM read_json_auto(['%s'], union_by_name = true, ignore_errors=true%s)",
      f,
      extra_options
    )
    schemas[[i]] <- tryCatch(
      DBI::dbGetQuery(con, schema_sql),
      error = function(e) {
        if (verbose) message("Schema inference failed for ", basename(f), ": ", e$message)
        NULL
      }
    )

    # Save per-file cache ----
    if (!is.null(schema_cache_dir) && !is.null(schemas[[i]])) {
      write.csv(schemas[[i]], cache_file, row.names = FALSE)
    }
  }

  if (verbose) cli::cli_progress_done(id = pb, .envir = environment())

  # Remove failed inferences ----
  schemas <- Filter(Negate(is.null), schemas)

  if (length(schemas) == 0) {
    if (verbose) message("Could not infer schema from any file.")
    return(NULL)
  }

  # Merge per-file schemas ----
  unified <- merge_schemas(schemas)

  if (is.null(unified) || nrow(unified) == 0) {
    return(NULL)
  }

  if (verbose) {
    message("Unified schema inferred with ", nrow(unified), " columns")
  }

  # Save unified schema cache ----
  if (!is.null(schema_cache_dir)) {
    write.csv(unified, unified_cache, row.names = FALSE)
  }

  # Build columns clause ----
  col_defs <- paste0("'", unified$col_name, "': '", unified$col_type, "'")
  paste0("{", paste(col_defs, collapse = ", "), "}")
}


#' Merge per-file DuckDB DESCRIBE schemas using type-widening rules
#'
#' @param schemas List of data frames from DuckDB DESCRIBE output, each with
#'   column name and type columns (named `column_name`/`name` and
#'   `column_type`/`type` depending on DuckDB version).
#'
#' @return Data frame with columns `col_name` and `col_type` representing the
#'   unified schema.
#'
#' @details Type-widening precedence for conflicting types on the same column:
#' 1. Identical types → keep as-is.
#' 2. Any STRUCT/LIST/MAP vs simpler type → use the complex type.
#' 3. Multiple STRUCT types → use the one with the most fields.
#' 4. Pure numeric conflicts → use the widest numeric type
#'    (`TINYINT < SMALLINT < INTEGER < BIGINT < HUGEINT < FLOAT < DOUBLE`).
#' 5. Fallback → `VARCHAR`.
#'
#' @noRd
merge_schemas <- function(schemas) {
  # Numeric type widening order (higher index = wider) ----
  numeric_order <- c(
    "TINYINT", "SMALLINT", "INTEGER", "INT", "BIGINT",
    "HUGEINT", "FLOAT", "DOUBLE"
  )

  # Normalise column name differences between DuckDB versions ----
  schemas <- lapply(schemas, function(df) {
    nms <- names(df)
    data.frame(
      col_name = df[[if ("column_name" %in% nms) "column_name" else "name"]],
      col_type  = df[[if ("column_type" %in% nms) "column_type" else "type"]],
      stringsAsFactors = FALSE
    )
  })

  all_cols <- do.call(rbind, schemas)

  # Preserve first-seen column order ----
  ordered_names <- unique(all_cols$col_name)

  widen_type <- function(types) {
    u <- unique(types)
    if (length(u) == 1L) return(u)

    # Prefer STRUCT/LIST/MAP over simple types ----
    complex <- grep("^STRUCT|^LIST|^MAP", u, value = TRUE)
    if (length(complex) == 1L) return(complex)
    if (length(complex) > 1L) {
      # Pick the STRUCT with the most fields ----
      field_counts <- vapply(complex, function(t) {
        inner <- sub("^STRUCT\\((.*)\\)$", "\\1", t)
        nchar(inner) - nchar(gsub(",", "", inner)) + 1L
      }, integer(1))
      return(complex[[which.max(field_counts)]])
    }

    # Numeric widening ----
    ranks <- match(toupper(u), numeric_order)
    if (!all(is.na(ranks))) {
      return(numeric_order[max(ranks, na.rm = TRUE)])
    }

    # Fallback ----
    "VARCHAR"
  }

  widened_types <- vapply(
    ordered_names,
    function(cn) widen_type(all_cols$col_type[all_cols$col_name == cn]),
    character(1),
    USE.NAMES = FALSE
  )

  data.frame(
    col_name = ordered_names,
    col_type  = widened_types,
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}


#' Convert a single JSON/NDJSON file to Parquet using DuckDB
#'
#' Creates a per-worker DuckDB connection, reads one input file, and writes
#' one `.parquet` output file. Designed to be called from [future.apply::future_lapply()]
#' where each worker needs its own isolated connection.
#'
#' @param input_file Path to the input file (`.json`, `.gz`, etc.).
#' @param output_file Full path for the output `.parquet` file.
#'   Parent directories are created automatically.
#' @param columns_clause DuckDB columns clause from [infer_json_schema()],
#'   or `NULL` to use `read_json_auto()`.
#' @param extra_options Additional `read_json`/`read_json_auto` options string,
#'   e.g. `", maximum_object_size=1000000000"`. Default is `""`.
#' @param memory_limit DuckDB memory limit (e.g., `"8GB"`), or `NULL`.
#' @param temp_directory DuckDB temp directory, or `NULL`.
#'
#' @return The path to the created parquet file (`output_file`).
#' @noRd
convert_json_to_parquet <- function(
  input_file,
  output_file,
  columns_clause = NULL,
  extra_options = "",
  memory_limit = NULL,
  temp_directory = NULL
) {
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)

  # Falls back to a private spill directory when the caller names none: the
  # DuckDB default is `.tmp` relative to the working directory, which
  # concurrent workers would share and corrupt.
  con <- .pro_con(
    memory_limit = memory_limit,
    temp_dir = temp_directory %||% .pro_temp_dir(basename(output_file)),
    json = TRUE
  )
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  # Build read function ----
  read_fn <- if (!is.null(columns_clause)) {
    sprintf("read_json('%s', columns = %s%s)", input_file, columns_clause, extra_options)
  } else {
    sprintf("read_json_auto('%s'%s)", input_file, extra_options)
  }

  sql <- sprintf(
    "COPY (SELECT * FROM %s) TO '%s' (FORMAT PARQUET, COMPRESSION SNAPPY, ROW_GROUP_SIZE 100000)",
    read_fn,
    output_file
  )

  DBI::dbExecute(conn = con, sql)
  output_file
}
