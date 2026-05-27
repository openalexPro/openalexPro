#' Convert OA snapshot to Parquet format
#'
#' @description
#' **Moved to the \pkg{openalexSnapshot} package.**
#'
#' This function has been removed from \pkg{openalexPro}.
#' Please install the \pkg{openalexSnapshot} package and call
#' `openalexSnapshot::snapshot_to_parquet()` instead.
#'
#' @param ... Ignored.
#'
#' @seealso \url{https://github.com/rkrug/openalexSnapshot}
#'
#' @export
snapshot_to_parquet <- function(...) {
  stop(
    "snapshot_to_parquet() has moved to the openalexSnapshot package.\n",
    "Install it with: pak::pak(\"openalexSnapshot\")",
    call. = FALSE
  )
}
