# inst/scripts/record_cassettes.R
#
# Re-records ALL VCR cassettes from the live OpenAlex API.
#
# Run from the package root in an R session:
#
#   Sys.setenv(openalexPro.apikey = "your-real-key")
#   source("inst/scripts/record_cassettes.R")
#
# After recording, run devtools::test() normally (without the env var) to
# verify all tests pass in playback mode.

api_key <- pro_api_key()
if (!nzchar(api_key)) {
  stop(
    "openalexPro.apikey is not set.\n",
    "Run first: Sys.setenv(openalexPro.apikey = 'your-real-key')"
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
    "openalexPro.apikey appears invalid (rate-limit endpoint failed).\n",
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
devtools::test()

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

# Post-process: replace the real API key with the placeholder used in
# playback matching.  The helper_vcr.R skips filter_query_parameters during
# recording so that authenticated requests reach the server; we scrub the key
# from the stored YAML files here instead.
message("Sanitizing real API key in cassettes ...")
encoded_key <- utils::URLencode(api_key, reserved = TRUE)
for (f in new_cassettes) {
  lines <- readLines(f, warn = FALSE)
  lines <- gsub(api_key, "<api-key>", lines, fixed = TRUE)
  lines <- gsub(encoded_key, "%3Capi-key%3E", lines, fixed = TRUE)
  writeLines(lines, f)
}
message("Sanitized ", length(new_cassettes), " cassette(s).")
message("\nCassettes recorded:")
message(paste(" -", basename(new_cassettes), collapse = "\n"))
