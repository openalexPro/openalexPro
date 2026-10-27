library(testthat)

# Resuming an interrupted query in the middle (_paging.json), and the check
# for inconsistencies after a resume (inconsistency_on_resume).
# The paged API mock (mock_cursor() & co.) is in helper_mock_api.R.

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

test_that("an empty page after a full one does not advance the progress by 0", {
  # OpenAlex sends a next_cursor after an exactly full last page; the empty
  # page after it must not call the progressor with amount = 0 (progressr
  # fails on that once the bar is complete)
  httr2::local_mocked_responses(function(req) {
    last <- grepl("cursor=c2", req$url, fixed = TRUE)
    page <- list(
      meta = list(count = 2L, per_page = 2L, next_cursor = if (!last) "c2"),
      results = if (last) list() else list(list(id = "W1"), list(id = "W2"))
    )
    httr2::response(200, headers = list("content-type" = "application/json"),
      body = charToRaw(as.character(jsonlite::toJSON(page, auto_unbox = TRUE, null = "null"))))
  })
  amounts <- numeric(0)
  fetch_query_pages(
    q_url, pages = NULL, output = file.path(withr::local_tempdir(), "q"),
    overwrite = TRUE, api_key = NULL, verbose = FALSE, error_log = NULL,
    progressor = function(amount) amounts <<- c(amounts, amount)
  )
  expect_equal(amounts, 1)
})
