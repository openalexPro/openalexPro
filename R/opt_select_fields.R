#' Get available select fields from OpenAlex API
#'
#' Valid select fields differ between entities (e.g. `orcid` for authors).
#' The list is taken from the error message OpenAlex returns for an invalid
#' select field, which names exactly the fields it accepts for that entity;
#' error responses cost no credits. Each entity's list is cached for the R
#' session.
#'
#' @inheritParams opt_filter_names
#' @return A character vector of available select fields. Empty if OpenAlex
#'   does not return a list for `entity` (e.g. the retired `"venues"`).
#'
#' @importFrom httr2 request req_url_query resp_body_json
#' @export
opt_select_fields <- function(update = FALSE, entity = "works") {
  .oa_allowed_names("select_fields", entity, update)
}
