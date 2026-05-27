#' Convert JSON files to jsonl files
#'
#'
#' The function takes a directory of JSON files as written from a call to
#' `pro_request(...)` and is preparing the json files to be
#' processed further using DuckDB by converting them to `jsonl` files.
#' The subfolders in `input_json` are preserved in `output`, i.e.
#' results of a list of initial queries passed to `pro_request()` are maintained.
#' @details See \code{\link{jq_execute}} or the \code{\link{vignette}}("jq",
#'   package = "openalexPro") for more information on the conversion of the
#'   JSON files.
#'   The folder/filename is converted to a value named `page`
#'   As an example:
#'   1. the subfolder in the `output` folder is called `Chunk_1`
#'   2. the page othe json file represents is `2`
#'   3. The resulting cvalus for `page` will be `Chunk_1_2`
#'
#' When starting the conversion, a file `00_in.progress` which is deleted upon completion.
#'
#' @param input_json The directory of JSON files returned from `pro_request(...,
#'   json_dir = "FOLDER")`.
#' @param output output directory for the jsonl files as created by calls to
#'   `jq_execute().
#' @param add_columns List of additional fields to be added to the output. They
#'   nave to be provided as a named list, e./g. `list(column_1 = "value_1",
#'   column_2 = 2)`. Only Scalar values are supported.
#' @param overwrite Logical indicating whether to overwrite `output`.
#' @param verbose Logical indicating whether to show a verbose information.
#'   Defaults to `TRUE`
#' @param progress Logical indicating whether to show a progress bar. Default `TRUE`.
#' @param delete_input Determines if the `input_json` should be deleted
#'   afterwards. Defaults to `FALSE`.
#' @param workers Number of parallel workers to use. Defaults to 1.
#'
#' @return The function does returns the output invisibly.
#'
#' @details The function uses DuckDB to read the JSON files and to create the
#'   Apache Parquet files. The function creates a DuckDB connection in memory
#'   and readsds the JSON files into DuckDB when needed. Then it creates a SQL
#'   query to convert the JSON files to Apache Parquet files and to copy the
#'   result to the specified directory.
#'
#' @importFrom duckdb duckdb
#' @importFrom DBI dbConnect dbDisconnect dbExecute
#' @importFrom future.apply future_lapply
#' @importFrom cli cli_progress_bar cli_progress_update cli_progress_done cli_alert_info
#' @importFrom progressr with_progress progressor handlers
#'
#' @md
#'
#' @examples
#' \dontrun{
#'   source_to_parquet(
#'   input_json = "json",
#'   source_type = "snapshot",
#'   output = "parquet"
#' ) }
#'
#' @export

pro_request_jsonl_R <- function(
  input_json = NULL,
  output = NULL,
  add_columns = list(),
  overwrite = FALSE,
  verbose = TRUE,
  progress = TRUE,
  delete_input = FALSE,
  workers = 1
) {
  .Deprecated(
    new = "pro_request_parquet",
    msg = paste0(
      "`pro_request_jsonl_R()` + `pro_request_jsonl_parquet()` are deprecated.\n",
      "Use `pro_request_parquet()` instead: it converts JSON directly to Parquet\n",
      "in one step with no intermediate JSONL files on disk."
    )
  )

  # Argument checks --------------------------------------------------------

  if (is.null(output)) {
    stop("No `output` output folder specified!")
  }

  ## Check if input_json is specified
  if (is.null(input_json)) {
    stop("No `input_json`_dir to convert specified!")
  }

  ## Check if output is specified
  if (is.null(output)) {
    stop("No output to convert to specified!")
  }

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
  dir.create(output, recursive = TRUE)
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

  ## Read names of json files
  jsons <- list.files(
    input_json,
    pattern = "*.json$",
    full.names = TRUE,
    recursive = TRUE
  )

  has_subdirs <- length(list.dirs(input_json)) > 1

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
    stop("No JSON files found in `input_json`!")
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

  # Go through all jsons, i.e. one per page --------------------------------
  ### Names: results_page_x.json

  old_plan <- future::plan()
  on.exit(future::plan(old_plan), add = TRUE)
  if (workers > 1) {
    future::plan(
      future::multisession,
      workers = workers
    )
  } else {
    future::plan(
      future::sequential
    )
  }

  # Setup progress bar
  if (progress) {
    cli::cli_alert_info("Converting {length(jsons)} JSON files to JSONL")
    progressr::handlers("cli")
  }

  progressr::with_progress({
    p <- if (progress) progressr::progressor(steps = length(jsons)) else NULL

    future.apply::future_lapply(seq_along(jsons), function(i) {
      fn <- jsons[i]
      if (verbose) {
        message("Preparing ", i, " of ", length(jsons), " : ", fn)
      }

      ## Extract page number into pn
      pn <- basename(fn) |>
        strsplit(split = "_")
      pn <- pn[[1]]

      pn <- pn[length(pn)] |>
        gsub(pattern = ".json", replacement = "")

      if (has_subdirs) {
        # Preserve full relative subdirectory path (handles arbitrary nesting depth)
        input_depth <- length(strsplit(gsub("\\\\", "/", input_json), "/")[[1]])
        f_parts     <- strsplit(gsub("\\\\", "/", dirname(fn)), "/")[[1]]
        rel_parts   <- f_parts[seq(input_depth + 1L, length(f_parts))]
        jsonl <- do.call(file.path, c(list(output), as.list(rel_parts), list(basename(fn))))
        pn <- basename(dirname(fn))
      } else {
        jsonl <- file.path(output, basename(fn))
        pn <- pn
      }
      dir.create(dirname(jsonl), recursive = TRUE, showWarnings = FALSE)

      try(
        {
          ## do the following in the json:"
          ## - Convert `inverted_abstract_index` to `abstract`
          ## - remove `inverted_abstract_index`
          ## - add `page` = pn
          jq_execute(
            input_json = fn,
            output_jsonl = jsonl,
            add_columns = add_columns,
            jq_filter = NULL,
            page = pn,
            type = types
          )
          if (file.size(jsonl) < 5) {
            unlink(jsonl)
          }
        },
        silent = !verbose
      )

      # Update progress
      if (!is.null(p)) p()

      invisible(NULL)
    })
  }, enable = progress)

  if (verbose) {
    message("Done")
  }

  if (delete_input) {
    unlink(input_json, recursive = TRUE, force = TRUE)
  }

  success <- TRUE

  return(invisible(normalizePath(output)))
}
