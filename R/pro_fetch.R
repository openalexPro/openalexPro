# pro_fetch --------------------------------------------------------------------
#
# Main function uses the direct JSON → Parquet pipeline (Rust-backed via
# pro_request_parquet()).  pro_fetch_R() is the standalone pure-R fallback
# using pro_request_parquet_R(), with an identical argument signature.

#' Fetch and convert OpenAlex data to Parquet
#'
#' Convenience wrapper that downloads records from OpenAlex via
#' \code{\link{pro_request}()} and converts them directly to an Apache Parquet
#' dataset via \code{\link{pro_request_parquet}()} (Rust-backed, parallel via
#' rayon).  No intermediate JSONL files are written.
#'
#' The function
#' \itemize{
#'   \item downloads records from OpenAlex via \code{pro_request()} into a
#'     \code{"json"} subfolder of \code{project_folder}, and
#'   \item converts the JSON files to an Apache Parquet dataset via
#'     \code{pro_request_parquet()} into a \code{"parquet"} subfolder.
#' }
#'
#' **This function assumes `count_only == FALSE`**
#'
#' @inheritParams pro_request
#' @inheritParams pro_request_parquet
#'
#' @param count_only Do not use it here. The function will abort if set to
#'   \code{TRUE} and give a warning if \code{FALSE}.
#' @param project_folder Directory where intermediate (\code{json}) and final
#'   (\code{parquet}) results are stored.  If it does not exist, it is created.
#'   If \code{NULL}, a temporary directory is created.
#' @param overwrite Logical. If \code{TRUE}, the \code{json} and
#'   \code{parquet} subdirectories are deleted from \code{project_folder}
#'   before the pipeline starts. If \code{FALSE} (the default) and any of
#'   those subdirectories already exist, the function stops with an error.
#' @param delete_input Logical. If \code{TRUE} (the default), the \code{json}
#'   subfolder is deleted after successful conversion to Parquet.
#'
#' @return Invisibly, the normalised path of the \code{parquet} subfolder
#'   inside \code{project_folder}.
#'
#' @seealso [pro_fetch_R()] for the pure-R/DuckDB fallback,
#'   [pro_request()] for the download step,
#'   [pro_request_parquet()] for the conversion step.
#'
#' @md
#'
#' @export
pro_fetch <- function(
  query_url,
  pages          = 10000,
  project_folder = NULL,
  overwrite      = FALSE,
  api_key        = pro_api_key(),
  delete_input   = TRUE,
  workers        = 1,
  verbose        = FALSE,
  progress       = TRUE,
  enrich         = TRUE,
  count_only,
  error_log      = NULL
) {
  if (
    is.null(api_key) ||
    (is.character(api_key) && length(api_key) == 1 && !nzchar(api_key))
  ) {
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
  dir.create(project_folder, recursive = TRUE, showWarnings = FALSE)

  subdirs  <- c("json", "parquet")
  existing <- subdirs[dir.exists(file.path(project_folder, subdirs))]
  if (length(existing) > 0) {
    if (!overwrite) {
      stop(
        "The following subdirectories already exist in '",
        project_folder, "': ",
        paste(existing, collapse = ", "),
        ".\nEither specify `overwrite = TRUE` or delete them.",
        call. = FALSE
      )
    }
    for (d in existing) {
      unlink(file.path(project_folder, d), recursive = TRUE)
    }
  }

  pro_request(
    query_url  = query_url,
    pages      = pages,
    output     = file.path(project_folder, "json"),
    overwrite  = FALSE,
    api_key    = api_key,
    workers    = workers,
    verbose    = verbose,
    progress   = progress,
    count_only = FALSE,
    error_log  = error_log
  ) |>
    pro_request_parquet(
      output       = file.path(project_folder, "parquet"),
      overwrite    = FALSE,
      verbose      = verbose,
      progress     = progress,
      delete_input = delete_input,
      workers      = workers,
      enrich       = enrich
    )
}


#' Fetch and convert OpenAlex data to Parquet (pure-R implementation)
#'
#' Pure-R/DuckDB fallback for [pro_fetch()].  Uses
#' \code{\link{pro_request_parquet_R}()} for the conversion step instead of
#' the Rust-backed \code{\link{pro_request_parquet}()}.  Both functions share
#' the same argument signature and produce identical output.
#'
#' @inheritParams pro_fetch
#'
#' @return Invisibly, the normalised path of the \code{parquet} subfolder
#'   inside \code{project_folder}.
#'
#' @seealso [pro_fetch()]
#'
#' @md
#'
#' @export
pro_fetch_R <- function(
  query_url,
  pages          = 10000,
  project_folder = NULL,
  overwrite      = FALSE,
  api_key        = pro_api_key(),
  delete_input   = TRUE,
  workers        = 1,
  verbose        = FALSE,
  progress       = TRUE,
  enrich         = TRUE,
  count_only,
  error_log      = NULL
) {
  if (
    is.null(api_key) ||
    (is.character(api_key) && length(api_key) == 1 && !nzchar(api_key))
  ) {
    api_key <- NULL
  } else if (!is.character(api_key) || length(api_key) != 1) {
    stop("`api_key` must be NULL or a length-1 character string.", call. = FALSE)
  }

  if (!missing(count_only)) {
    warning("`count_only` is set but will be assumed to be `FALSE`")
    if (count_only) {
      stop("Setting `count_only = TRUE` is not supported in `pro_fetch_R()`")
    }
  }

  if (is.null(project_folder)) {
    project_folder <- tempdir()
  }
  dir.create(project_folder, recursive = TRUE, showWarnings = FALSE)

  subdirs  <- c("json", "parquet")
  existing <- subdirs[dir.exists(file.path(project_folder, subdirs))]
  if (length(existing) > 0) {
    if (!overwrite) {
      stop(
        "The following subdirectories already exist in '",
        project_folder, "': ",
        paste(existing, collapse = ", "),
        ".\nEither specify `overwrite = TRUE` or delete them.",
        call. = FALSE
      )
    }
    for (d in existing) {
      unlink(file.path(project_folder, d), recursive = TRUE)
    }
  }

  pro_request(
    query_url  = query_url,
    pages      = pages,
    output     = file.path(project_folder, "json"),
    overwrite  = FALSE,
    api_key    = api_key,
    workers    = workers,
    verbose    = verbose,
    progress   = progress,
    count_only = FALSE,
    error_log  = error_log
  ) |>
    pro_request_parquet_R(
      output       = file.path(project_folder, "parquet"),
      overwrite    = FALSE,
      verbose      = verbose,
      progress     = progress,
      delete_input = delete_input,
      workers      = workers,
      enrich       = enrich
    )
}
