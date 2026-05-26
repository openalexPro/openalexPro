#' Get available select fields from OpenAlex API
#'
#' @param update logical. If `TRUE` update the existing value. Default is `FALSE`.
#' @return A character vector of available select fields
#'
#' @importFrom httr2 request req_url_query resp_body_json
#' @export
opt_select_fields <- function(update = FALSE) {
  if (update) {
    oao <- getOption("openalexPro")
    oao$select_fields <- NULL
    options(openalexPro = oao)
  }

  if (is.null(getOption("openalexPro")$select_fields)) {
    resp <- httr2::request("https://api.openalex.org/works/W1775749144") |>
      httr2::req_url_query(select = "DOESNTEXIST") |>
      api_call(get_html_response = NULL) |>
      httr2::resp_body_json()

    select <- resp$message |>
      strsplit(split = ", ")

    select <- select[[1]][-1]

    ## <<
    ## This is to make sure that `id` is in the filter list, which it is not at the moment, but always present.

    if (!("id" %in% select)) {
      select <- c("id", select)
    }

    ## >>

    oao <- getOption("openalexPro")
    if (is.null(oao)) {
      oao <- list(
        select_fields = select
      )
    } else {
      oao$select_fields <- select
    }
    options(openalexPro = oao)
  }
  return(getOption("openalexPro")$select_fields)
}
