library(testthat)
# library(httptest)

# single work ------------------------------------------------------------

output_json <- file.path(tempdir(), "single_work")
output_jsonl <- file.path(tempdir(), "single_work_jsonl")
output_parquet <- file.path(tempdir(), "single_work_parquet")

unlink(output_json, recursive = TRUE, force = TRUE)
unlink(output_jsonl, recursive = TRUE, force = TRUE)
unlink(output_parquet, recursive = TRUE, force = TRUE)

test_that("pro_request single identifier", {
  vcr::local_cassette("pro_request_single_identifier")
  # Define the API request
  output_json <- pro_query(
    entity = "works",
    id = "W2162348455"
  ) |>
    pro_request(
      pages = 1,
      output = output_json,
      verbose = FALSE,
      progress = TRUE
    )

  # Check that the output file contains the expected data (platform-agnostic)
  expect_snapshot_file(
    file.path(output_json, "single_1.json"),
    name = "json",
    compare = compare_json
  )
})

test_that("pro_request_jsonl single identifier", {
  # Convert to jsonl
  output_jsonl <- suppressWarnings(
    output_json |>
      pro_request_jsonl(
        output = output_jsonl,
        verbose = FALSE,
        progress = TRUE
      )
  )

  # Check that the output file contains the expected data (platform-agnostic)
  expect_snapshot_file(
    file.path(output_jsonl, "single_1.json"),
    name = "jsonl",
    compare = compare_jsonl
  )
})

test_that("pro_request_jsonl_parquet single identifier", {
  # Convert to parquet
  output_parquet <- suppressWarnings(
    output_jsonl |>
      pro_request_jsonl_parquet(
        output = output_parquet,
        verbose = FALSE
      )
  )

  # Check that the output file exists
  expect_true(
    length(list.files(output_parquet, "*.parquet", recursive = TRUE)) >= 1
  )

  # Check that the output file contains the expected data structure
  x <- read_corpus(
    output_parquet,
    return_data = FALSE
  )
  expect_snapshot({
    nrow(x)
    sort(names(x))
  })

  # Check that the output file contains the expected data
  # expect_snapshot_file(file.path(output_json, "results_page_1.json"))
})

unlink(output_json, recursive = TRUE, force = TRUE)
unlink(output_jsonl, recursive = TRUE, force = TRUE)
unlink(output_parquet, recursive = TRUE, force = TRUE)

test_that("resume skips a completed single query without any request", {
  tmp <- withr::local_tempdir()
  out <- file.path(tmp, "json")
  dir.create(out)
  writeLines("{}", file.path(out, "results_page_1.json"))
  # An unroutable URL: reaching the network would error.
  expect_equal(
    pro_request("http://invalid.invalid/works", output = out, resume = TRUE,
                progress = FALSE),
    normalizePath(out)
  )
  expect_true(file.exists(file.path(out, "results_page_1.json")))
})

capture_urls <- function(calls) {
  function(req) {
    calls$urls <- c(calls$urls, req$url)
    httr2::response(
      200, headers = list("content-type" = "application/json"),
      body = charToRaw('{"meta":{"count":1,"per_page":50,"next_cursor":null},"results":[{"id":"W1"}]}')
    )
  }
}

test_that("per_page in the query is kept; page and cursor are replaced with a warning", {
  calls <- new.env()
  httr2::local_mocked_responses(capture_urls(calls))
  expect_warning(
    pro_request(
      "https://api.openalex.org/works?filter=type:article&per_page=50&page=2&cursor=abc",
      output = file.path(withr::local_tempdir(), "json"), progress = FALSE
    ),
    "`page`, `cursor` in the query is replaced"
  )
  q <- httr2::url_parse(calls$urls[[1]])$query
  expect_equal(q$per_page, "50")
  expect_equal(q$cursor, "*")
  expect_null(q$page)
})

test_that("default paging is unchanged: per_page 200 with a cursor, no warning", {
  calls <- new.env()
  httr2::local_mocked_responses(capture_urls(calls))
  expect_no_warning(pro_request(
    "https://api.openalex.org/works?filter=type:article",
    output = file.path(withr::local_tempdir(), "json"), progress = FALSE
  ))
  q <- httr2::url_parse(calls$urls[[1]])$query
  expect_equal(q$per_page, "200")
  expect_equal(q$cursor, "*")
})

test_that("semantic search is fetched without cursor paging", {
  calls <- new.env()
  httr2::local_mocked_responses(capture_urls(calls))
  pro_request(
    pro_query(entity = "works", search.semantic = "coral reef bleaching"),
    output = file.path(withr::local_tempdir(), "json"), progress = FALSE
  )
  q <- httr2::url_parse(calls$urls[[1]])$query
  expect_null(q$cursor)
  expect_equal(q$per_page, "50")
  expect_length(calls$urls, 1L)
})

# A sample of `n` records, served by page number (OpenAlex ends cursor paging
# of a sample after the first page).
mock_sample <- function(calls, n) {
  function(req) {
    calls$urls <- c(calls$urls, req$url)
    q <- httr2::url_parse(req$url)$query
    pp <- as.integer(q$per_page)
    pg <- as.integer(q$page %||% 1L)
    k <- max(0L, min(pp, n - (pg - 1L) * pp))
    ids <- sprintf('{"id":"W%d"}', (pg - 1L) * pp + seq_len(k))
    httr2::response(
      200, headers = list("content-type" = "application/json"),
      body = charToRaw(sprintf(
        '{"meta":{"count":%d,"per_page":%d,"next_cursor":null},"results":[%s]}',
        n, pp, paste(ids, collapse = ",")
      ))
    )
  }
}

test_that("a sample larger than one page is paged by page number with a seed", {
  calls <- new.env()
  httr2::local_mocked_responses(mock_sample(calls, 450L))
  out <- file.path(withr::local_tempdir(), "json")
  expect_message(
    pro_request(
      "https://api.openalex.org/works?filter=type:article&sample=450",
      output = out, progress = FALSE
    ),
    "using seed = [0-9]+"
  )
  qs <- lapply(calls$urls, function(u) httr2::url_parse(u)$query)
  expect_equal(vapply(qs, `[[`, "", "page"), c("1", "2", "3"))
  expect_true(all(vapply(qs, function(q) is.null(q$cursor), logical(1))))
  seeds <- unique(vapply(qs, `[[`, "", "seed"))
  expect_length(seeds, 1L)
  expect_equal(
    sort(list.files(out, "^results_page_")),
    paste0("results_page_", 1:3, ".json")
  )
})

test_that("a given seed is kept, and a one-page sample needs none", {
  calls <- new.env()
  httr2::local_mocked_responses(mock_sample(calls, 450L))
  expect_no_message(pro_request(
    "https://api.openalex.org/works?filter=type:article&sample=450&seed=7",
    output = file.path(withr::local_tempdir(), "json"), progress = FALSE
  ))
  expect_true(all(vapply(calls$urls, function(u) httr2::url_parse(u)$query$seed == "7", logical(1))))

  calls$urls <- NULL
  httr2::local_mocked_responses(mock_sample(calls, 100L))
  expect_no_message(pro_request(
    "https://api.openalex.org/works?filter=type:article&sample=100",
    output = file.path(withr::local_tempdir(), "json"), progress = FALSE
  ))
  expect_length(calls$urls, 1L)
  expect_null(httr2::url_parse(calls$urls[[1]])$query$seed)
})

# Two pages via cursor, each costing 1 credit / $0.0001, echoing the query.
mock_two_pages <- function() {
  function(req) {
    q <- httr2::url_parse(req$url)$query
    first <- identical(q$cursor, "*")
    httr2::response(
      200,
      headers = list(
        "content-type" = "application/json",
        "x-ratelimit-credits-used" = "1",
        "x-ratelimit-cost-usd" = "0.0001"
      ),
      body = charToRaw(sprintf(
        paste0(
          '{"meta":{"count":3,"per_page":2,"next_cursor":%s,',
          '"x_query":{"oql":"get works where type is (article)",',
          '"oqo":{"get_rows":"works","filter_rows":[{"column_id":"type","value":"article"}]}}},',
          '"results":[%s]}'
        ),
        if (first) '"c2"' else "null",
        if (first) '{"id":"W1"},{"id":"W2"}' else '{"id":"W3"}'
      ))
    )
  }
}

test_that("each query gets a _query.json with the echoed query and its cost", {
  httr2::local_mocked_responses(mock_two_pages())
  out <- file.path(withr::local_tempdir(), "json")
  expect_message(
    res <- pro_request(
      "https://api.openalex.org/works?filter=type:article",
      output = out, progress = TRUE
    ),
    "2 requests, 2 credits \\(\\$0.0002\\)"
  )
  # the return value is still just the path
  expect_null(attributes(res))
  rec <- jsonlite::read_json(file.path(out, "_query.json"))
  expect_equal(rec$query_url, "https://api.openalex.org/works?filter=type:article")
  expect_equal(rec$via, "url")
  expect_equal(rec$oql, "get works where type is (article)")
  expect_equal(rec$oqo$get_rows, "works")
  expect_equal(rec$records, 3L)
  expect_equal(rec$requests, 2L)
  expect_equal(rec$credits, 2L)
  expect_equal(rec$cost_usd, 0.0002)
  expect_true(all(c("started", "finished", "openalexPro") %in% names(rec)))
})

test_that("_query.json is not converted, but carried into the parquet partition", {
  httr2::local_mocked_responses(mock_two_pages())
  tmp <- withr::local_tempdir()
  pro_fetch(
    list(articles = "https://api.openalex.org/works?filter=type:article"),
    project_folder = tmp, progress = FALSE, enrich = FALSE
  )
  # json folder deleted (delete_input = TRUE), record survives in the partition
  expect_false(dir.exists(file.path(tmp, "json")))
  rec <- file.path(tmp, "parquet", "query=articles", "_query.json")
  expect_true(file.exists(rec))
  expect_equal(jsonlite::read_json(rec)$records, 3L)
  # only the pages are data
  ds <- arrow::open_dataset(file.path(tmp, "parquet"))
  expect_equal(sort(dplyr::collect(ds)$id), c("W1", "W2", "W3"))
})
