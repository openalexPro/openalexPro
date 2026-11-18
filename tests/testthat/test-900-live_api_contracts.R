library(testthat)

# Online-only contract tests -------------------------------------------------
#
# Run these tests manually with:
#   Sys.setenv(OPENALEXPRO_LIVE_TESTS = "true")
#   Sys.setenv(openalexPro.api_key = "your-real-key")
#   Sys.setenv(openalexPro.personal_api_key = "personal-key") # collections
#   devtools::test(filter = "900-live")


test_that("live rate-limit endpoint returns expected top-level structure", {
  api_key <- skip_if_not_live_openalex()

  result <- suppressMessages(
    pro_rate_limit_status(api_key = api_key, verbose = FALSE)
  )

  expect_type(result, "list")
  expect_true(all(c("api_key", "rate_limit") %in% names(result)))

  rl <- result$rate_limit
  expect_type(rl, "list")
  expect_true(all(
    c(
      "daily_budget_usd", "daily_used_usd", "daily_remaining_usd",
      "resets_at", "resets_in_seconds", "endpoint_costs_usd"
    ) %in% names(rl)
  ))
  expect_type(rl$endpoint_costs_usd, "list")
  expect_true(is.numeric(rl$resets_in_seconds))
})


test_that("live works request returns stable meta and result structure", {
  api_key <- skip_if_not_live_openalex()

  query_url <- pro_query(
    entity = "works",
    search = "climate change",
    options = list(per_page = 5)
  )

  output_json <- file.path(tempdir(), paste0("live_contract_", as.integer(Sys.time())))
  on.exit(unlink(output_json, recursive = TRUE, force = TRUE), add = TRUE)

  output_json <- pro_request(
    query_url = query_url,
    pages = 1,
    output = output_json,
    api_key = api_key,
    verbose = FALSE,
    progress = FALSE
  )

  # page files only: `_query.json` (the query record) sorts before them
  json_files <- list.files(output_json, pattern = "^results_page_[0-9]+\\.json$", full.names = TRUE)
  expect_true(length(json_files) >= 1)

  payload <- jsonlite::read_json(json_files[[1]], simplifyVector = FALSE)

  expect_true(is.list(payload$meta))
  expect_true(is.list(payload$results))

  expect_true(all(c("count", "per_page") %in% names(payload$meta)))

  expect_true(length(payload$results) >= 1)

  first <- payload$results[[1]]
  expect_true(all(c("id", "display_name", "ids") %in% names(first)))
  expect_match(first$id, "^https://openalex.org/W")
  expect_true(is.list(first$ids))
  expect_true("openalex" %in% names(first$ids))
})


test_that("live opt_filter_names returns non-empty character vector", {
  skip_if_not_live_openalex()

  filters <- opt_filter_names(update = TRUE)

  expect_type(filters, "character")
  expect_gt(length(filters), 0)
  expect_true(all(c("from_publication_date", "institutions.id") %in% filters))
})


test_that("live: an old cursor is still accepted (cursors are durable)", {
  api_key <- skip_if_not_live_openalex()

  # Resuming a query in the middle (`_paging.json`) relies on OpenAlex cursors
  # staying valid across sessions: they are stateless positions in the sort
  # order. This cursor was created on 2026-10-14 for this query (the start of
  # page 2, 50 per page), so every run of the live tests checks durability
  # over a longer span. If OpenAlex changes its cursor format, this fails --
  # and resume then has to fall back to fetching queries from page 1.
  cursor <- "IlsnLUluZmluaXR5JywgNDEsICdodHRwczovL29wZW5hbGV4Lm9yZy9XMjYxMzg2MjMzOSddIg=="
  url <- paste0(
    "https://api.openalex.org/works?filter=type:erratum,",
    "primary_location.source.id:S137773608,publication_year:2000-2015",
    "&select=id&per_page=50"
  )
  req <- httr2::request(url) |>
    httr2::req_url_query(cursor = cursor) |>
    .oa_auth(api_key)
  data <- httr2::resp_body_json(api_call(req))

  expect_equal(length(data$results), 50L)
  expect_false(is.null(data$meta$next_cursor))
})


test_that("live pro_collection(): create, import, member IDs, then delete", {
  skip_if_not_live_openalex()
  # Collections need a personal key; other keys get 401.
  key <- Sys.getenv("openalexPro.personal_api_key")
  if (!nzchar(key)) {
    skip("Set openalexPro.personal_api_key to a personal OpenAlex key.")
  }
  pf <- withr::local_tempdir()
  q <- pro_query("works", search = "coral bleaching", publication_year = 2024,
                 type = "review")
  f <- pro_collection(q, name = paste("openalexPro live test", Sys.time()),
                      project_folder = pf, api_key = key, progress = FALSE)
  rec <- jsonlite::read_json(file.path(f, "_collection.json"))
  withr::defer(.col_req("https://api.openalex.org", "DELETE",
                        c("collections", rec$collection_id), key, ok = c(204L, 404L)))

  expect_match(rec$collection_id, "^col_")
  expect_gt(rec$member_count, 0)
  expect_equal(rec$imports[[1]]$status, "done")
  ids <- arrow::read_parquet(file.path(f, "members/parquet/members.parquet"))
  expect_equal(nrow(ids), rec$member_count)
  expect_match(ids$id[[1]], "^W")
  # the collection works as a filter
  n <- pro_count(pro_query("works", collection = rec$collection_id), api_key = key)$count
  expect_equal(n, rec$member_count)
})
