library(testthat)

# Offline tests (mocked HTTP) for the less common branches of api_call(),
# pro_count(), pro_rate_limit_status() and opt_api_key().

mock_resp <- function(status, body = "{}", type = "application/json",
                      headers = list()) {
  function(req) {
    httr2::response(
      status,
      headers = c(list("content-type" = type), headers),
      body = charToRaw(body)
    )
  }
}

works_req <- function() httr2::request("https://api.openalex.org/works")

html_400 <- paste0(
  "<html><head><title>400 Bad Request</title></head><body>",
  "<h1>Bad Request</h1><p>Request Line is too large (4195 &gt; 4094)</p>",
  "</body></html>"
)

# --- api_call -----------------------------------------------------------------

test_that("api_call aborts on an unexpected non-error status", {
  httr2::local_mocked_responses(mock_resp(204))
  expect_error(
    suppressMessages(api_call(works_req())),
    "Unexpected HTTP status 204",
    class = "unexpected_http_status"
  )
})

test_that("api_call aborts when the status differs from get_html_response", {
  httr2::local_mocked_responses(mock_resp(204))
  expect_error(
    suppressMessages(api_call(works_req(), get_html_response = 400)),
    "Unexpected HTTP status 204",
    class = "unexpected_http_status"
  )
})

test_that("api_call returns an HTML response with the get_html_response status", {
  httr2::local_mocked_responses(mock_resp(400, html_400, type = "text/html"))
  expect_message(
    resp <- api_call(works_req(), get_html_response = 400),
    "HTTP 400 \\(HTML\\) - returning response"
  )
  expect_equal(httr2::resp_status(resp), 400L)
  expect_match(httr2::resp_body_string(resp), "Request Line is too large")
})

test_that("api_call throws for a non-HTML response with the get_html_response status", {
  httr2::local_mocked_responses(mock_resp(400, '{"message":"bad filter"}'))
  expect_error(
    suppressMessages(api_call(works_req(), get_html_response = 400)),
    "bad filter",
    class = "api_call_error"
  )
})

test_that("api_call aborts itself on a non-HTML match if httr2 does not throw", {
  # Defensive check after req_perform(): reached only when the request
  # returns the response instead of raising an error.
  local_mocked_bindings(
    req_perform = function(req, ...) {
      httr2::response(400, headers = list("content-type" = "application/json"),
                      body = charToRaw("{}"))
    },
    .package = "httr2"
  )
  expect_error(
    suppressMessages(api_call(works_req(), get_html_response = 400)),
    "Unexpected HTTP status 400 \\(non-HTML\\)",
    class = "unexpected_http_status"
  )
})

test_that("api_call writes failures to error_log instead of messaging", {
  httr2::local_mocked_responses(mock_resp(404, '{"message":"no such work"}'))
  log <- withr::local_tempfile(fileext = ".log")
  expect_no_message(
    expect_error(api_call(works_req(), error_log = log), "no such work")
  )
  txt <- paste(readLines(log), collapse = "\n")
  expect_match(txt, "^\\[\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}\\] .*API call failed: HTTP 404")
  expect_match(txt, "no such work", fixed = TRUE)
})

test_that("api_call shortens very long OpenAlex error messages", {
  long <- strrep("x", 600)
  httr2::local_mocked_responses(mock_resp(400, sprintf('{"message":"%s"}', long)))
  err <- expect_error(suppressMessages(api_call(works_req())))
  msg <- conditionMessage(err)
  expect_match(msg, paste0(strrep("x", 500), " [...]"), fixed = TRUE)
  expect_false(grepl(strrep("x", 501), msg, fixed = TRUE))
})

test_that("openalexPro.ratelimit_check prints the budget before each request", {
  urls <- character(0)
  httr2::local_mocked_responses(function(req) {
    urls <<- c(urls, req$url)
    if (grepl("rate-limit", req$url, fixed = TRUE)) {
      return(mock_resp(200, '{"rate_limit":{"daily_budget_usd":1,"daily_used_usd":0.25}}')(req))
    }
    mock_resp(200, '{"meta":{"count":1},"results":[]}')(req)
  })
  withr::local_options(openalexPro.ratelimit_check = TRUE)
  msgs <- capture_messages(resp <- api_call(works_req()))
  expect_match(msgs, "OpenAlex Rate Limit Status", all = FALSE)
  expect_match(msgs, "Daily used: +\\$0.25", all = FALSE)
  expect_equal(httr2::resp_status(resp), 200L)
  # The nested rate-limit request does not trigger another check (recursion),
  # and the option is restored afterwards.
  expect_equal(urls, c("https://api.openalex.org/rate-limit", "https://api.openalex.org/works"))
  expect_true(getOption("openalexPro.ratelimit_check"))
})

# --- pro_count ----------------------------------------------------------------

test_that("pro_count sends no API key for an empty key", {
  auth <- "unset"
  httr2::local_mocked_responses(function(req) {
    auth <<- httr2::req_get_headers(req, redacted = "reveal")$Authorization %||% NA
    mock_resp(200, '{"meta":{"count":42,"db_response_time_ms":3,"page":1,"per_page":1},"results":[]}')(req)
  })
  meta <- pro_count("https://api.openalex.org/works?filter=type:article",
                    api_key = "", via = "url")
  expect_true(is.na(auth))
  expect_equal(meta$count, 42L)
  expect_true(is.na(meta$error))
})

test_that("pro_count rejects an API key that is not a single string", {
  expect_error(
    pro_count("https://api.openalex.org/works", api_key = c("a", "b"), via = "url"),
    "`api_key` must be NULL or a length-1 character string"
  )
  expect_error(
    pro_count("https://api.openalex.org/works", api_key = 123, via = "url"),
    "`api_key` must be NULL or a length-1 character string"
  )
})

test_that("pro_count reports a too long request line as a negative count", {
  httr2::local_mocked_responses(mock_resp(400, html_400, type = "text/html"))
  # The JSON parse of the HTML page fails inside try(), which prints it
  utils::capture.output(
    meta <- suppressMessages(
      pro_count("https://api.openalex.org/works?filter=doi:x", api_key = NULL,
                via = "url")
    ),
    type = "message"
  )
  expect_equal(meta$count, -4195)
  expect_equal(meta$error, "ERROR: Request size exceeds the maximum limit of 4094.")
  expect_true(is.na(meta$page))
})

# --- pro_rate_limit_status ----------------------------------------------------

test_that("pro_rate_limit_status rejects an API key that is not a single string", {
  expect_error(
    pro_rate_limit_status(api_key = c("a", "b")),
    "`api_key` must be NULL or a length-1 character string"
  )
})

test_that("pro_rate_limit_status returns FALSE on an unexpected status", {
  httr2::local_mocked_responses(mock_resp(404, '{"message":"gone"}'))
  expect_message(
    res <- pro_rate_limit_status(api_key = "any-key"),
    "Unexpected HTTP status 404. Rate limit status could not be retrieved."
  )
  expect_false(res)
})

# --- opt_api_key --------------------------------------------------------------

test_that("opt_api_key sets the key option and returns the previous one", {
  withr::local_options(openalexPro = list(api_key = "old-key", other = 1))
  expect_equal(opt_api_key("new-key"), "old-key")
  expect_equal(opt_api_key(), "new-key")
  expect_equal(getOption("openalexPro")$other, 1) # other settings kept
  expect_equal(pro_api_key(), "new-key") # the option wins
})
