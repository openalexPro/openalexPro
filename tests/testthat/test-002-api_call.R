library(testthat)

test_that("api_call returns response object on success (200)", {
  vcr::local_cassette("api_call_200")
  req <- httr2::request("https://api.openalex.org/works/W4234567890")
  resp <- api_call(req)
  expect_equal(httr2::resp_status(resp), 200)
})

# test_that("api_call stops on Request Line too large (400)", {
#   vcr::use_cassette("api_call_400", {
#     req <- httr2::request(
#       "https://api.openalex.org/works?filter=title.search:verylongtitle"
#     )
#     expect_error(api_call(req), "HTTP status 400 Request Line is too large")
#   })
# })

# test_that("api_call stops on Too Many Requests (429)", {
#   vcr::use_cassette("api_call_429", {
#     req <- httr2::request("https://api.openalex.org/works/W4234567890")
#     # Simulate a 429 response by modifying the request headers
#     req$headers[["x-ratelimit-remaining"]] <- "0"
#     expect_error(api_call(req), "HTTP status 429 Too Many Requests")
#   })
# })

# test_that("api_call stops on Service Unavailable (503)", {
#   vcr::use_cassette("api_call_503", {
#     req <- httr2::request("https://api.openalex.org/works/INVALID")
#     # Simulate a 503 response
#     mockery::stub(api_call, "httr2::req_perform", function(...) {
#       list(status_code = 503, content = "<title>Service Unavailable</title>")
#     })
#     expect_error(
#       api_call(req),
#       paste0(
#           "Service Unavailable.\n",
#           "Please try setting `per_page = 25` in your function call!")
#     )
#     mockery::unstub(api_call, "httr2::req_perform")
#   })
# })

# test_that("api_call stops on generic error (>= 400)", {
#   vcr::use_cassette("api_call_404", {
#     req <- httr2::request("https://api.openalex.org/works/INVALID")
#     expect_error(api_call(req), "OpenAlex API request failed \\[404\\]")
#   })
# })

mock_json <- function(status, body, headers = list()) {
  function(req) {
    httr2::response(
      status,
      headers = c(list("content-type" = "application/json"), headers),
      body = charToRaw(body)
    )
  }
}

test_that("api_call includes OpenAlex's own message in a 4xx error", {
  httr2::local_mocked_responses(mock_json(
    400,
    '{"error":"Invalid query parameters error.","message":"DOESNTEXIST is not a valid field."}'
  ))
  expect_error(
    api_call(httr2::request("https://api.openalex.org/works")),
    "DOESNTEXIST is not a valid field"
  )
})

test_that("an exhausted daily budget fails at once instead of retrying", {
  calls <- 0L
  mock <- mock_json(
    429, '{"error":"Rate limit exceeded"}',
    list("x-ratelimit-remaining" = "0", "x-ratelimit-reset" = "7200")
  )
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    mock(req)
  })
  expect_error(
    api_call(httr2::request("https://api.openalex.org/works")),
    "credits left today; it resets in 2.0 h"
  )
  expect_equal(calls, 1L)
})

test_that("a not_enough_credits refusal fails at once", {
  calls <- 0L
  mock <- mock_json(
    429, '{"error":"not_enough_credits","message":"Query costs 10 credits."}',
    list("x-ratelimit-remaining" = "5")
  )
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    mock(req)
  })
  expect_error(
    api_call(httr2::request("https://api.openalex.org/works")),
    "Query costs 10 credits"
  )
  expect_equal(calls, 1L)
})

test_that("an OQL validation error shows OpenAlex's parse message", {
  httr2::local_mocked_responses(mock_json(
    400,
    '{"validation":{"valid":false,"errors":[{"type":"parse_error","message":"unexpected text near \\"wher\\" (position 6)","position":6}],"warnings":[]}}'
  ))
  expect_error(
    api_call(httr2::request("https://api.openalex.org/?oql=works%20wher")),
    "parse_error: unexpected text near \"wher\""
  )
})
