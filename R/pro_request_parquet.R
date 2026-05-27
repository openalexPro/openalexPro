#' Convert JSON files from pro_request() directly to Apache Parquet
#'
#' Single-step replacement for the two-step
#' `pro_request_jsonl_R()` + `pro_request_jsonl_parquet()` pipeline.
#' Reads the JSON files written by [pro_request()] and converts each one to a
#' Parquet file using DuckDB, with no intermediate JSONL on disk.
#'
#' For works entities the function detects the presence of
#' `abstract_inverted_index`, `authorships`, and `publication_year` in the
#' inferred schema and, when `enrich = TRUE` (the default), adds two computed
#' columns:
#' - **`abstract`** — plain text reconstructed from `abstract_inverted_index`.
#' - **`citation`** — `"Author (year)"` / `"A & B (year)"` / `"A et al. (year)"`.
#'
#' These expressions are identical to those used by the `openalex-snapshot` CLI
#' binary, so the Parquet output matches the snapshot pipeline column for column.
#'
#' @section File format:
#' [pro_request()] writes one JSON file per API page.  For paginated queries
#' each file has the structure `{"results": [...], "meta": {...}}`.  For
#' group-by queries the array field is `"group_by"`.  For single-record lookups
#' the file is a bare JSON object.  All three formats are handled automatically.
#'
#' @section Output layout:
#' The subdirectory structure of `input_json` is preserved, with hive-partition
#' naming (`query=<name>/`, `query_l2=<name>/`, …) so that Arrow/DuckDB can
#' read the result as a partitioned dataset.  A `page` column is added to each
#' record with a value derived from the source filename (or subdirectory for
#' multi-query inputs).
#'
#' @param input_json Directory of JSON files returned by [pro_request()].
#' @param output Output directory for the Parquet dataset.
#' @param add_columns Named list of scalar constant columns to embed in every
#'   output record (e.g. `list(query = "my_filter")`).  Values are embedded as
#'   SQL string literals; only character scalars are supported.
#' @param overwrite Logical.  Overwrite `output` if it already exists.
#'   Default `FALSE`.
#' @param verbose Logical.  Show progress messages.  Default `TRUE`.
#' @param progress Logical.  Show a progress bar.  Default `TRUE`.
#' @param delete_input Logical.  Delete `input_json` after a successful
#'   conversion.  Default `FALSE`.
#' @param sample_size Integer.  Number of records per file passed to DuckDB's
#'   `sample_size` option during schema inference.  Use `-1` to read all
#'   records (accurate but slow for large files).  Default `1000`.
#' @param workers Integer.  Number of parallel workers.
#'   `NULL` or `1` runs sequentially.  Default `NULL`.
#' @param enrich Logical.  When `TRUE` (the default) and the inferred schema
#'   contains `abstract_inverted_index` / `authorships` / `publication_year`,
#'   add `abstract` and `citation` computed columns.
#'
#' @return Output directory path (invisibly).
#'
#' @seealso [pro_request()] to download the JSON files,
#'   [pro_request_jsonl_R()] and [pro_request_jsonl_parquet()] for the older
#'   two-step pipeline (now deprecated).
#'
#' @importFrom duckdb duckdb
#' @importFrom DBI dbConnect dbDisconnect dbExecute dbGetQuery
#' @importFrom future plan multisession sequential
#' @importFrom future.apply future_lapply
#' @importFrom cli cli_alert_info
#' @importFrom progressr with_progress progressor handlers
#'
#' @md
#'
#' @export
pro_request_parquet <- function(
  input_json = NULL,
  output = NULL,
  add_columns = list(),
  overwrite = FALSE,
  verbose = TRUE,
  progress = TRUE,
  delete_input = FALSE,
  sample_size = 1000,
  workers = NULL,
  enrich = TRUE
) {
  # ── Argument checks ──────────────────────────────────────────────────────────
  if (is.null(input_json)) stop("No `input_json` specified!")
  if (is.null(output))     stop("No `output` specified!")

  # ── Output directory ─────────────────────────────────────────────────────────
  if (file.exists(output)) {
    if (!overwrite) {
      stop(
        "output ", output, " exists.\n",
        "Either specify `overwrite = TRUE` or delete it."
      )
    }
    unlink(output, recursive = TRUE, force = TRUE)
  }
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  progress_file <- file.path(output, "00_in.progress")
  file.create(progress_file)
  success <- FALSE
  on.exit({ if (isTRUE(success)) unlink(progress_file) }, add = TRUE)

  # ── Discover JSON files ──────────────────────────────────────────────────────
  jsons <- list.files(
    input_json, pattern = "\\.json$", full.names = TRUE, recursive = TRUE
  )
  # Sort by trailing page number so pages convert in order
  jsons <- jsons[order(as.numeric(
    sub(".*_([0-9]+)\\.json$", "\\1", jsons)
  ))]
  if (length(jsons) == 0) stop("No JSON files found in `input_json`!")
  has_subdirs <- length(list.dirs(input_json, recursive = FALSE)) > 0

  # Determine format from filename prefix
  types <- unique(vapply(
    basename(jsons),
    function(b) strsplit(b, "_")[[1L]][1L],
    character(1L)
  ))
  if (length(types) > 1L) stop("Mixed entity types found in `input_json`!")
  entity_type <- if (identical(types, "group")) "group_by" else types
  # array_field: the JSON key containing the records array; NULL for single records
  array_field <- switch(entity_type, results = "results", group_by = "group_by", NULL)

  # ── Schema inference ─────────────────────────────────────────────────────────
  sample_opt <- if (isTRUE(sample_size > 0)) {
    sprintf(", sample_size = %d", as.integer(sample_size))
  } else {
    ""
  }
  # Use at most 20 files for inference to keep it fast
  infer_files <- if (length(jsons) > 20L) sample(jsons, 20L) else jsons
  files_sql   <- paste0("[", paste0("'", infer_files, "'", collapse = ", "), "]")

  schema_df <- NULL
  list_type <- NULL  # STRUCT(...)[] type for the array items

  if (verbose) message("Inferring schema from ", length(infer_files), " sampled file(s)...")

  con <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbExecute(con, "INSTALL json; LOAD json;")

  if (!is.null(array_field)) {
    # Paginated case: {"results":[...], "meta":{...}}
    # ignore_errors=true: OpenAlex works abstract_inverted_index can contain
    # duplicate struct keys (e.g. "the"/"The"); DuckDB struct auto-detection
    # rejects these.  With ignore_errors=true DuckDB infers
    # abstract_inverted_index as MAP(VARCHAR, BIGINT[]) which handles duplicate
    # keys correctly and works with map_entries() in oa_works_abstract_sql().
    schema_sql <- sprintf(
      "DESCRIBE SELECT r.* FROM (SELECT unnest(%s) AS r FROM read_json(%s, ignore_errors = true%s))",
      array_field, files_sql, sample_opt
    )
    schema_df <- tryCatch(
      DBI::dbGetQuery(con, schema_sql),
      error = function(e) {
        if (verbose) message("Schema inference failed: ", conditionMessage(e))
        NULL
      }
    )
    if (!is.null(schema_df) && nrow(schema_df) > 0L) {
      # Force abstract_inverted_index to MAP(VARCHAR, BIGINT[]).
      # When a sampled page has no duplicate-cased keys DuckDB infers the
      # column as STRUCT(...) rather than MAP, which breaks map_entries() in
      # oa_works_abstract_sql().  Pinning the type here ensures read_json()
      # always parses it as MAP regardless of the sample contents.
      aii_idx <- which(schema_df$column_name == "abstract_inverted_index")
      if (length(aii_idx) == 1L) {
        schema_df$column_type[aii_idx] <- "MAP(VARCHAR, BIGINT[])"
      }
      struct_fields <- paste(schema_df$column_name, schema_df$column_type, sep = " ")
      list_type <- paste0(
        "STRUCT(", paste(struct_fields, collapse = ", "), ")[]"
      )
    }
  } else {
    # Single-record case: bare JSON object.
    schema_sql <- sprintf(
      "DESCRIBE SELECT * FROM read_json(%s, ignore_errors = true%s)",
      files_sql, sample_opt
    )
    schema_df <- tryCatch(
      DBI::dbGetQuery(con, schema_sql),
      error = function(e) NULL
    )
  }

  DBI::dbDisconnect(con, shutdown = TRUE)

  # Decide which enrichment columns to add
  present_cols  <- if (!is.null(schema_df)) schema_df$column_name else character(0L)
  add_abstract  <- enrich && "abstract_inverted_index" %in% present_cols
  add_citation  <- enrich && all(c("authorships", "publication_year") %in% present_cols)

  abstract_sql <- if (add_abstract) oa_works_abstract_sql() else NULL
  citation_sql <- if (add_citation) oa_works_citation_sql() else NULL

  # ── Compute output file paths ─────────────────────────────────────────────────
  input_depth <- length(strsplit(gsub("\\\\", "/", input_json), "/")[[1L]])
  hive_key    <- function(depth) if (depth == 1L) "query" else paste0("query_l", depth)

  output_files <- vapply(jsons, function(f) {
    f_parts   <- strsplit(gsub("\\\\", "/", f), "/")[[1L]]
    fname     <- sub("\\.json$", ".parquet", basename(f))
    rel_parts <- if (length(f_parts) > input_depth + 1L) {
      f_parts[seq(input_depth + 1L, length(f_parts) - 1L)]
    } else {
      character(0L)
    }
    if (length(rel_parts) > 0L) {
      hive_dirs <- mapply(
        function(d, v) paste0(hive_key(d), "=", v),
        seq_along(rel_parts), rel_parts,
        SIMPLIFY = TRUE
      )
      do.call(file.path, c(list(output), as.list(hive_dirs), list(fname)))
    } else {
      file.path(output, fname)
    }
  }, character(1L), USE.NAMES = FALSE)

  # ── Parallel conversion ───────────────────────────────────────────────────────
  if (!is.null(workers) && workers > 1L) {
    old_plan <- future::plan(future::multisession, workers = workers)
    on.exit(future::plan(old_plan), add = TRUE)
  }

  if (progress) {
    cli::cli_alert_info("Converting {length(jsons)} JSON file{?s} to Parquet")
    progressr::handlers("cli")
  }

  # Capture all loop-invariant state as plain values for future serialisation
  .array_field  <- array_field
  .list_type    <- list_type
  .abstract_sql <- abstract_sql
  .citation_sql <- citation_sql
  .add_columns  <- add_columns
  .has_subdirs  <- has_subdirs
  .verbose      <- verbose

  progressr::with_progress({
    p <- if (progress) progressr::progressor(steps = length(jsons)) else NULL

    future.apply::future_lapply(seq_along(jsons), function(i) {
      fn     <- jsons[[i]]
      out_fn <- output_files[[i]]

      # Page identifier: subdirectory name for multi-query inputs, else number
      pn <- if (.has_subdirs) {
        basename(dirname(fn))
      } else {
        sub(".*_([0-9]+)\\.json$", "\\1", basename(fn))
      }

      dir.create(dirname(out_fn), recursive = TRUE, showWarnings = FALSE)

      # Build the list of extra SELECT expressions
      extras <- character(0L)
      if (!is.null(.abstract_sql)) {
        extras <- c(extras, paste0(.abstract_sql, " AS abstract"))
      }
      if (!is.null(.citation_sql)) {
        extras <- c(extras, paste0(.citation_sql, " AS citation"))
      }
      extras <- c(extras, sprintf("'%s' AS page", pn))
      if (length(.add_columns) > 0L) {
        extras <- c(
          extras,
          sprintf("'%s' AS %s", as.character(.add_columns), names(.add_columns))
        )
      }
      extra_select <- if (length(extras) > 0L) {
        paste(",", paste(extras, collapse = ",\n          "))
      } else {
        ""
      }

      # Build conversion SQL depending on format
      sql <- if (!is.null(.array_field)) {
        read_spec <- if (!is.null(.list_type)) {
          sprintf(
            "read_json('%s', columns = {'%s': '%s', 'meta': 'JSON'})",
            fn, .array_field, .list_type
          )
        } else {
          sprintf("read_json_auto('%s')", fn)
        }
        sprintf(
          "COPY (
            SELECT *%s
            FROM (
              SELECT r.*
              FROM (SELECT unnest(%s) AS r FROM %s)
            )
          ) TO '%s' (FORMAT PARQUET, COMPRESSION SNAPPY, ROW_GROUP_SIZE 100000)",
          extra_select, .array_field, read_spec, out_fn
        )
      } else {
        sprintf(
          "COPY (
            SELECT *%s
            FROM read_json_auto('%s')
          ) TO '%s' (FORMAT PARQUET, COMPRESSION SNAPPY, ROW_GROUP_SIZE 100000)",
          extra_select, fn, out_fn
        )
      }

      worker_con <- DBI::dbConnect(duckdb::duckdb())
      tryCatch(
        {
          DBI::dbExecute(worker_con, "INSTALL json; LOAD json;")
          DBI::dbExecute(worker_con, sql)
        },
        error = function(e) {
          if (.verbose) {
            message("Failed to convert ", basename(fn), ": ", conditionMessage(e))
          }
        }
      )
      DBI::dbDisconnect(worker_con, shutdown = TRUE)

      if (!is.null(p)) p()
      invisible(NULL)
    })
  }, enable = progress)

  if (delete_input) unlink(input_json, recursive = TRUE, force = TRUE)

  success <- TRUE
  invisible(normalizePath(output))
}
