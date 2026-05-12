#' Retrieve the OpenAlex Pro API key
#'
#' Retrieves the OpenAlex Pro API key from one of several locations,
#' checked in the following order:
#'
#' \enumerate{
#'   \item The R option \code{openalexPro$api_key}
#'   \item The environment variable \code{openalexPro.api_key}
#'   \item The system keyring via the \pkg{keyring} package
#'         (only if the package \pkg{keyring} is installed)
#' }
#'
#' If no API key is found, \code{NULL} or an empty string may be returned,
#' depending on the environment variable state.
#'
#' @return
#' A character string containing the API key, or \code{NULL} if no key
#' could be found.
#'
#' @examples
#' \dontrun{
#' pro_api_key()
#'
#' options(openalexPro = list(api_key = "my-key"))
#' pro_api_key()
#' }
#'
#' @seealso
#' \code{\link[base:options]{options}},
#' \code{\link[base:Sys.getenv]{Sys.getenv}}
#'
#' @export
pro_api_key = function() {
  api_key <- opt_api_key()
  if (is.null(api_key)) {
    api_key <- Sys.getenv("openalexPro.api_key")
    if (!nzchar(api_key)) {
      api_key <- NULL
    }
  }
  if (is.null(api_key)) {
    if (requireNamespace("keyring", quietly = TRUE)) {
      try(
        api_key <- keyring::key_get("API_openalex"),
        silent = TRUE
      )
    }
  }
  return(api_key)
}
