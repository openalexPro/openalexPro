# pro_fetch --------------------------------------------------------------------

#' Fetch and convert OpenAlex data to Parquet
#'
#' Convenience wrapper that downloads records from OpenAlex via
#' \code{\link{pro_request}()} and converts them directly to an Apache Parquet
#' dataset via \code{\link{pro_request_parquet}()}.  No intermediate JSONL
#' files are written.
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
#' @param workers Number of parallel workers for the conversion to Parquet
#'   (CPU and memory bound), and by default also for the download. Default 1.
#' @param download_workers Number of parallel workers for the download, used
#'   when \code{query_url} is a list. Defaults to \code{workers}. Downloads
#'   are limited by the API rather than the machine, so a few (e.g. 2--4)
#'   are usually enough, while the conversion can use more.
#' @param resume Logical. When \code{TRUE}, keep existing \code{json} and
#'   \code{parquet} subfolders and complete an interrupted run: only leaf
#'   queries that did not finish are downloaded again, and only missing
#'   Parquet files are converted. A finished run is returned unchanged.
#'   \code{overwrite} is ignored. Default \code{FALSE}.
#'
#' @return Invisibly, the normalised path of the \code{parquet} subfolder
#'   inside \code{project_folder}.
#'
#' @seealso [pro_request()] for the download step,
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
  download_workers = workers,
  verbose        = FALSE,
  progress       = TRUE,
  enrich         = TRUE,
  count_only,
  error_log      = NULL,
  resume         = FALSE,
  via            = c("url", "oqo")
) {
  via <- match.arg(via)
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
  parquet_dir <- file.path(project_folder, "parquet")

  # Resume: a parquet folder without its sentinel is a finished run (the json
  # may already be gone through `delete_input`), so there is nothing to do.
  if (isTRUE(resume) && dir.exists(parquet_dir) &&
      !file.exists(file.path(parquet_dir, "00_in.progress"))) {
    return(invisible(normalizePath(parquet_dir)))
  }

  if (length(existing) > 0 && !isTRUE(resume)) {
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
    workers    = download_workers,
    verbose    = verbose,
    progress   = progress,
    count_only = FALSE,
    error_log  = error_log,
    resume     = resume,
    via        = via
  ) |>
    pro_request_parquet(
      output       = parquet_dir,
      overwrite    = FALSE,
      verbose      = verbose,
      progress     = progress,
      delete_input = delete_input,
      workers      = workers,
      enrich       = enrich,
      resume       = resume
    )
}
