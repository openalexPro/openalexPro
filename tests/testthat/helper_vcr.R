library("vcr")

# Normalize numeric types recursively (integer -> numeric)
# This handles the 0 vs 0.0 difference across platforms
normalize_numerics <- function(obj) {
  if (is.null(obj)) {
    return(obj)
  }
  if (is.list(obj)) {
    return(lapply(obj, normalize_numerics))
  }
  if (is.integer(obj)) {
    return(as.numeric(obj))
  }
  obj
}

# Platform-agnostic JSON comparison for expect_snapshot_file()
# Parses JSON and compares as R objects, ignoring formatting differences
compare_json <- function(old, new) {
  old_parsed <- normalize_numerics(jsonlite::read_json(
    old,
    simplifyVector = FALSE
  ))
  new_parsed <- normalize_numerics(jsonlite::read_json(
    new,
    simplifyVector = FALSE
  ))
  identical(old_parsed, new_parsed)
}

# Platform-agnostic JSONL comparison for expect_snapshot_file()
# Parses each line as JSON and compares as R objects
compare_jsonl <- function(old, new) {
  parse_jsonl <- function(path) {
    lines <- readLines(path, warn = FALSE)
    lines <- lines[nchar(trimws(lines)) > 0]
    lapply(lines, function(line) {
      normalize_numerics(jsonlite::fromJSON(line, simplifyVector = FALSE))
    })
  }
  identical(parse_jsonl(old), parse_jsonl(new))
}

# Factory function to create a JSON comparator that ignores specified fields
# Usage: compare = compare_json_ignore(c("db_response_time_ms", "updated_date"))
compare_json_ignore <- function(ignore_fields) {
  remove_fields <- function(obj, fields) {
    if (is.null(obj) || length(fields) == 0) {
      return(obj)
    }
    if (is.list(obj)) {
      obj <- obj[!names(obj) %in% fields]
      obj <- lapply(obj, remove_fields, fields = fields)
    }
    obj
  }
  function(old, new) {
    old_parsed <- normalize_numerics(jsonlite::read_json(
      old,
      simplifyVector = FALSE
    ))
    new_parsed <- normalize_numerics(jsonlite::read_json(
      new,
      simplifyVector = FALSE
    ))
    old_clean <- remove_fields(old_parsed, ignore_fields)
    new_clean <- remove_fields(new_parsed, ignore_fields)
    identical(old_clean, new_clean)
  }
}

vcr_dir <- vcr::vcr_test_path("fixtures", "vcr")
vcr::vcr_configure_log(file = file.path(vcr_dir, "vcr.log"))

# "all" re-records every cassette; triggered by record_cassettes.R script.
# "new_episodes" is the normal mode: replay existing, record only missing.
vcr_record_mode <- if (nzchar(Sys.getenv("OPENALEXPRO_RECORD_CASSETTES"))) {
  "all"
} else {
  "new_episodes"
}

if (vcr_record_mode == "all") {
  # During recording: no query-parameter filtering so the real API key is sent
  # to the server (authenticated requests). record_cassettes.R post-processes
  # the cassette files afterward to replace the real key with the placeholder.
  invisible(vcr::vcr_configure(
    dir = vcr_dir,
    record = vcr_record_mode
  ))
} else {
  # During playback: filter_query_parameters normalises api_key in incoming
  # requests so they match the <api-key> placeholder stored in cassettes.
  invisible(vcr::vcr_configure(
    dir = vcr_dir,
    record = vcr_record_mode,
    filter_request_headers = list(api_key = "<api-key>"),
    filter_query_parameters = list(api_key = "<api-key>")
  ))
}

# Ensure a dummy API key is set so validation passes during VCR-recorded tests
if (!nzchar(pro_api_key())) {
  Sys.setenv(openalexPro.apikey = "test-api-key")
}

# try(
#   {
#     Sys.setenv(openalexPro.apikey = keyring::key_get("API_openalex"))
#     Sys.setenv(openalexPro.email = "Rainer@krugs.de")
#   }
# )

# if (!openalexPro::pro_validate_credentials()) {
#   stop("invalid credentials!")
# }
