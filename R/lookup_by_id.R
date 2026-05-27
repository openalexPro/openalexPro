#' Look up records by OpenAlex ID
#'
#' @description
#' **Moved to the \pkg{openalexSnapshot} package.**
#'
#' This function has been removed from \pkg{openalexPro}.
#' Please install the \pkg{openalexSnapshot} package and call
#' `openalexSnapshot::lookup_by_id()` instead.
#'
#' @param ... Ignored.
#'
#' @seealso \url{https://github.com/rkrug/openalexSnapshot}
#'
#' @export
lookup_by_id <- function(...) {
  stop(
    "lookup_by_id() has moved to the openalexSnapshot package.\n",
    "Install it with: pak::pak(\"openalexSnapshot\")",
    call. = FALSE
  )
}
