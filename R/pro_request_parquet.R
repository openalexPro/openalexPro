#' Convert JSON files from pro_request() directly to Apache Parquet
#'
#' Single-step replacement for the two-step
#' `pro_request_jsonl()` + `pro_request_jsonl_parquet()` pipeline.
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
#' @param resume Logical.  When `TRUE`, keep an existing `output` and convert
#'   only the files that are not already there.  Safe because each file is
#'   written to a `.part` sidecar and renamed only on success, so a present
#'   file is always complete.  Default `FALSE`.
#' @param on_error How to handle files that still fail after the sequential
#'   retry: `"error"` (the default) stops and names them, `"warn"` warns and
#'   returns, `"ignore"` is silent.
#'
#'   Before 0.12.0 failures were only `message()`d when `verbose`, and the run
#'   reported success regardless -- so a page that failed to convert went
#'   silently missing from the corpus.  `"warn"` is the closest to that old
#'   behaviour, but visible.
#' @param memory_limit DuckDB `memory_limit` for each conversion worker.
#'   `NULL` (default) derives one from physical RAM and `workers`, rather than
#'   letting every worker claim DuckDB's default of 80% of the machine.
#' @param retry_memory_limit `memory_limit` for the sequential retry pass,
#'   where no workers compete.  `NULL` (default) uses the whole budget.
#' @param workers Integer.  Number of parallel workers.
#'   `NULL` or `1` runs sequentially.  Default `NULL`.
#' @param enrich Logical.  When `TRUE` (the default) and the inferred schema
#'   contains `abstract_inverted_index` / `authorships` / `publication_year`,
#'   add `abstract` and `citation` computed columns.
#' @param schema Controls use of a pre-built baseline schema for type
#'   resolution.  Possible values:
#'   \describe{
#'     \item{`"auto"` (default)}{Auto-detect the OpenAlex entity type from the
#'       inferred columns, then load the matching schema from the user cache
#'       (populated by \code{\link{oa_schema}(update = TRUE)}) or the schemas
#'       bundled with the package.  For each column where DuckDB runtime
#'       inference produced the ambiguous `JSON` fallback type, the baseline
#'       type is used instead.  Falls back silently to runtime-only inference
#'       when the entity cannot be detected or no schema is found.}
#'     \item{`"none"` or `NULL`}{Skip the baseline entirely; behaviour is
#'       identical to package versions before this feature was added.}
#'     \item{A file path}{Path to a CSV with columns `col_name` / `col_type`.
#'       Used directly as the baseline.}
#'     \item{A directory path}{Auto-detect entity, then look for
#'       `<entity>.csv` inside that directory.}
#'   }
#'
#' @return Output directory path (invisibly).
#'
#' @seealso [pro_request()] to download the JSON files,
#'   [pro_request_jsonl()] and [pro_request_jsonl_parquet()] for the older
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
  enrich = TRUE,
  schema = "auto",
  resume = FALSE,
  on_error = c("error", "warn", "ignore"),
  memory_limit = NULL,
  retry_memory_limit = NULL
) {
  if (is.null(input_json)) stop("No `input_json` specified!")
  if (is.null(output))     stop("No `output` specified!")
  on_error <- match.arg(on_error)

  progress_file <- .prr_prepare_output(output, overwrite, resume)
  success <- FALSE
  on.exit({ if (isTRUE(success)) unlink(progress_file) }, add = TRUE)

  disc      <- .prr_discover_jsons(input_json)
  schema_df <- .prr_infer_schema(
    disc$jsons, disc$array_field, sample_size, schema, verbose
  )
  list_type <- attr(schema_df, "list_type")

  present_cols <- if (!is.null(schema_df)) schema_df$column_name else character(0L)
  abstract_sql <- if (enrich && "abstract_inverted_index" %in% present_cols) {
    oa_works_abstract_sql()
  } else NULL
  citation_sql <- if (enrich && all(c("authorships", "publication_year") %in% present_cols)) {
    oa_works_citation_sql()
  } else NULL

  output_files <- .prr_output_paths(disc$jsons, input_json, output)

  if (!is.null(workers) && workers > 1L) {
    old_plan <- future::plan(future::multisession, workers = workers)
    on.exit(future::plan(old_plan), add = TRUE)
  }

  if (progress) {
    cli::cli_alert_info("Converting {length(disc$jsons)} JSON file{?s} to Parquet")
    progressr::handlers("cli")
  }

  .array_field  <- disc$array_field
  .has_subdirs  <- disc$has_subdirs
  .list_type    <- list_type
  .abstract_sql <- abstract_sql
  .citation_sql <- citation_sql
  .add_columns  <- add_columns
  .verbose      <- verbose
  .resume       <- isTRUE(resume)
  jsons         <- disc$jsons

  # One DuckDB thread per worker: the processes already saturate the machine,
  # and each worker's parquet write buffers separately. Sequentially, let
  # DuckDB use all cores rather than idling them.
  n_workers <- if (is.null(workers)) 1L else as.integer(workers)
  .threads  <- if (n_workers > 1L) 1L else NULL
  .memory   <- memory_limit %||% .pro_worker_memory(n_workers)

  statuses <- progressr::with_progress({
    p <- if (progress) progressr::progressor(steps = length(jsons)) else NULL
    future.apply::future_lapply(seq_along(jsons), function(i) {
      st <- .prr_convert_one(
        fn           = jsons[[i]],
        out_fn       = output_files[[i]],
        array_field  = .array_field,
        has_subdirs  = .has_subdirs,
        list_type    = .list_type,
        abstract_sql = .abstract_sql,
        citation_sql = .citation_sql,
        add_columns  = .add_columns,
        verbose      = .verbose,
        memory_limit = .memory,
        threads      = .threads,
        resume       = .resume
      )
      if (!is.null(p)) p()
      st
    })
  }, enable = progress)

  failed <- which(!vapply(statuses, is.null, logical(1)))

  # Retry sequentially with the whole budget. Per-file peak memory varies with
  # how large and nested a page happens to be, so sizing the per-worker limit
  # for the worst file would throttle all of them; let dense files fail and
  # re-run just those alone.
  if (length(failed) > 0L && n_workers > 1L) {
    if (verbose) {
      message("Retrying ", length(failed), " failed file(s) sequentially.")
    }
    future::plan(future::sequential)
    retry_mem <- retry_memory_limit %||% .pro_worker_memory(1L)
    for (i in failed) {
      statuses[[i]] <- .prr_convert_one(
        fn           = jsons[[i]],
        out_fn       = output_files[[i]],
        array_field  = .array_field,
        has_subdirs  = .has_subdirs,
        list_type    = .list_type,
        abstract_sql = .abstract_sql,
        citation_sql = .citation_sql,
        add_columns  = .add_columns,
        verbose      = .verbose,
        memory_limit = retry_mem,
        threads      = NULL,
        resume       = FALSE
      )
    }
    failed <- which(!vapply(statuses, is.null, logical(1)))
  }

  if (length(failed) > 0L) {
    .prr_report_failures(failed, jsons, statuses, output, length(jsons), on_error)
  }

  if (delete_input) unlink(input_json, recursive = TRUE, force = TRUE)

  # Only a wholly successful run clears the sentinel, so `00_in.progress`
  # marks a partial conversion and can drive `resume`.
  success <- length(failed) == 0L
  invisible(normalizePath(output))
}

#' Report per-file conversion failures according to `on_error`
#'
#' @keywords internal
#' @noRd
.prr_report_failures <- function(failed, jsons, statuses, output, n_total, on_error) {
  if (on_error == "ignore") {
    return(invisible(NULL))
  }
  shown <- utils::head(failed, 10L)
  detail <- paste0(
    "  ", basename(unlist(jsons[shown])), ": ",
    vapply(statuses[shown], function(s) sub("\n.*", "", s), character(1)),
    collapse = "\n"
  )
  msg <- paste0(
    length(failed), " of ", n_total, " JSON file(s) failed to convert",
    " (", n_total - length(failed), " succeeded).\n", detail,
    if (length(failed) > length(shown)) {
      paste0("\n  ... and ", length(failed) - length(shown), " more")
    } else {
      ""
    },
    "\nOutput: ", output,
    "\nRe-run with `resume = TRUE` to convert only the missing files."
  )
  if (on_error == "error") stop(msg, call. = FALSE) else warning(msg, call. = FALSE)
}

# Helpers --------------------------------------------------------------------

#' @keywords internal
#' @noRd
.prr_prepare_output <- function(output, overwrite, resume = FALSE) {
  if (file.exists(output)) {
    # Resume keeps what is already converted. Each output file is written via
    # a `.part` sidecar and renamed on success, so anything present is whole.
    if (isTRUE(resume)) {
      unlink(list.files(output, pattern = "\\.part$", recursive = TRUE,
                        full.names = TRUE), force = TRUE)
      progress_file <- file.path(output, "00_in.progress")
      if (!file.exists(progress_file)) file.create(progress_file)
      return(progress_file)
    }
    if (!overwrite) {
      stop(
        "output ", output, " exists.\n",
        "Either specify `overwrite = TRUE`, `resume = TRUE`, or delete it."
      )
    }
    unlink(output, recursive = TRUE, force = TRUE)
  }
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  progress_file <- file.path(output, "00_in.progress")
  file.create(progress_file)
  progress_file
}

#' @keywords internal
#' @noRd
.prr_discover_jsons <- function(input_json) {
  jsons <- list.files(
    input_json, pattern = "\\.json$", full.names = TRUE, recursive = TRUE
  )
  jsons <- jsons[order(as.numeric(
    sub(".*_([0-9]+)\\.json$", "\\1", jsons)
  ))]
  if (length(jsons) == 0) stop("No JSON files found in `input_json`!")

  types <- unique(vapply(
    basename(jsons),
    function(b) strsplit(b, "_")[[1L]][1L],
    character(1L)
  ))
  if (length(types) > 1L) stop("Mixed entity types found in `input_json`!")
  entity_type <- if (identical(types, "group")) "group_by" else types
  array_field <- switch(
    entity_type, results = "results", group_by = "group_by", NULL
  )

  list(
    jsons       = jsons,
    array_field = array_field,
    has_subdirs = length(list.dirs(input_json, recursive = FALSE)) > 0
  )
}

#' @keywords internal
#' @noRd
.prr_infer_schema <- function(jsons, array_field, sample_size, schema, verbose) {
  sample_opt <- if (isTRUE(sample_size > 0)) {
    sprintf(", sample_size = %d", as.integer(sample_size))
  } else {
    ""
  }
  infer_files <- if (length(jsons) > 20L) sample(jsons, 20L) else jsons
  files_sql   <- paste0("[", paste0("'", infer_files, "'", collapse = ", "), "]")

  if (verbose) message("Inferring schema from ", length(infer_files), " sampled file(s)...")

  # Schema inference reads up to 20 JSON files, which is not free -- give it
  # the same budget and private spill directory as a conversion worker.
  temp_dir <- .pro_temp_dir("infer_schema")
  con <- .pro_con(
    memory_limit = .pro_worker_memory(1L), temp_dir = temp_dir, json = TRUE
  )
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  on.exit(unlink(temp_dir, recursive = TRUE, force = TRUE), add = TRUE)

  if (is.null(array_field)) {
    schema_sql <- sprintf(
      "DESCRIBE SELECT * FROM read_json(%s, ignore_errors = true%s)",
      files_sql, sample_opt
    )
    schema_df <- tryCatch(DBI::dbGetQuery(con, schema_sql), error = function(e) NULL)
    return(schema_df)
  }

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
  if (is.null(schema_df) || nrow(schema_df) == 0L) return(schema_df)

  # Force abstract_inverted_index to MAP — DuckDB sometimes infers STRUCT
  # when the sample has no duplicate-cased keys, which breaks map_entries().
  aii_idx <- which(schema_df$column_name == "abstract_inverted_index")
  if (length(aii_idx) == 1L) {
    schema_df$column_type[aii_idx] <- "MAP(VARCHAR, BIGINT[])"
  }

  schema_df <- .prr_apply_baseline(schema_df, schema, verbose)

  struct_fields <- paste(schema_df$column_name, schema_df$column_type, sep = " ")
  list_type <- paste0("STRUCT(", paste(struct_fields, collapse = ", "), ")[]")
  list_type <- .prr_fix_json_types(list_type)
  attr(schema_df, "list_type") <- list_type
  schema_df
}

#' @keywords internal
#' @noRd
.prr_apply_baseline <- function(schema_df, schema, verbose) {
  if (is.null(schema) || identical(schema, "none")) return(schema_df)
  baseline_df <- .resolve_baseline(schema, present_cols = schema_df$column_name)
  if (is.null(baseline_df)) return(schema_df)

  for (.i in seq_len(nrow(schema_df))) {
    rt <- schema_df$column_type[.i]
    if (!grepl("\\bJSON\\b", rt)) next
    col      <- schema_df$column_name[.i]
    base_row <- baseline_df[baseline_df$col_name == col, , drop = FALSE]
    if (nrow(base_row) == 1L) {
      schema_df$column_type[.i] <- base_row$col_type
    }
  }
  if (verbose) {
    message(
      "Applied baseline schema for entity '",
      attr(baseline_df, "entity"), "'."
    )
  }
  schema_df
}

#' @keywords internal
#' @noRd
.prr_fix_json_types <- function(list_type) {
  # Patch known OpenAlex source-struct fields DuckDB may infer as JSON when
  # all sampled values are null — required for union_by_name = true reads.
  list_type <- gsub("\\bissn_l JSON\\b", "issn_l VARCHAR", list_type)
  list_type <- gsub("(?<![_])\\bissn JSON\\b", "issn VARCHAR[]", list_type, perl = TRUE)
  gsub(
    "host_organization_lineage_names JSON\\[\\]",
    "host_organization_lineage_names VARCHAR[]",
    list_type, fixed = TRUE
  )
}

#' @keywords internal
#' @noRd
.prr_output_paths <- function(jsons, input_json, output) {
  input_depth <- length(strsplit(gsub("\\\\", "/", input_json), "/")[[1L]])
  hive_key <- function(depth) if (depth == 1L) "query" else paste0("query_l", depth)

  vapply(jsons, function(f) {
    f_parts <- strsplit(gsub("\\\\", "/", f), "/")[[1L]]
    fname   <- sub("\\.json$", ".parquet", basename(f))
    rel_parts <- if (length(f_parts) > input_depth + 1L) {
      f_parts[seq(input_depth + 1L, length(f_parts) - 1L)]
    } else {
      character(0L)
    }
    if (length(rel_parts) == 0L) return(file.path(output, fname))
    hive_dirs <- mapply(
      function(d, v) paste0(hive_key(d), "=", v),
      seq_along(rel_parts), rel_parts,
      SIMPLIFY = TRUE
    )
    do.call(file.path, c(list(output), as.list(hive_dirs), list(fname)))
  }, character(1L), USE.NAMES = FALSE)
}

#' @keywords internal
#' @noRd
.prr_convert_one <- function(
  fn, out_fn, array_field, has_subdirs, list_type,
  abstract_sql, citation_sql, add_columns, verbose,
  memory_limit = NULL, threads = NULL, resume = FALSE
) {
  # Resume: a finished file is complete by construction, because the write is
  # to `<out>.part` and renamed only on success. A bare file.exists() check
  # against a directly-written target would happily trust a file truncated by
  # a killed worker.
  if (isTRUE(resume) && file.exists(out_fn)) {
    return(NULL)
  }
  pn <- if (has_subdirs) {
    basename(dirname(fn))
  } else {
    sub(".*_([0-9]+)\\.json$", "\\1", basename(fn))
  }
  dir.create(dirname(out_fn), recursive = TRUE, showWarnings = FALSE)

  extras <- character(0L)
  if (!is.null(abstract_sql)) extras <- c(extras, paste0(abstract_sql, " AS abstract"))
  if (!is.null(citation_sql)) extras <- c(extras, paste0(citation_sql, " AS citation"))
  extras <- c(extras, sprintf("'%s' AS page", pn))
  if (length(add_columns) > 0L) {
    extras <- c(
      extras,
      sprintf("'%s' AS %s", as.character(add_columns), names(add_columns))
    )
  }
  extra_select <- if (length(extras) > 0L) {
    paste(",", paste(extras, collapse = ",\n          "))
  } else {
    ""
  }

  # Write to a sidecar and rename on success. A parquet footer is written
  # last, so a worker killed mid-COPY leaves a file that looks plausible to
  # file.exists() but cannot be read -- and `resume` would then skip it
  # forever. A same-directory rename is atomic.
  part_fn <- paste0(out_fn, ".part")
  unlink(part_fn, force = TRUE)

  sql <- if (!is.null(array_field)) {
    read_spec <- if (!is.null(list_type)) {
      sprintf(
        "read_json('%s', columns = {'%s': '%s', 'meta': 'JSON'})",
        fn, array_field, list_type
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
      extra_select, array_field, read_spec, part_fn
    )
  } else {
    sprintf(
      "COPY (
        SELECT *%s
        FROM read_json_auto('%s')
      ) TO '%s' (FORMAT PARQUET, COMPRESSION SNAPPY, ROW_GROUP_SIZE 100000)",
      extra_select, fn, part_fn
    )
  }

  temp_dir <- .pro_temp_dir(basename(out_fn))
  worker_con <- .pro_con(
    memory_limit = memory_limit, temp_dir = temp_dir,
    threads = threads, json = TRUE
  )
  on.exit(DBI::dbDisconnect(worker_con, shutdown = TRUE), add = TRUE)
  on.exit(unlink(temp_dir, recursive = TRUE, force = TRUE), add = TRUE)

  # Returns NULL on success and the error message on failure. It must NOT
  # swallow the error: until 0.11.0 a file that failed to convert was only
  # message()d when `verbose`, and the run still reported success -- so an
  # OOMed page went silently missing from the corpus and every downstream
  # count was quietly wrong. The caller decides what to do with failures.
  status <- tryCatch(
    {
      DBI::dbExecute(worker_con, sql)
      NULL
    },
    error = function(e) conditionMessage(e)
  )

  if (is.null(status)) {
    if (!file.rename(part_fn, out_fn)) {
      status <- paste0("could not rename ", part_fn, " to ", out_fn)
    }
  }
  if (!is.null(status)) {
    unlink(part_fn, force = TRUE)
    if (verbose) {
      message("Failed to convert ", basename(fn), ": ", status)
    }
  }
  status
}
