#' Build a Parquet ID-lookup index
#'
#' @description
#' **Moved to the \pkg{openalexSnapshot} package.**
#'
#' This function has been removed from \pkg{openalexPro}.
#' Please install the \pkg{openalexSnapshot} package and call
#' `openalexSnapshot::build_corpus_index()` instead.
#'
#' @param ... Ignored.
#'
#' @seealso \url{https://github.com/rkrug/openalexSnapshot}
#'
#' @export
build_corpus_index <- function(...) {
  stop(
    "build_corpus_index() has moved to the openalexSnapshot package.\n",
    "Install it with: pak::pak(\"openalexSnapshot\")",
    call. = FALSE
  )
}
