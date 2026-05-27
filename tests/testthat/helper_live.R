# Helpers for opt-in online contract tests against live OpenAlex API

.env_true <- function(var) {
  tolower(trimws(Sys.getenv(var, unset = ""))) %in% c("1", "true", "yes", "on")
}

skip_if_not_live_openalex <- function() {
  testthat::skip_on_cran()

  if (!.env_true("OPENALEXPRO_LIVE_TESTS")) {
    testthat::skip(
      "Live OpenAlex tests are disabled. Set OPENALEXPRO_LIVE_TESTS=true to enable."
    )
  }

  api_key <- pro_api_key()
  if (!nzchar(api_key) || identical(api_key, "test-api-key")) {
    testthat::skip(
      "No real API key found. Set openalexPro.apikey to run live OpenAlex tests."
    )
  }

  invisible(api_key)
}
