#' Perform an API call to the OpenAlex API with retry logic
#'
#' This function performs a request to the OpenAlex API and handles different
#' HTTP status codes with retry for transient errors. Optionally, specific
#' non-200 status codes (e.g. 400) can return the raw HTML response instead
#' of aborting.
#'
#' @param req A request object created by \code{\link[httr2]{request}}.
#' @param max_retries Maximum number of retry attempts (default: 10).
#' @param transient_responses Integer vector of HTTP statuses considered transient
#'   (default: 500, 502, 503, 504, 429).
#' @param error_log File path for error logging (default: `NULL` (none)).
#' @param get_html_response Integer or \code{NULL} controlling when to return a
#'   non-200 response instead of aborting:
#'   \itemize{
#'     \item \emph{Missing:} default behaviour (abort on all non-200 statuses).
#'     \item \code{NULL:} return the response object for all non-200 statuses.
#'     \item integer (e.g. \code{400}): return the response object only if the
#'       HTTP status equals this value \emph{and} the response has an HTML
#'       \code{Content-Type}.
#'   }
#'
#' @return An \code{httr2} response object (on success, or per get_html_response rules), or aborts.
#'
#' @section Debug option:
#' When \code{options(openalexPro.ratelimit_check = TRUE)}, \code{api_call()}
#' calls \code{pro_rate_limit_status(verbose = TRUE)} before every request,
#' printing the current API budget and usage as a message. The option is
#' temporarily set to \code{FALSE} during the nested rate-limit call to prevent
#' infinite recursion.
#'
#' @importFrom httr2 req_retry req_error req_perform resp_status resp_header
#' @importFrom rlang caller_env abort
#' @noRd
api_call <- function(
  req,
  max_retries = 10,
  transient_responses = c(500, 502, 503, 504, 429),
  error_log = NULL,
  get_html_response
) {
  # Rate-limit debug check: print status before each call when option is set.
  # Temporarily disabled during the nested pro_rate_limit_status() call to
  # prevent infinite recursion (pro_rate_limit_status → api_call → ...).
  if (isTRUE(getOption("openalexPro.ratelimit_check"))) {
    options(openalexPro.ratelimit_check = FALSE)
    on.exit(options(openalexPro.ratelimit_check = TRUE), add = TRUE)
    pro_rate_limit_status(verbose = TRUE)
  }

  # simple logger
  log_fun <- function(msg, log_file) {
    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    full_msg <- paste0("[", timestamp, "] ", msg, "\n")
    if (!is.null(log_file)) {
      cat(full_msg, file = log_file, append = TRUE)
    } else {
      message(full_msg)
    }
  }

  # Retry logic for transient statuses
  req <- req |>
    httr2::req_retry(
      max_tries = max_retries,
      backoff = ~ 2^.x,
      is_transient = function(resp) {
        status <- httr2::resp_status(resp)
        status %in% transient_responses
      }
    )

  # IMPORTANT: control when httr2 should throw vs return the response
  if (!missing(get_html_response) && is.null(get_html_response)) {
    # Return ALL non-200 responses (never auto-throw)
    req <- req |> httr2::req_error(is_error = function(resp) FALSE)
  } else if (!missing(get_html_response) && is.numeric(get_html_response)) {
    # Return only when status matches the integer AND content is HTML
    req <- req |>
      httr2::req_error(is_error = function(resp) {
        status <- httr2::resp_status(resp)
        if (status == get_html_response) {
          ct <- httr2::resp_header(resp, "content-type")
          is_html <- !is.na(ct) &&
            grepl("text/html|application/xhtml\\+xml", ct, ignore.case = TRUE)
          return(!is_html) # don't throw if HTML; throw otherwise
        }
        # default: throw on other 4xx/5xx
        return(status >= 400)
      })
    # If get_html_response is missing: leave default erroring behavior
  }

  # Perform the request
  resp <- tryCatch(
    httr2::req_perform(req, error_call = rlang::caller_env()),
    error = function(e) {
      log_fun(
        paste0(
          "\u274C API call failed after ",
          max_retries,
          " attempts: ",
          e$message
        ),
        error_log
      )
      rlang::abort(message = e$message, class = "api_call_error", parent = e)
    }
  )

  status <- httr2::resp_status(resp)
  if (status == 200) {
    return(resp)
  }

  # Non-200 handling
  if (missing(get_html_response)) {
    # unchanged: abort
    log_fun(paste0("\u26A0 Unexpected HTTP status ", status), error_log)
    rlang::abort(
      paste0("Unexpected HTTP status ", status, "\n  Aborting!"),
      class = "unexpected_http_status"
    )
  } else if (is.null(get_html_response)) {
    return(resp)
  } else if (is.numeric(get_html_response) && status == get_html_response) {
    ct <- httr2::resp_header(resp, "content-type")
    is_html <- !is.na(ct) &&
      grepl("text/html|application/xhtml\\+xml", ct, ignore.case = TRUE)
    if (is_html) {
      log_fun(
        paste0(
          "\u26A0 HTTP ",
          status,
          " (HTML) - returning response for caller inspection"
        ),
        error_log
      )
      return(resp)
    }
    # matched status but not HTML \u2192 abort
    log_fun(
      paste0("\u26A0 Unexpected HTTP status ", status, " (non-HTML)"),
      error_log
    )
    rlang::abort(
      paste0("Unexpected HTTP status ", status, " (non-HTML)\n  Aborting!"),
      class = "unexpected_http_status"
    )
  } else {
    # integer provided, but status didn't match \u2192 abort
    log_fun(paste0("\u26A0 Unexpected HTTP status ", status), error_log)
    rlang::abort(
      paste0("Unexpected HTTP status ", status, "\n  Aborting!"),
      class = "unexpected_http_status"
    )
  }
}
