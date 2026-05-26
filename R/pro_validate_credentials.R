#' Validate OpenAlex credentials
#'
#' Makes a minimal API request to verify that the api_key is valid.
#'
#' @param api_key API key to validate (character string) or `NULL`.
#' @param show_credentials shows the api_key using `message()`. USE WITH CAUTION!
#' @return TRUE if credentials work, FALSE otherwise
#' @export
pro_validate_credentials <- function(
  api_key = pro_api_key(),
  show_credentials = FALSE
) {
  message("Testing:")
  if (show_credentials) {
    message("    api_key: ", api_key)
  } else {
    message("    api_key: ", strrep("X", nchar(api_key)))
  }
  result <- pro_rate_limit_status(api_key = api_key, verbose = FALSE)
  isTRUE(is.list(result))
}
