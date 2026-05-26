#' Check OpenAlex rate limit status
#'
#' Queries the OpenAlex rate-limit endpoint and returns current API usage
#' and remaining budget as a parsed list.
#'
#' @param api_key API key (character string) or `NULL`. Defaults to
#'   \code{pro_api_key()}. If `NULL` or `""`, this function
#'   returns \code{FALSE} with an informational message.
#' @param verbose Logical. If \code{TRUE} (default), prints rate limit info via \code{message()}.
#' @return Invisibly, the parsed JSON list with all rate limit fields; \code{FALSE}
#'   if the API key is missing or invalid; or \code{NULL} if the request failed due
#'   to a network error.
#' @importFrom httr2 request req_url_query req_user_agent resp_status resp_body_json
#' @export
pro_rate_limit_status <- function(
  api_key = pro_api_key(),
  verbose = TRUE
) {
  if (
    is.null(api_key) ||
      (is.character(api_key) && length(api_key) == 1 && !nzchar(api_key))
  ) {
    message(
      "No API key found. Set it with:\n",
      "  Sys.setenv(openalexPro.apikey = 'your-key')\n",
      "or add 'openalexPro.apikey=your-key' to your .Renviron file."
    )
    return(invisible(FALSE))
  } else if (!is.character(api_key) || length(api_key) != 1) {
    stop(
      "`api_key` must be NULL or a length-1 character string.",
      call. = FALSE
    )
  }

  req <- httr2::request("https://api.openalex.org/rate-limit") |>
    httr2::req_url_query(api_key = api_key) |>
    httr2::req_user_agent(paste0(
      "openalexPro/",
      utils::packageVersion("openalexPro")
    ))

  resp <- tryCatch(
    suppressMessages(api_call(req, get_html_response = NULL)),
    error = function(e) {
      message("Request failed: ", conditionMessage(e))
      NULL
    }
  )

  if (is.null(resp)) {
    return(invisible(NULL))
  }

  status <- httr2::resp_status(resp)

  if (status %in% c(401, 403)) {
    message("Invalid API key. Rate limit status could not be retrieved.")
    return(invisible(FALSE))
  }

  if (status != 200) {
    message(
      "Unexpected HTTP status ",
      status,
      ". Rate limit status could not be retrieved."
    )
    return(invisible(FALSE))
  }

  result <- httr2::resp_body_json(resp)

  if (verbose) {
    rl <- result$rate_limit
    message("OpenAlex Rate Limit Status:")
    message("  Daily budget:      $", rl$daily_budget_usd)
    message("  Daily used:        $", rl$daily_used_usd)
    message("  Daily remaining:   $", rl$daily_remaining_usd)
    if (!is.null(rl$prepaid_balance_usd)) {
      message("  Prepaid balance:   $", rl$prepaid_balance_usd)
      message("  Prepaid remaining: $", rl$prepaid_remaining_usd)
    }
    message("  Resets at:         ", rl$resets_at)
    message("  Resets in:         ", rl$resets_in_seconds, " seconds")
  }

  invisible(result)
}
