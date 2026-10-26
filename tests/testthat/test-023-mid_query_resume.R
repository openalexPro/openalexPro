library(testthat)

# Resuming an interrupted query in the middle (_paging.json), and the check
# for inconsistencies after a resume (inconsistency_on_resume).
#
# The mock is a paged API serving records W1..Wn, two per page. Cursor "*" is
# offset 0, "c<k>" offset k (from the URL, or the POST body for via = "oqo");
# a sample is paged by `page`. It can fail (HTTP 404, not retried) at an
# offset -- the interruption --, report another count, or put an extra
# (duplicate) record on a page.

mock_cursor <- function(log, n = 5, fail_at = NULL, fail_if = NULL,
                        count = n, extra = NULL, grouped = FALSE) {
  log$requests <- list()
  function(req) {
    u <- httr2::url_parse(req$url)
    body <- if (!is.null(req$body$data)) {
      jsonlite::fromJSON(jsonlite::toJSON(req$body$data, auto_unbox = TRUE),
                         simplifyVector = FALSE)
    }
    cursor <- u$query$cursor %||% body$cursor
    log$requests[[length(log$requests) + 1L]] <- list(
      path = u$path, cursor = cursor %||% NA_character_,
      page = u$query$page %||% body$page, body = body, url = req$url
    )
    respond <- function(x, status = 200, cost = TRUE) {
      h <- list("content-type" = "application/json")
      if (cost) h <- c(h, list("x-ratelimit-credits-used" = "1", "x-ratelimit-cost-usd" = "0.0001"))
      httr2::response(status, headers = h,
        body = charToRaw(as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"))))
    }
    if (identical(u$path, "/query")) { # translation and OQL rendering
      return(respond(list(
        oqo = body$oqo %||% list(get_rows = "works",
                                 filter_rows = list(list(column_id = "type", value = "article"))),
        oql = "get works where type is (article)",
        oql_oneline = "get works where type is (article)",
        validation = list(valid = TRUE, errors = list())
      ), cost = FALSE))
    }
    per_page <- as.integer(u$query$per_page %||% body$per_page %||% 2L)
    page <- u$query$page %||% body$page
    offset <- if (!is.null(page)) {
      (as.integer(page) - 1L) * per_page
    } else if (identical(cursor, "*")) 0L else as.integer(sub("^c", "", cursor))
    hit <- is.null(fail_if) || grepl(fail_if, utils::URLdecode(req$url), fixed = TRUE)
    if (!is.null(fail_at) && offset == fail_at && hit) {
      return(respond(list(error = "x", message = "interrupted"), status = 404, cost = FALSE))
    }
    idx <- if (offset < n) seq(offset + 1L, min(offset + per_page, n)) else integer(0)
    more <- if (grouped) offset < n else offset + per_page < n
    next_cursor <- if (is.null(page) && more) paste0("c", offset + per_page)
    rows <- lapply(idx, function(i) {
      if (grouped) list(key = paste0("g", i), count = 1L) else list(id = paste0("W", i))
    })
    if (!is.null(extra) && extra$offset == offset) rows <- c(rows, list(list(id = extra$id)))
    meta <- list(count = count, per_page = per_page, next_cursor = next_cursor,
                 groups_count = if (grouped) length(idx) else NULL)
    respond(if (grouped) list(meta = meta, group_by = rows) else list(meta = meta, results = rows))
  }
}

# The cursors of the page requests (translation / OQL requests left out)
page_requests <- function(log) Filter(function(r) !identical(r$path, "/query"), log$requests)
page_cursors <- function(log) vapply(page_requests(log), function(r) r$cursor, "")

ids_in <- function(out, prefix = "results_page_") {
  files <- list.files(out, paste0("^", prefix, "[0-9]+\\.json$"), full.names = TRUE)
  files <- files[order(as.integer(sub(".*_([0-9]+)\\.json$", "\\1", files)))]
  unlist(lapply(files, function(f) {
    j <- jsonlite::read_json(f)
    vapply(j$results %||% j$group_by, function(r) r$id %||% r$key, "")
  }))
}

q_url <- "https://api.openalex.org/works?filter=type:article&per_page=2"

# Session 1: interrupted at offset 4 (page 3); pages 1 and 2 are saved.
# `...` goes to the mock (n, grouped, ...).
interrupted <- function(out, url = q_url, via = "url", ...) {
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log, fail_at = 4L, ...))
  expect_error(pro_request(url, output = out, progress = FALSE, via = via), "404")
  log
}

test_that("an interrupted download leaves _paging.json with the position", {
  out <- file.path(withr::local_tempdir(), "json")
  interrupted(out, url = paste0(q_url, "&api_key=secret"))
  st <- jsonlite::read_json(file.path(out, "_paging.json"))
  expect_equal(st$page, 2L)
  expect_equal(st$status, "downloading")
  expect_match(st$cursor_created, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
  expect_false(grepl("secret", paste(readLines(file.path(out, "_paging.json")), collapse = "")))
  expect_true(file.exists(file.path(out, "00_in.progress")))
})

test_that("resume continues at the saved cursor and says how old it is", {
  out <- file.path(withr::local_tempdir(), "json")
  interrupted(out)
  page1 <- readLines(file.path(out, "results_page_1.json"))
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log))
  expect_message(
    pro_request(via = "url", q_url, output = out, progress = FALSE, resume = TRUE),
    "Resuming .*page 3.*cursor from .*ago"
  )
  expect_equal(page_cursors(log), "c4") # only the missing page
  expect_equal(ids_in(out), paste0("W", 1:5))
  expect_equal(readLines(file.path(out, "results_page_1.json")), page1)
  expect_false(file.exists(file.path(out, "_paging.json")))
  expect_false(file.exists(file.path(out, "00_in.progress")))
  rec <- jsonlite::read_json(file.path(out, "_query.json"))
  expect_equal(rec$requests, 3L) # 2 + 1 over both sessions
  expect_equal(rec$credits, 3L)
  expect_length(rec$resumed, 1L)
  expect_equal(rec$records_saved, 5L)
})

test_that("in a list, only the interrupted query continues", {
  out <- file.path(withr::local_tempdir(), "json")
  qs <- list(a = q_url, b = sub("article", "book", q_url))
  log1 <- new.env()
  local({
    httr2::local_mocked_responses(mock_cursor(log1, fail_at = 4L, fail_if = "type:book"))
    expect_error(pro_request(via = "url", qs, output = out, progress = FALSE), "1 of 2 queries failed")
  })
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log))
  suppressMessages(pro_request(via = "url", qs, output = out, progress = FALSE, resume = TRUE))
  expect_equal(page_cursors(log), "c4")
  expect_true(grepl("type:book", utils::URLdecode(page_requests(log)[[1]]$url), fixed = TRUE))
  expect_equal(ids_in(file.path(out, "b")), paste0("W", 1:5))
})

test_that("via = 'oqo': every continued page sends the identical OQO, no translation", {
  out <- file.path(withr::local_tempdir(), "json")
  url <- paste0(q_url, "&select=id&sort=cited_by_count:desc")
  log1 <- interrupted(out, url = url, via = "oqo")
  first <- page_requests(log1)[[1]]$body
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log))
  suppressMessages(pro_request(url, output = out, progress = FALSE, resume = TRUE, via = "oqo"))
  expect_equal(log$requests[[1]]$path, "/") # no translation first
  cont <- page_requests(log)[[1]]$body
  expect_equal(cont$cursor, "c4")
  expect_identical(cont$oqo, first$oqo)
  expect_identical(cont[c("select", "sort", "per_page")], first[c("select", "sort", "per_page")])
  expect_equal(ids_in(out), paste0("W", 1:5))
})

test_that("grouped results continue at the saved group key", {
  out <- file.path(withr::local_tempdir(), "json")
  interrupted(out, grouped = TRUE)
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log, grouped = TRUE))
  suppressMessages(pro_request(via = "url", q_url, output = out, progress = FALSE, resume = TRUE))
  expect_equal(page_cursors(log), c("c4", "c6")) # c6: empty last page, not saved
  expect_equal(ids_in(out, "group_by_page_"), paste0("g", 1:5))
  expect_false(file.exists(file.path(out, "group_by_page_4.json")))
})

test_that("a page saved after the last state write is fetched again; higher ones go", {
  out <- file.path(withr::local_tempdir(), "json")
  interrupted(out)
  writeLines("{ junk", file.path(out, "results_page_3.json"))
  writeLines("{}", file.path(out, "results_page_9.json"))
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log))
  suppressMessages(pro_request(via = "url", q_url, output = out, progress = FALSE, resume = TRUE))
  expect_equal(page_cursors(log), "c4")
  expect_equal(ids_in(out), paste0("W", 1:5))
  expect_false(file.exists(file.path(out, "results_page_9.json")))
})

test_that("a crash after the last page costs one request on resume", {
  out <- file.path(withr::local_tempdir(), "json")
  local({
    log1 <- new.env()
    httr2::local_mocked_responses(mock_cursor(log1))
    local_mocked_bindings(.pr_write_query_record = function(...) stop("crash"))
    expect_error(pro_request(via = "url", q_url, output = out, progress = FALSE), "crash")
  })
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log))
  suppressMessages(pro_request(via = "url", q_url, output = out, progress = FALSE, resume = TRUE))
  expect_equal(page_cursors(log), "c4")
  expect_equal(ids_in(out), paste0("W", 1:5))
})

test_that("an unusable state restarts the query with a reason", {
  breakers <- list(
    damaged = function(out) writeLines("{", file.path(out, "_paging.json")),
    other_query = function(out) {
      st <- jsonlite::read_json(file.path(out, "_paging.json"))
      st$query_url <- "https://api.openalex.org/works?filter=type:book"
      jsonlite::write_json(st, file.path(out, "_paging.json"), auto_unbox = TRUE, null = "null")
    },
    missing_page = function(out) unlink(file.path(out, "results_page_1.json"))
  )
  for (b in names(breakers)) {
    out <- file.path(withr::local_tempdir(), "json")
    interrupted(out)
    breakers[[b]](out)
    log <- new.env()
    httr2::local_mocked_responses(mock_cursor(log))
    expect_message(
      pro_request(via = "url", q_url, output = out, progress = FALSE, resume = TRUE),
      "Cannot resume", info = b
    )
    expect_equal(page_cursors(log)[1], "*", info = b)
    expect_equal(ids_in(out), paste0("W", 1:5), info = b)
  }
})

test_that("the pages limit holds across sessions", {
  out <- file.path(withr::local_tempdir(), "json")
  interrupted(out, n = 9L)
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log, n = 9L))
  suppressMessages(pro_request(via = "url", q_url, output = out, progress = FALSE, resume = TRUE, pages = 3))
  expect_equal(page_cursors(log), "c4")
  expect_equal(ids_in(out), paste0("W", 1:6))
})

# inconsistency_on_resume ------------------------------------------------------

# In session 2 the mock puts W1 (already on page 1) on page 3 as well.

test_that("a duplicate after resume stops by default; a rerun needs no download", {
  out <- file.path(withr::local_tempdir(), "json")
  interrupted(out)
  local({
    log <- new.env()
    httr2::local_mocked_responses(mock_cursor(log, extra = list(offset = 4L, id = "W1")))
    err <- expect_error(
      suppressMessages(pro_request(via = "url", q_url, output = out, progress = FALSE, resume = TRUE))
    )
    msg <- conditionMessage(err)
    expect_match(msg, "1 record appears twice", fixed = TRUE)
    expect_match(msg, "without downloading anything again", fixed = TRUE)
    expect_match(msg, "inconsistency_on_resume", fixed = TRUE)
  })
  expect_equal(jsonlite::read_json(file.path(out, "_paging.json"))$status, "check_pending")
  expect_true(file.exists(file.path(out, "00_in.progress")))

  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log))
  suppressMessages(pro_request(via = "url", q_url, output = out, progress = FALSE, resume = TRUE,
                               inconsistency_on_resume = "newest"))
  expect_length(page_requests(log), 0L) # nothing downloaded
  expect_equal(ids_in(out), c("W2", "W3", "W4", "W5", "W1")) # newest copy kept (page 3)
  rec <- jsonlite::read_json(file.path(out, "_query.json"))
  expect_equal(rec$duplicates, 1L)
  expect_equal(rec$duplicates_removed, 1L)
  expect_equal(rec$inconsistency_on_resume, "newest")
  expect_false(file.exists(file.path(out, "_paging.json")))
})

test_that("oldest keeps the first copy; warning and ignore keep both", {
  for (policy in c("oldest", "warning", "ignore")) {
    out <- file.path(withr::local_tempdir(), "json")
    interrupted(out)
    log <- new.env()
    httr2::local_mocked_responses(mock_cursor(log, extra = list(offset = 4L, id = "W1")))
    run <- function() pro_request(via = "url", q_url, output = out, progress = FALSE, resume = TRUE,
                                  inconsistency_on_resume = policy)
    if (policy == "warning") {
      expect_warning(suppressMessages(run()), "1 record appears twice")
    } else {
      expect_no_warning(suppressMessages(run()))
    }
    expected <- if (policy == "oldest") paste0("W", 1:5) else c(paste0("W", 1:5), "W1")
    expect_equal(ids_in(out), expected, info = policy)
  }
})

test_that("missing records (net) stop by default, or warn", {
  for (policy in c("error", "warning", "oldest")) {
    out <- file.path(withr::local_tempdir(), "json")
    interrupted(out)
    log <- new.env()
    httr2::local_mocked_responses(mock_cursor(log, count = 7L)) # OpenAlex now reports 7
    run <- function() pro_request(via = "url", q_url, output = out, progress = FALSE, resume = TRUE,
                                  inconsistency_on_resume = policy)
    if (policy == "error") {
      expect_error(suppressMessages(run()), "2 fewer records than OpenAlex now reports \\(net")
    } else {
      expect_warning(suppressMessages(run()), "2 fewer records", info = policy)
      expect_equal(jsonlite::read_json(file.path(out, "_query.json"))$missing_net, 2L)
    }
  }
})

test_that("in a list, an inconsistent query is reported with the way out", {
  out <- file.path(withr::local_tempdir(), "json")
  qs <- list(a = q_url, b = sub("article", "book", q_url))
  local({
    log1 <- new.env()
    httr2::local_mocked_responses(mock_cursor(log1, fail_at = 4L, fail_if = "type:book"))
    expect_error(pro_request(via = "url", qs, output = out, progress = FALSE), "1 of 2 queries failed")
  })
  local({
    log <- new.env()
    httr2::local_mocked_responses(mock_cursor(log, extra = list(offset = 4L, id = "W1")))
    err <- expect_error(suppressMessages(
      pro_request(via = "url", qs, output = out, progress = FALSE, resume = TRUE)
    ))
    expect_match(conditionMessage(err), "b: Resumed query `b`: 1 record appears twice", fixed = TRUE)
    expect_match(conditionMessage(err), "nothing is downloaded again", fixed = TRUE)
  })
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log))
  suppressMessages(pro_request(via = "url", qs, output = out, progress = FALSE, resume = TRUE,
                               inconsistency_on_resume = "oldest"))
  expect_length(page_requests(log), 0L)
  expect_equal(ids_in(file.path(out, "b")), paste0("W", 1:5))
})

# Regression ------------------------------------------------------------------

test_that("an interrupted sample writes no state and restarts from page 1", {
  out <- file.path(withr::local_tempdir(), "json")
  url <- "https://api.openalex.org/works?filter=type:article&sample=6&seed=1&per_page=2"
  local({
    log1 <- new.env()
    httr2::local_mocked_responses(mock_cursor(log1, n = 6L, fail_at = 4L))
    expect_error(pro_request(via = "url", url, output = out, progress = FALSE), "404")
  })
  expect_false(file.exists(file.path(out, "_paging.json")))
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log, n = 6L))
  pro_request(via = "url", url, output = out, progress = FALSE, resume = TRUE)
  expect_equal(vapply(page_requests(log), function(r) as.character(r$page), ""), c("1", "2", "3"))
})

test_that("a run without interruption leaves no trace of the resume machinery", {
  out <- file.path(withr::local_tempdir(), "json")
  log <- new.env()
  httr2::local_mocked_responses(mock_cursor(log))
  pro_request(via = "url", q_url, output = out, progress = FALSE)
  expect_false(any(file.exists(file.path(out, c("_paging.json", "_paging.json.part")))))
  rec <- jsonlite::read_json(file.path(out, "_query.json"))
  expect_false(any(c("resumed", "duplicates", "missing_net") %in% names(rec)))
})

test_that("_paging.json is never converted or copied into parquet", {
  out <- file.path(withr::local_tempdir(), "json")
  interrupted(out)
  pq <- file.path(dirname(out), "parquet")
  pro_request_parquet(out, pq, progress = FALSE, verbose = FALSE, enrich = FALSE)
  expect_false(file.exists(file.path(pq, "_paging.json")))
  expect_equal(sort(dplyr::collect(arrow::open_dataset(pq))$id), paste0("W", 1:4))
})
