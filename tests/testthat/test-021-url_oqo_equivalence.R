library(testthat)

# The same query sent as a URL (GET) and as an OQO (POST) must return the same
# records. Every case below is small enough (<= 400 results, i.e. at most two
# pages) that the complete result sets are compared, not just counts.
#
# Recorded with vcr: the first run (or inst/scripts/record_cassettes.R) talks to
# the live API, so the comparison was made against real data; later runs replay
# it. Both requests of a case are in one cassette (GET and POST are matched on
# method, URI and body).

# Record IDs (or group keys with counts) of all pages in a download
downloaded_ids <- function(dir) {
  files <- list.files(
    dir, "^(results_page|group_by_page|single)_[0-9]+\\.json$",
    recursive = TRUE, full.names = TRUE
  )
  unlist(lapply(files, function(f) {
    j <- jsonlite::fromJSON(f, simplifyVector = FALSE)
    if (length(j$group_by) > 0) {
      vapply(j$group_by, function(g) paste0(g$key, "=", g$count), "")
    } else if (!is.null(j$results)) {
      vapply(j$results, function(r) r$id, "")
    } else {
      j$id
    }
  }))
}

fetch_both <- function(query_url) {
  run <- function(via) {
    out <- tempfile("equiv_")
    on.exit(unlink(out, recursive = TRUE))
    suppressMessages(pro_request(query_url, output = out, progress = FALSE, via = via))
    downloaded_ids(out)
  }
  list(url = run("url"), oqo = run("oqo"))
}

expect_same_records <- function(res, min_n = 1L) {
  expect_gte(length(res$url), min_n)
  expect_equal(length(res$oqo), length(res$url))
  expect_setequal(res$oqo, res$url)
}

nature <- "S137773608"

test_that("url and oqo: filters, two pages", {
  vcr::local_cassette("equiv_filter_2pages")
  res <- fetch_both(pro_query(
    entity = "works", publication_year = "2018-2020", type = "erratum",
    `primary_location.source.id` = nature, select = "id"
  ))
  expect_same_records(res, min_n = 201L) # spans two pages
})

test_that("url and oqo: boolean search", {
  vcr::local_cassette("equiv_boolean")
  expect_same_records(fetch_both(pro_query(
    entity = "works", search = "(coral OR reef) AND bleaching NOT model",
    publication_year = 2020, is_oa = TRUE, type = "article", select = "id"
  )), min_n = 201L)
})

test_that("url and oqo: wildcard (search.exact)", {
  vcr::local_cassette("equiv_wildcard")
  expect_same_records(fetch_both(pro_query(
    entity = "works", search.exact = "microbio*", publication_year = 2020,
    `primary_location.source.id` = nature, select = "id"
  )))
})

test_that("url and oqo: proximity", {
  vcr::local_cassette("equiv_proximity")
  expect_same_records(fetch_both(pro_query(
    entity = "works", search = '"climate change"~5', publication_year = 2020,
    `primary_location.source.id` = nature, select = "id"
  )))
})

test_that("url and oqo: sample with seed, two pages", {
  vcr::local_cassette("equiv_sample")
  expect_same_records(fetch_both(pro_query(
    entity = "works", publication_year = 2020, select = "id",
    options = list(sample = 300, seed = 42)
  )), min_n = 300L)
})

test_that("url and oqo: grouped results", {
  vcr::local_cassette("equiv_grouped")
  expect_same_records(fetch_both(pro_query(
    entity = "works", publication_year = 2020,
    `primary_location.source.id` = nature, group_by = "type"
  )))
})

test_that("url and oqo: other entity with an entity-specific filter", {
  vcr::local_cassette("equiv_authors")
  expect_same_records(fetch_both(pro_query(
    entity = "authors", `last_known_institutions.id` = "I4200000001",
    select = "id"
  )))
})

test_that("url and oqo: chunked DOI list", {
  vcr::local_cassette("equiv_dois")
  dois <- readRDS(testthat::test_path("..", "fixtures", "dois.rds"))
  expect_same_records(fetch_both(pro_query(entity = "works", doi = dois, select = "id")),
                      min_n = 101L)
})

test_that("url and oqo: single record (stays GET)", {
  vcr::local_cassette("equiv_singleton")
  expect_same_records(fetch_both(pro_query(entity = "works", id = "W2741809807")))
})

test_that("url and oqo: semantic search (OpenAlex varies at the 50th place)", {
  vcr::local_cassette("equiv_semantic")
  res <- fetch_both(pro_query(
    entity = "works", search.semantic = "coral reef bleaching and ocean warming",
    select = "id"
  ))
  # Repeating the identical GET request alone returns sets that differ in
  # about one work; demand near-identity, not identity.
  expect_equal(length(res$url), 50L)
  expect_equal(length(res$oqo), 50L)
  expect_gte(length(intersect(res$url, res$oqo)), 45L)
})

test_that("OQL and OQO input give the same records as the classic URL", {
  vcr::local_cassette("equiv_oql_oqo_input")
  classic <- fetch_both(pro_query(
    entity = "works", publication_year = "2018-2020", type = "erratum",
    `primary_location.source.id` = nature, select = "id"
  ))$url
  # the OQL OpenAlex itself renders for the classic filter
  oql <- paste(
    "get works where source is [Nature](S137773608) and",
    "published from 2018 through 2020 and type is [erratum](erratum)"
  )
  from_oql <- fetch_both(pro_query(oql = oql, select = "id"))
  from_oqo <- fetch_both(pro_query(oqo = list(
    get_rows = "works",
    filter_rows = list(
      list(column_id = "primary_location.source.id", value = nature),
      list(column_id = "publication_year", value = 2018, operator = ">="),
      list(column_id = "publication_year", value = 2020, operator = "<="),
      list(column_id = "type", value = "erratum")
    )
  ), select = "id"))
  for (x in c(from_oql, from_oqo)) {
    expect_equal(length(x), length(classic))
    expect_setequal(x, classic)
  }
})

test_that("pro_count gives the same count via url and oqo", {
  vcr::local_cassette("equiv_count")
  queries <- list(
    filter = pro_query(entity = "works", publication_year = "2018-2020",
                       type = "erratum", `primary_location.source.id` = nature),
    boolean = pro_query(entity = "works",
                        search = "(coral OR reef) AND bleaching NOT model",
                        publication_year = 2020),
    authors = pro_query(entity = "authors",
                        `last_known_institutions.id` = "I4200000001")
  )
  for (q in queries) {
    via_url <- pro_count(q, via = "url")
    via_oqo <- pro_count(q, via = "oqo")
    expect_gt(via_url$count, 0)
    expect_equal(via_oqo$count, via_url$count)
  }
})

# Unit tests of the OQO route (mocked) -------------------------------------

# /query echoes a fixed OQO; POST / answers with the page asked for.
mock_oqo_api <- function(log) {
  log$requests <- list()
  function(req) {
    # the JSON body exactly as it would be sent
    body <- if (!is.null(req$body$data)) {
      jsonlite::fromJSON(
        jsonlite::toJSON(req$body$data, auto_unbox = TRUE),
        simplifyVector = FALSE
      )
    }
    log$requests[[length(log$requests) + 1L]] <- list(
      method = req$method %||% "GET", url = req$url, body = body
    )
    path <- httr2::url_parse(req$url)$path
    if (identical(path, "/query")) {
      if (!is.null(body$oxurl) && grepl("INVALID", body$oxurl)) {
        return(httr2::response(400, headers = list("content-type" = "application/json"),
          body = charToRaw('{"oqo":null,"validation":{"valid":false,"errors":[{"type":"bad_request","message":"INVALID is not a valid field"}]}}')))
      }
      return(httr2::response(200, headers = list("content-type" = "application/json"),
        body = charToRaw('{"oql_oneline":"get works where type is (article)","oqo":{"get_rows":"works","filter_rows":[{"column_id":"type","value":"article"}]},"validation":{"valid":true,"errors":[]}}')))
    }
    first <- identical(body$cursor, "*") || identical(body$page, 1L)
    httr2::response(200, headers = list("content-type" = "application/json"),
      body = charToRaw(sprintf(
        '{"meta":{"count":3,"per_page":2,"next_cursor":%s},"results":[%s]}',
        if (first && !is.null(body$cursor)) '"c2"' else "null",
        if (first) '{"id":"W1"},{"id":"W2"}' else '{"id":"W3"}'
      )))
  }
}

test_that("via = 'oqo' translates once, then POSTs the OQO with cursor paging", {
  log <- new.env()
  httr2::local_mocked_responses(mock_oqo_api(log))
  out <- file.path(withr::local_tempdir(), "json")
  pro_request(
    "https://api.openalex.org/works?filter=type:article&select=id,doi&sort=cited_by_count:desc&per_page=2",
    output = out, progress = FALSE, via = "oqo"
  )
  all <- log$requests
  is_query <- vapply(all, function(x) httr2::url_parse(x$url)$path == "/query", TRUE)
  # translation first, then the pages, then the two calls for the readable OQL
  # (render the OQO that ran, translate the OQL back)
  expect_equal(is_query, c(TRUE, FALSE, FALSE, TRUE, TRUE))
  expect_false(is.null(all[[4]]$body$oqo))
  expect_false(is.null(all[[5]]$body$oql))
  r <- all
  # 1. translation: paging and view parameters removed from the URL
  expect_equal(httr2::url_parse(r[[1]]$url)$path, "/query")
  expect_equal(utils::URLdecode(r[[1]]$body$oxurl), "/works?filter=type:article")
  # 2./3. POST / with the OQO, view parameters alongside, cursor paging
  expect_equal(r[[2]]$method, "POST")
  expect_equal(r[[2]]$body$oqo$get_rows, "works")
  expect_equal(r[[2]]$body$select, "id,doi")
  expect_equal(r[[2]]$body$sort, "cited_by_count:desc")
  expect_equal(r[[2]]$body$per_page, 2L)
  expect_equal(r[[2]]$body$cursor, "*")
  expect_equal(r[[3]]$body$cursor, "c2")
  expect_null(r[[3]]$body$page)
  rec <- jsonlite::read_json(file.path(out, "_query.json"))
  expect_equal(rec$via, "oqo")
  expect_equal(rec$oql, "get works where type is (article)")
  expect_equal(rec$records, 3L)
})

test_that("via = 'oqo' puts sample (number) and seed (text) into the OQO and pages by number", {
  log <- new.env()
  httr2::local_mocked_responses(mock_oqo_api(log))
  pro_request(
    "https://api.openalex.org/works?filter=type:article&sample=3&seed=7&per_page=2",
    output = file.path(withr::local_tempdir(), "json"), progress = FALSE, via = "oqo"
  )
  r <- log$requests
  expect_false(grepl("sample|seed", r[[1]]$body$oxurl))
  expect_identical(r[[2]]$body$oqo$sample, 3L)
  expect_identical(r[[2]]$body$oqo$seed, "7")
  expect_equal(c(r[[2]]$body$page, r[[3]]$body$page), c(1L, 2L))
  expect_null(r[[2]]$body$cursor)
})

test_that("an invalid query stops before any credits are spent", {
  log <- new.env()
  httr2::local_mocked_responses(mock_oqo_api(log))
  expect_error(
    pro_request("https://api.openalex.org/works?filter=INVALID:1",
                output = file.path(withr::local_tempdir(), "json"),
                progress = FALSE, via = "oqo"),
    "INVALID is not a valid field"
  )
  # only the free translation was called
  expect_length(log$requests, 1L)
  expect_equal(httr2::url_parse(log$requests[[1]]$url)$path, "/query")
})

test_that("more than 100 values per filter: stopped for url, sent for oqo", {
  many <- paste0("https://api.openalex.org/works?filter=doi:",
                 paste0("10.1/x", 1:150, collapse = "|"))
  expect_error(
    pro_request(many, output = file.path(withr::local_tempdir(), "json"),
                progress = FALSE),
    "has 150 values.*chunk_limit"
  )
  log <- new.env()
  httr2::local_mocked_responses(mock_oqo_api(log))
  expect_no_error(pro_request(many, output = file.path(withr::local_tempdir(), "json"),
                              progress = FALSE, via = "oqo"))
})
