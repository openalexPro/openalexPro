#' Get available filter names from OpenAlex API
#'
#' Valid filter names differ between entities (e.g. `country_code` is a filter
#' for institutions but not for works). The list is taken from the error
#' message OpenAlex returns for an invalid filter, which names exactly the
#' filters it accepts for that entity; error responses cost no credits. Each
#' entity's list is cached for the R session.
#'
#' @param update logical. If `TRUE` update the existing value. Default is `FALSE`.
#' @param entity OpenAlex entity, e.g. `"works"` (default), `"authors"`,
#'   `"institutions"`. Use the same value as `entity` in [pro_query()].
#' @return A character vector of available filter names. Empty if OpenAlex
#'   does not return a list for `entity` (e.g. the retired `"venues"`).
#'
#' @importFrom httr2 request req_url_query resp_body_json
#' @export
opt_filter_names <- function(update = FALSE, entity = "works") {
  .oa_allowed_names("filter_names", entity, update)
}

#' Fetch and cache the filter names or select fields OpenAlex accepts
#'
#' @param kind `"filter_names"` or `"select_fields"`; also the cache key in
#'   `getOption("openalexPro")`, which holds one vector per entity.
#' @keywords internal
#' @noRd
.oa_allowed_names <- function(kind, entity, update) {
  stopifnot(is.character(entity), length(entity) == 1L, nzchar(entity))
  cache <- getOption("openalexPro")[[kind]]
  # Before 0.12.1 the cache held a single (works) vector, not a list.
  if (!is.list(cache)) cache <- list()
  if (!update && !is.null(cache[[entity]])) {
    return(cache[[entity]])
  }

  probe <- switch(
    kind,
    filter_names = list(filter = "DOESNTEXIST:1"),
    select_fields = list(select = "DOESNTEXIST")
  )
  # The list follows the last ": " of messages such as "... versions of:
  # a, b, c" or "... Valid fields for select are: a, b, c."
  marker <- switch(
    kind,
    filter_names = "versions of: ",
    select_fields = "Valid fields for select are: "
  )
  req <- httr2::request("https://api.openalex.org") |>
    httr2::req_url_path_append(entity) |>
    httr2::req_url_query(!!!probe)
  req <- .oa_auth(req, pro_api_key())
  resp <- api_call(req, get_html_response = NULL)
  msg <- tryCatch(
    httr2::resp_body_json(resp)$message,
    error = function(e) NULL
  )

  if (!is.character(msg) || length(msg) != 1L || !grepl(marker, msg, fixed = TRUE)) {
    # No list (e.g. HTTP 404 for a retired entity): validation is skipped and
    # OpenAlex's own error reaches the user. Not cached, so a transient
    # failure does not switch validation off for the rest of the session.
    return(character(0))
  }
  allowed <- sub(paste0(".*", marker), "", msg)
  allowed <- strsplit(sub("\\.$", "", allowed), ", ", fixed = TRUE)[[1]]

  oao <- getOption("openalexPro")
  if (is.null(oao)) oao <- list()
  cache[[entity]] <- allowed
  oao[[kind]] <- cache
  options(openalexPro = oao)
  allowed
}
