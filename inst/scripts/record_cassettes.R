# inst/scripts/record_cassettes.R
#
# Re-records ALL VCR cassettes from the live OpenAlex API.
#
# Run from the package root in an R session:
#
#   Sys.setenv(openalexPro.api_key = "your-real-key")
#   source("inst/scripts/record_cassettes.R")
#
# After recording, run devtools::test() normally (without the env var) to
# verify all tests pass in playback mode.

api_key <- pro_api_key()
if (is.null(api_key) || !nzchar(api_key) || identical(api_key, "test-api-key")) {
  stop(
    "openalexPro.api_key is not set.\n",
    "Run first: Sys.setenv(openalexPro.api_key = 'your-real-key')"
  )
}

# Fail fast on invalid keys so we do not overwrite working cassettes with 401s
key_ok <- tryCatch(
  is.list(openalexPro::pro_rate_limit_status(
    api_key = api_key,
    verbose = FALSE
  )),
  error = function(e) FALSE
)
if (!isTRUE(key_ok)) {
  stop(
    "openalexPro.api_key appears invalid (rate-limit endpoint failed).\n",
    "Not re-recording cassettes to avoid replacing them with HTTP 401 responses."
  )
}

cassette_dir <- file.path("tests", "fixtures", "vcr")
cassettes <- list.files(cassette_dir, pattern = "\\.yml$", full.names = TRUE)

message(
  "Deleting ",
  length(cassettes),
  " existing cassette(s) from ",
  cassette_dir,
  " ..."
)
file.remove(cassettes)

message("Setting OPENALEXPRO_RECORD_CASSETTES=true ...")
Sys.setenv(OPENALEXPRO_RECORD_CASSETTES = "true")
on.exit(Sys.unsetenv("OPENALEXPRO_RECORD_CASSETTES"), add = TRUE)

message("Running tests to record new cassettes ...")
# Snapshot failures are expected while recording (the live data has moved
# on since the last recording); they are reviewed afterwards. testthat stops
# after 10 failures by default, which would leave the remaining tests -- and
# their cassettes -- unrecorded.
old_max_fails <- Sys.getenv("TESTTHAT_MAX_FAILS", NA)
Sys.setenv(TESTTHAT_MAX_FAILS = Inf) # what testthat::set_max_fails() sets
devtools::test()
if (is.na(old_max_fails)) {
  Sys.unsetenv("TESTTHAT_MAX_FAILS")
} else {
  Sys.setenv(TESTTHAT_MAX_FAILS = old_max_fails)
}

new_cassettes <- list.files(
  cassette_dir,
  pattern = "\\.yml$",
  full.names = TRUE
)
message(
  "\nDone. ",
  length(new_cassettes),
  " cassette(s) written to ",
  cassette_dir,
  "."
)

# Post-process: the key is sent as a Bearer header, which helper_vcr.R masks
# when writing cassettes. As a safety net, scrub any remaining occurrence of
# the real key (plain or URL-encoded) and fail if one survives.
message("Sanitizing real API key in cassettes ...")
encoded_key <- utils::URLencode(api_key, reserved = TRUE)
for (f in new_cassettes) {
  lines <- readLines(f, warn = FALSE)
  lines <- gsub(api_key, "<api-key>", lines, fixed = TRUE)
  lines <- gsub(encoded_key, "%3Capi-key%3E", lines, fixed = TRUE)
  # /rate-limit echoes a shortened key ("abc...xyz") in its response body
  lines <- gsub('"api_key":"[^"]*"', '"api_key":"<api-key>"', lines)
  writeLines(lines, f)
}
message("Sanitized ", length(new_cassettes), " cassette(s).")
leaks <- new_cassettes[vapply(new_cassettes, function(f) {
  any(grepl(api_key, readLines(f, warn = FALSE), fixed = TRUE))
}, logical(1))]
if (length(leaks) > 0L) {
  stop("The API key is still present in: ", paste(basename(leaks), collapse = ", "))
}
message("\nCassettes recorded:")
message(paste(" -", basename(new_cassettes), collapse = "\n"))

# Checked last, so the key is always scrubbed first.
missing <- setdiff(basename(cassettes), basename(new_cassettes))
if (length(missing) > 0L) {
  stop(
    length(missing), " cassette(s) were not re-created (did the test run ",
    "stop early?):\n  ", paste(missing, collapse = "\n  ")
  )
}
