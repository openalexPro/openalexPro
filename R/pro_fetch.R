#' Fetch and convert OpenAlex data
#'
#' Convenience wrapper around \code{\link{pro_request}},
#' \code{\link{pro_request_jsonl}} and
#' \code{\link{pro_request_jsonl_parquet}}.
#'
#' The function
#' \itemize{
#'   \item downloads records from OpenAlex via \code{pro_request()} into a
#'     \code{"json"} subfolder of \code{project_folder},
#'   \item converts the JSON files to \code{jsonl} via
#'     \code{pro_request_jsonl()} into a \code{"jsonl"} subfolder, and
#'   \item converts the jsonl files to an Apache Parquet dataset via
#'     \code{pro_request_jsonl_parquet()} into a \code{"parquet"} subfolder.
#' }
#'
#' This is a high-level helper for the common workflow of going from an
#' OpenAlex query URL to a local Parquet dataset in a single call.
#' In most cases, this function should be sufficient, but if more control is needed,
#' the individual functions have to be called separately.
#'
#' **This function assumes `count_only == FALSE`**
#'
#' @inheritParams pro_request
#' @param count_only Do not use it here. The function will abort if it set to
#' `TRUE` and give a warning if `FALSE`
#'
#' @param project_folder Directory where all intermediate (\code{json},
#'   \code{jsonl}) and final (\code{parquet}) results are stored.
#'   If it does not exist, it is created. If \code{NULL}, a temporary
#'   directory is created.
#' @param overwrite Logical. If \code{TRUE}, all three subdirectories
#'   (\code{json}, \code{jsonl}, \code{parquet}) are deleted from
#'   \code{project_folder} before the pipeline starts. If \code{FALSE} (the
#'   default) and any of those subdirectories already exist, the function stops
#'   with an error.
#'
#' @return Invisibly, the normalized path of the \code{parquet} subfolder
#'   inside \code{project_folder}, i.e. the value returned by
#'   \code{pro_request_jsonl_parquet()}.
#'
#' @md
#'
#' @export
pro_fetch <- function(
  query_url,
  pages = 10000,
  project_folder = NULL,
  overwrite = FALSE,
  api_key = Sys.getenv("openalexPro.apikey"),
  workers = 1,
  verbose = FALSE,
  progress = TRUE,
  count_only,
  error_log = NULL
) {
  if (is.null(api_key) || (is.character(api_key) && length(api_key) == 1 && !nzchar(api_key))) {
    api_key <- NULL
  } else if (!is.character(api_key) || length(api_key) != 1) {
    stop("`api_key` must be NULL or a length-1 character string.", call. = FALSE)
  }

  if (!missing(count_only)) {
    warning("`count_only` is set but will be assumed to be `FALSE`")
    if (count_only) {
      stop("Setting `count_only = TRUE` is not supported in `pro_fetch()`")
    }
  }
  if (is.null(project_folder)) {
    project_folder <- tempdir()
  }

  if (!dir.exists(project_folder)) {
    dir.create(
      project_folder,
      recursive = TRUE,
      showWarnings = FALSE
    )
  }

  subdirs <- c("json", "jsonl", "parquet")
  existing <- subdirs[dir.exists(file.path(project_folder, subdirs))]
  if (length(existing) > 0) {
    if (!overwrite) {
      stop(
        "The following subdirectories already exist in '", project_folder, "': ",
        paste(existing, collapse = ", "), ".\n",
        "Either specify `overwrite = TRUE` or delete them."
      )
    }
    for (d in existing) {
      unlink(file.path(project_folder, d), recursive = TRUE)
    }
  }

  pro_request(
    query_url = query_url,
    pages = pages,
    output = file.path(project_folder, "json"),
    overwrite = FALSE,
    api_key = api_key,
    workers = workers,
    verbose = verbose,
    progress = progress,
    count_only = FALSE,
    error_log = error_log
  ) |>
    pro_request_jsonl(
      output = file.path(project_folder, "jsonl"),
      overwrite = FALSE,
      progress = progress,
      delete_input = FALSE,
      workers = workers
    ) |>
    pro_request_jsonl_parquet(
      output = file.path(project_folder, "parquet"),
      overwrite = FALSE,
      verbose = verbose,
      delete_input = FALSE
    )
}
