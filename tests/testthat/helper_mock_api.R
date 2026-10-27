# Mock of a paged OpenAlex API for offline tests (used by test-023 and
# test-028). See mock_cursor() for what it serves.

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
