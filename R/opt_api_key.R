#' Get API key for OpenAlex API
#'
#' @param api_key character vector or NULL. If specified, value to assign to the api key option. Default is `NULL`.
#' @return The API key, if `api_key` is not specified the current one, otherwise the old one.
#'
#' @export
opt_api_key <- function(api_key) {
  result <- getOption("openalexPro")$api_key
  if (!missing(api_key)) {
    oao <- getOption("openalexPro")
    oao$api_key <- api_key
    options(openalexPro = oao)
  }

  return(result)
}
