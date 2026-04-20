#' Get available filter names from OpenAlex API
#'
#' @param update logical. If `TRUE` update the existing value. Default is `FALSE`.
#' @return A character vector of available filter names
#'
#' @importFrom httr2 request req_url_query resp_body_json
#' @export
opt_filter_names <- function(update = FALSE) {
  if (update) {
    oao <- getOption("openalexPro")
    oao$filter_names <- NULL
    options(openalexPro = oao)
  }

  if (is.null(getOption("openalexPro")$filter_names)) {
    url <- "https://api.openalex.org/works?filter=DOESNTEXIST%3A1"
    resp <- httr2::request("https://api.openalex.org/works") |>
      httr2::req_url_query(filter = "DOESNTEXIST:1") |>
      api_call(get_html_response = NULL) |>
      httr2::resp_body_json()

    filter <- resp$message |>
      strsplit(split = ", ")

    filter <- filter[[1]][-1]

    oao <- getOption("openalexPro")
    if (is.null(oao)) {
      oao <- list(
        filter_names = filter
      )
    } else {
      oao$filter_names <- filter
    }
    options(openalexPro = oao)
  }
  return(getOption("openalexPro")$filter_names)
}
