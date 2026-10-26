#' Retrieve metadata counts for a PRO API request
#'
#' Builds an `httr2` request targeting the OpenAlex PRO endpoint, executes it,
#' and extracts the pagination metadata. Only summary metadata is requested and
#' the first page is fetched to minimise API usage.
#'
#' @param query_url Character string containing the fully constructed OpenAlex
#'   PRO endpoint URL.
#' @param api_key Character string API key or `NULL`. Defaults to
#'   `pro_api_key()`. If `NULL` or `""`, the request is sent
#'   without an API key (subject to OpenAlex's unauthenticated limits).
#' @param error_log location of error log of API calls. (default: `NULL` (none)).
#' @param via `"oqo"` (default) or `"url"`; see [pro_request()].
#'
#' @return A data.frame containing `count`, `db_response_time_ms`,
#'   `page`, and `per_page` elements. If count is negative, the size of the
#'   request is larger then the allowed limit of 4094. If the request fails,
#'   each value is `NA`.
#'
#' @keywords internal
#'
#' @export
#'
#' @examples
#' \dontrun{
#' meta <- pro_count("https://api.openalex.org/works?filter=host_venue.id:V123")
#' meta[["count"]]
#' }
pro_count <- function(
  query_url,
  api_key = pro_api_key(),
  error_log = NULL,
  via = c("oqo", "url")
) {
  via <- match.arg(via)
  if (
    is.null(api_key) ||
      (is.character(api_key) && length(api_key) == 1 && !nzchar(api_key))
  ) {
    api_key <- NULL
  } else if (!is.character(api_key) || length(api_key) != 1) {
    stop(
      "`api_key` must be NULL or a length-1 character string.",
      call. = FALSE
    )
  }

  query <- list(
    per_page = 1,
    select = "ids",
    page = 1
  )
  oq <- if (via == "oqo") .oa_to_oqo(query_url, api_key) else NULL
  req <- if (is.null(oq)) {
    do.call(httr2::req_url_query, c(list(httr2::request(query_url)), query))
  } else {
    httr2::request(oq$root) |>
      httr2::req_method("POST") |>
      httr2::req_body_json(
        list(oqo = oq$oqo, per_page = 1L, page = 1L, select = "id"),
        auto_unbox = TRUE
      )
  }
  req <- req |>
    .oa_auth(api_key) |>
    httr2::req_user_agent(
      paste0("openalexPro/", packageVersion("openalexPro"))
    )

  meta <- data.frame(
    count = NA_integer_,
    db_response_time_ms = NA_integer_,
    page = NA_integer_,
    per_page = NA_integer_,
    error = NA_character_
  )

  resp <- api_call(
    req,
    get_html_response = 400,
    error_log = error_log
  )
  try(
    {
      data <- resp |>
        httr2::resp_body_json()

      meta <- data.frame(data$meta[c(
        "count",
        "db_response_time_ms",
        "page",
        "per_page"
      )])
      meta$error <- NA_character_
    }
  )
  if (is.na(meta["page"])) {
    try(
      {
        html <- httr2::resp_body_string(resp)

        # Replace HTML entities
        html <- gsub("&gt;", ">", html)

        # Extract the part starting with "Request Line" until the next "<"
        line <- regmatches(html, regexpr("Request Line[^<]+", html))

        # Extract all numbers
        nums <- as.numeric(regmatches(line, gregexpr("\\d+", line))[[1]])

        nums
        # [1] 4195 4094

        meta$count <- -nums[1]

        meta$error <- "ERROR: Request size exceeds the maximum limit of 4094."
      }
    )
  }
  return(meta)
}
