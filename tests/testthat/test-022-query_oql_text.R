library(testthat)

# The readable OQL files (_query_oql.txt / _query_oql.html) written next to
# _query.json. OpenAlex is mocked: a list page that echoes the query it ran
# (meta$x_query), and /query, which renders an OQO as OQL and translates OQL
# back to an OQO.

ran_oqo <- list(
  get_rows = "works",
  filter_rows = list(
    list(column_id = "type", value = "article"),
    list(column_id = "primary_location.source.id", value = "S137773608")
  )
)

mock_api <- function(oql, back_oqo = ran_oqo, query_status = 200) {
  json <- function(x) charToRaw(as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null")))
  function(req) {
    path <- httr2::url_parse(req$url)$path
    body <- req$body$data
    if (identical(path, "/query")) {
      if (query_status != 200) {
        return(httr2::response(query_status, headers = list("content-type" = "text/html"),
                               body = charToRaw("<html>not here</html>")))
      }
      out <- if (!is.null(body$oqo)) {
        list(oql = oql, oql_oneline = gsub("\n *", " ", oql), oqo = body$oqo,
             validation = list(valid = TRUE))
      } else {
        list(oqo = back_oqo, validation = list(valid = TRUE))
      }
      return(httr2::response(200, headers = list("content-type" = "application/json"), body = json(out)))
    }
    httr2::response(200, headers = list("content-type" = "application/json"), body = json(list(
      meta = list(count = 2, per_page = 200, next_cursor = NULL,
                  x_query = list(oql = gsub("\n *", " ", oql), oqo = ran_oqo)),
      results = list(list(id = "W1"), list(id = "W2"))
    )))
  }
}

oql_nature <- "get works where type is [article](article)\n  and source is [Nature](S137773608)"

download <- function() {
  out <- file.path(withr::local_tempdir(.local_envir = parent.frame()), "json")
  pro_request("https://api.openalex.org/works?filter=type:article,primary_location.source.id:S137773608",
              output = out, progress = FALSE)
  out
}

test_that("_query_oql.txt holds OpenAlex's multi-line OQL and says it is exact", {
  httr2::local_mocked_responses(mock_api(oql_nature))
  out <- download()
  txt <- readLines(file.path(out, "_query_oql.txt"))
  expect_equal(txt[1], "# OpenAlex query (OQL)")
  expect_match(txt[2], "Records: 2 \\| Downloaded: \\d{4}-\\d{2}-\\d{2} \\(UTC\\) \\| openalexPro ")
  expect_match(txt[3], "^# Exact: ")
  expect_equal(tail(txt, 2), strsplit(oql_nature, "\n")[[1]])
})

test_that("conditions in a different order still count as exact", {
  reordered <- ran_oqo
  reordered$filter_rows <- rev(reordered$filter_rows)
  httr2::local_mocked_responses(mock_api(oql_nature, back_oqo = reordered))
  out <- download()
  expect_match(readLines(file.path(out, "_query_oql.txt"))[3], "^# Exact: ")
})

test_that("an OQL that does not translate back to the same query is marked", {
  lossy <- ran_oqo
  lossy$filter_rows[[1]]$value <- "review"
  httr2::local_mocked_responses(mock_api(oql_nature, back_oqo = lossy))
  out <- download()
  expect_match(readLines(file.path(out, "_query_oql.txt"))[3], "^# Not exact: .*OQO in _query.json")
  expect_match(paste(readLines(file.path(out, "_query_oql.html")), collapse = "\n"),
               'class="note inexact"')
})

test_that("without /query the OQL echoed by the API is used, marked as not checked", {
  httr2::local_mocked_responses(mock_api(oql_nature, query_status = 404))
  out <- download()
  txt <- readLines(file.path(out, "_query_oql.txt"))
  expect_match(txt[3], "^# Not checked: ")
  expect_equal(tail(txt, 1), gsub("\n *", " ", oql_nature))
  # the download itself is unaffected
  expect_true(file.exists(file.path(out, "results_page_1.json")))
})

test_that("the HTML highlights keywords, links OpenAlex IDs and is self-contained", {
  httr2::local_mocked_responses(mock_api(oql_nature))
  out <- download()
  html <- paste(readLines(file.path(out, "_query_oql.html")), collapse = "\n")
  expect_match(html, '<span class="kw">where</span>', fixed = TRUE)
  expect_match(html, '<a class="label" href="https://openalex.org/S137773608" title="S137773608">Nature</a>', fixed = TRUE)
  expect_match(html, '<span class="label" title="article">article</span>', fixed = TRUE)
  expect_match(html, '"get_rows": "works"', fixed = TRUE) # the OQO
  expect_false(grepl("<script|<link|src=", html))
})

test_that("OQL text is escaped in the HTML", {
  nasty <- 'get works where cited by count < (5) and title has ("<script>alert(1)</script>" AND x)'
  html <- paste(.oql_html(nasty, list(records = 1, date = "2026-01-01", version = "x", exact = TRUE),
                          ran_oqo, "https://api.openalex.org/works?a=<b>"), collapse = "\n")
  expect_false(grepl("<script>", html, fixed = TRUE))
  expect_match(html, "&lt; ", fixed = TRUE)
  expect_match(html, '<span class="str">&quot;&lt;script&gt;alert(1)&lt;/script&gt;&quot;</span>', fixed = TRUE)
  expect_match(html, '<span class="bool">AND</span>', fixed = TRUE)
})

test_that("the readable files are carried into the parquet partition", {
  httr2::local_mocked_responses(mock_api(oql_nature))
  tmp <- withr::local_tempdir()
  pro_fetch(list(nature = "https://api.openalex.org/works?filter=type:article,primary_location.source.id:S137773608"),
            project_folder = tmp, progress = FALSE, enrich = FALSE)
  part <- file.path(tmp, "parquet", "query=nature")
  expect_true(all(file.exists(file.path(part, c("_query.json", "_query_oql.txt", "_query_oql.html")))))
  # still only the pages are data
  expect_equal(sort(dplyr::collect(arrow::open_dataset(file.path(tmp, "parquet")))$id), c("W1", "W2"))
})

test_that("a single record gets no OQL files (nothing to describe)", {
  httr2::local_mocked_responses(function(req) {
    httr2::response(200, headers = list("content-type" = "application/json"),
                    body = charToRaw('{"id":"https://openalex.org/W1","title":"x"}'))
  })
  out <- file.path(withr::local_tempdir(), "json")
  pro_request("https://api.openalex.org/works/W1", output = out, progress = FALSE)
  expect_false(file.exists(file.path(out, "_query_oql.txt")))
})

# Summary of all queries (_queries_oql.txt / .html) ---------------------------

# mock_api(), plus one query that fails (HTTP 404)
mock_api_with_failure <- function(oql) {
  ok <- mock_api(oql)
  function(req) {
    if (grepl("doi:bad", utils::URLdecode(req$url), fixed = TRUE)) {
      return(httr2::response(404, headers = list("content-type" = "application/json"),
                             body = charToRaw('{"error":"Not found","message":"Not found"}')))
    }
    ok(req)
  }
}

q_ok <- "https://api.openalex.org/works?filter=type:article,primary_location.source.id:S137773608"
q_bad <- "https://api.openalex.org/works?filter=doi:bad"

test_that("a list download writes one summary of all queries, in list order", {
  httr2::local_mocked_responses(mock_api_with_failure(oql_nature))
  out <- file.path(withr::local_tempdir(), "json")
  expect_error(
    pro_request(list(zeta = q_ok, alpha = q_ok, broken = q_bad),
                output = out, progress = FALSE),
    "1 of 3 queries failed"
  )
  txt <- readLines(file.path(out, "_queries_oql.txt"))
  expect_equal(txt[1], "# OpenAlex queries (OQL)")
  expect_match(txt[2], "^# 3 queries \\| 4 records \\| exact: 2 of 2 \\| ")
  # list order, not alphabetical; the failed query is listed
  expect_equal(
    grep("^## ", txt, value = TRUE),
    c("## zeta | 2 records | Exact", "## alpha | 2 records | Exact",
      "## broken | - records | Not downloaded")
  )
  # each query's OQL follows its heading
  i <- which(txt == "## zeta | 2 records | Exact")
  expect_equal(txt[i + 1:2], strsplit(oql_nature, "\n")[[1]])

  html <- paste(readLines(file.path(out, "_queries_oql.html")), collapse = "\n")
  expect_match(html, '<td><a href="#q1">zeta</a></td>', fixed = TRUE)
  expect_match(html, '<h2 id="q3">broken <span class="badge missing">Not downloaded</span></h2>', fixed = TRUE)
  expect_match(html, '<a class="label" href="https://openalex.org/S137773608"', fixed = TRUE)
  expect_false(grepl("<script|<link|src=", html))
})

test_that("the summary includes queries skipped by resume", {
  httr2::local_mocked_responses(mock_api(oql_nature))
  out <- file.path(withr::local_tempdir(), "json")
  pro_request(list(a = q_ok, b = q_ok), output = out, progress = FALSE)
  unlink(file.path(out, "_queries_oql.txt"))
  unlink(file.path(out, "b"), recursive = TRUE) # b must be fetched again, a is skipped
  pro_request(list(a = q_ok, b = q_ok), output = out, progress = FALSE, resume = TRUE)
  expect_equal(
    grep("^## ", readLines(file.path(out, "_queries_oql.txt")), value = TRUE),
    c("## a | 2 records | Exact", "## b | 2 records | Exact")
  )
})

test_that("the summary is carried to the top of the parquet folder", {
  httr2::local_mocked_responses(mock_api(oql_nature))
  tmp <- withr::local_tempdir()
  pro_fetch(list(a = q_ok, b = q_ok), project_folder = tmp, progress = FALSE, enrich = FALSE)
  expect_true(all(file.exists(file.path(tmp, "parquet", c("_queries_oql.txt", "_queries_oql.html")))))
  expect_equal(nrow(dplyr::collect(arrow::open_dataset(file.path(tmp, "parquet")))), 4L)
})

test_that("a single URL gets no summary (its own files are at the top)", {
  httr2::local_mocked_responses(mock_api(oql_nature))
  out <- file.path(withr::local_tempdir(), "json")
  pro_request(q_ok, output = out, progress = FALSE)
  expect_false(file.exists(file.path(out, "_queries_oql.txt")))
  expect_true(file.exists(file.path(out, "_query_oql.txt")))
})
