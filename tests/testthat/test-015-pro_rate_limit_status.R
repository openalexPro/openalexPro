library(testthat)

# --- missing API key -----------------------------------------------------------

test_that("pro_rate_limit_status returns FALSE invisibly when api_key is empty", {
  result <- withCallingHandlers(
    pro_rate_limit_status(api_key = ""),
    message = function(m) invokeRestart("muffleMessage")
  )
  expect_false(result)
})

test_that("pro_rate_limit_status emits message when api_key is empty", {
  expect_message(
    pro_rate_limit_status(api_key = ""),
    "No API key found"
  )
})

# --- invalid API key (401) ----------------------------------------------------

test_that("pro_rate_limit_status returns FALSE invisibly on 401", {
  vcr::local_cassette("pro_rate_limit_status_401")
  result <- withCallingHandlers(
    pro_rate_limit_status(api_key = "bad-key"),
    message = function(m) invokeRestart("muffleMessage")
  )
  expect_false(result)
})

test_that("pro_rate_limit_status emits message on 401", {
  vcr::local_cassette("pro_rate_limit_status_401")
  expect_message(
    pro_rate_limit_status(api_key = "bad-key"),
    "Invalid API key"
  )
})

# --- successful response (200) ------------------------------------------------

test_that("pro_rate_limit_status returns a list invisibly on success", {
  vcr::local_cassette("pro_rate_limit_status_200")
  result <- suppressMessages(pro_rate_limit_status(api_key = pro_api_key()))
  expect_type(result, "list")
  # api_key and rate_limit are always present; is_grandfathered may appear too
  expect_true(all(c("api_key", "rate_limit") %in% names(result)))
})

test_that("pro_rate_limit_status result contains expected rate_limit fields", {
  vcr::local_cassette("pro_rate_limit_status_200")
  result <- suppressMessages(pro_rate_limit_status(api_key = pro_api_key()))
  rl <- result$rate_limit
  expect_true(all(
    c(
      "daily_budget_usd",
      "daily_used_usd",
      "daily_remaining_usd",
      "prepaid_balance_usd",
      "prepaid_remaining_usd",
      "resets_at",
      "resets_in_seconds",
      "endpoint_costs_usd"
    ) %in%
      names(rl)
  ))
  # Exact values depend on the API key tier; just check they are non-negative numbers
  expect_true(is.numeric(rl$daily_budget_usd) && rl$daily_budget_usd >= 0)
  expect_true(is.numeric(rl$daily_remaining_usd) && rl$daily_remaining_usd >= 0)
})

test_that("pro_rate_limit_status prints rate limit info when verbose = TRUE", {
  vcr::local_cassette("pro_rate_limit_status_200")
  expect_message(
    pro_rate_limit_status(api_key = pro_api_key(), verbose = TRUE),
    "OpenAlex Rate Limit Status"
  )
})

test_that("pro_rate_limit_status is silent when verbose = FALSE", {
  vcr::local_cassette("pro_rate_limit_status_200")
  expect_no_message(
    pro_rate_limit_status(api_key = pro_api_key(), verbose = FALSE)
  )
})

# --- network error ------------------------------------------------------------

test_that("pro_rate_limit_status returns NULL on network error", {
  local_mocked_bindings(
    req_perform = function(...) stop("Connection refused"),
    .package = "httr2"
  )
  result <- withCallingHandlers(
    pro_rate_limit_status(api_key = "any-key"),
    message = function(m) invokeRestart("muffleMessage")
  )
  expect_null(result)
})

test_that("pro_rate_limit_status emits message on network error", {
  local_mocked_bindings(
    req_perform = function(...) stop("Connection refused"),
    .package = "httr2"
  )
  expect_message(
    pro_rate_limit_status(api_key = "any-key"),
    "Request failed"
  )
})
