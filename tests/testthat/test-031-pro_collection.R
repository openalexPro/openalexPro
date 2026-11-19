# pro_collection(): offline, against a small in-memory collections API.

# Serves /query (translation), /rate-limit, and /collections with imports
# (running on the first poll, done on the second) and a members CSV.
mock_collections <- function(state, n_members = 3L) {
  state$cols <- list()
  state$log <- list()
  state$credits <- 0
  state$next_id <- 0L
  function(req) {
    u <- httr2::url_parse(req$url)
    method <- req$method %||% if (is.null(req$body)) "GET" else "POST"
    body <- if (!is.null(req$body$data)) {
      jsonlite::fromJSON(jsonlite::toJSON(req$body$data, auto_unbox = TRUE),
                         simplifyVector = FALSE)
    }
    p <- strsplit(sub("^/", "", u$path), "/")[[1]]
    state$log[[length(state$log) + 1L]] <- list(method = method, path = u$path, body = body)
    json <- function(x, status = 200L) {
      httr2::response(status, headers = list("content-type" = "application/json"),
        body = charToRaw(as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"))))
    }
    err <- function(status, code) json(list(code = code, message = code), status)
    pub <- function(col) col[setdiff(names(col), c("imports", "members"))]
    if (identical(p, "query")) {
      oqo <- body$oqo %||% list(get_rows = "works", filter_rows = list(
        list(column_id = "q", value = body$oxurl %||% body$oql)))
      oql <- paste("get works", oqo$filter_rows[[1]]$value)
      return(json(list(oqo = oqo, oql = oql, oql_oneline = oql,
                       validation = list(valid = TRUE, errors = list()))))
    }
    if (identical(p, "rate-limit")) {
      return(json(list(rate_limit = list(credits_used = state$credits))))
    }
    stopifnot(p[[1]] == "collections")
    if (length(p) == 1L && method == "GET") { # list own, `search` in the name
      hits <- Filter(function(x) grepl(tolower(u$query$search %||% ""), tolower(x$display_name),
                                       fixed = TRUE), state$cols)
      return(json(list(results = unname(lapply(hits, pub)))))
    }
    if (length(p) == 1L) { # create
      if (any(vapply(state$cols, function(x) { # unique per owner, ignoring case
        tolower(x$display_name) == tolower(body$display_name)
      }, TRUE))) {
        return(err(400L, "display_name_duplicate"))
      }
      state$next_id <- state$next_id + 1L
      id <- paste0("col_", state$next_id)
      state$cols[[id]] <- list(id = paste0("https://openalex.org/collections/", id),
        display_name = body$display_name, entity_type = body$entity_type,
        member_count = 0L, access = "private", imports = list(), members = character(0))
      return(json(pub(state$cols[[id]]), 201L))
    }
    id <- p[[2]]
    col <- state$cols[[id]]
    if (is.null(col)) return(err(404L, "collection_not_found"))
    if (length(p) == 2L) {
      if (method == "DELETE") {
        state$cols[[id]] <- NULL
        return(httr2::response(204L))
      }
      if (method == "PATCH") {
        if (identical(body$access, "public")) return(err(403L, "public_needs_review"))
        state$cols[[id]]$access <- body$access
        return(json(pub(state$cols[[id]])))
      }
      return(json(pub(col)))
    }
    if (p[[3]] == "members" && method == "POST") {
      ids <- unlist(body$member_ids)
      new <- setdiff(ids, col$members)
      state$cols[[id]]$members <- c(col$members, new)
      state$cols[[id]]$member_count <- length(state$cols[[id]]$members)
      return(json(list(added = length(new), already_present = length(ids) - length(new),
                       member_count = state$cols[[id]]$member_count)))
    }
    if (p[[3]] == "members" && method == "DELETE") {
      ids <- strsplit(u$query$member_ids, ",", fixed = TRUE)[[1]]
      stopifnot(length(ids) <= 100L)
      gone <- intersect(ids, col$members)
      state$cols[[id]]$members <- setdiff(col$members, ids)
      state$cols[[id]]$member_count <- length(state$cols[[id]]$members)
      return(json(list(member_count = state$cols[[id]]$member_count, removed = length(gone))))
    }
    if (p[[3]] == "members") {
      csv <- paste0("id,added_at\r\n", paste0(col$members, ",2026-11-18T00:00:00\r\n",
                                              collapse = ""))
      return(httr2::response(200L, headers = list("content-type" = "text/csv"),
                             body = charToRaw(csv)))
    }
    # imports
    if (length(p) == 3L && method == "POST") {
      imp <- paste0("imp_", length(col$imports) + 1L)
      state$cols[[id]]$imports[[imp]] <- list(id = imp, status = "queued", polls = 0L)
      return(json(list(id = imp, status = "queued"), 202L))
    }
    if (length(p) == 3L) {
      return(json(list(results = unname(lapply(col$imports, function(i) i[c("id", "status")])))))
    }
    imp <- col$imports[[p[[4]]]]
    imp$polls <- imp$polls + 1L
    if (imp$polls >= 2L && imp$status != "done") {
      imp$status <- "done"
      state$cols[[id]]$members <- union(col$members, paste0("W", seq_len(n_members)))
      state$cols[[id]]$member_count <- length(state$cols[[id]]$members)
      state$credits <- state$credits + 10
    } else if (imp$status == "queued") {
      imp$status <- "running"
    }
    state$cols[[id]]$imports[[p[[4]]]] <- imp
    json(list(id = imp$id, status = imp$status, progress = if (imp$status == "done") 1 else 0.5,
              added = if (imp$status == "done") n_members else 1L,
              already_present = 0L, result_count = n_members, stopped_at_limit = FALSE))
  }
}

local_collections <- function(state, ..., env = parent.frame()) {
  withr::local_options(openalexPro.collection_poll = 0, .local_envir = env)
  httr2::local_mocked_responses(mock_collections(state, ...), env = env)
}

# pro_fetch() replaced by a writer of one parquet file with the selected columns
local_fake_fetch <- function(calls, env = parent.frame()) {
  calls$n <- 0L
  local_mocked_bindings(pro_fetch = function(query_url, project_folder, resume = FALSE, ...) {
    calls$n <- calls$n + 1L
    calls$url <- query_url
    calls$resume <- resume
    sel <- httr2::url_parse(if (is.list(query_url)) query_url[[1]] else query_url)$query$select
    cols <- strsplit(sel %||% "id,title,doi", ",")[[1]]
    dir.create(file.path(project_folder, "parquet"), recursive = TRUE, showWarnings = FALSE)
    ids <- calls$ids %||% paste0("W", 1:3)
    df <- as.data.frame(stats::setNames(lapply(cols, function(x) {
      if (x == "id") paste0("https://openalex.org/", ids) else paste0(x, seq_along(ids))
    }), cols))
    con <- DBI::dbConnect(duckdb::duckdb())
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
    duckdb::duckdb_register(con, "df", df)
    DBI::dbExecute(con, sprintf("COPY df TO '%s' (FORMAT parquet)",
                                file.path(project_folder, "parquet", "results_page_1.parquet")))
    invisible(file.path(project_folder, "parquet"))
  }, .env = env)
}

pq_cols <- function(dir) {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  names(DBI::dbGetQuery(con, sprintf("SELECT * FROM read_parquet('%s/**/*.parquet') LIMIT 1", dir)))
}

sel_of <- function(url) httr2::url_parse(url)$query$select

posts <- function(state, re) {
  sum(vapply(state$log, function(x) x$method == "POST" && grepl(re, x$path), TRUE))
}

q1 <- "https://api.openalex.org/works?filter=publication_year%3A2024&search=coral"
q2 <- "https://api.openalex.org/works?filter=publication_year%3A2023&search=coral"

test_that("a query becomes a collection with a record, OQL text and member IDs", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  pf <- withr::local_tempdir()
  f <- pro_collection(q1, name = "coral", project_folder = pf, api_key = "k", progress = FALSE)

  expect_equal(basename(f), "coral.collection")
  rec <- jsonlite::read_json(file.path(f, "_collection.json"))
  expect_equal(rec$collection_id, "col_1")
  expect_equal(rec$member_count, 3)
  expect_equal(rec$credits_import, 10)
  expect_equal(rec$entity_type, "works")
  expect_equal(rec$imports[[1]]$status, "done")
  expect_equal(unlist(rec$select), "id")
  expect_true(file.exists(file.path(f, "_query_oql.txt")))
  # member CSV -> parquet; no CSV left; no records
  expect_equal(nrow(arrow::read_parquet(file.path(f, "members/parquet/members.parquet"))), 3)
  expect_false(file.exists(file.path(f, "members", "members.csv")))
  expect_false(dir.exists(file.path(f, "records")))
  expect_equal(calls$n, 0L)
  # the import sends the translated OQL
  imp <- Filter(function(x) x$method == "POST" && grepl("imports$", x$path), state$log)
  expect_equal(imp[[1]]$body$oql, "get works /works?filter=publication_year%3A2024&search=coral")
})

test_that("select = NULL creates the collection and downloads nothing", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  pf <- withr::local_tempdir()
  f <- pro_collection(q1, name = "c", project_folder = pf, select = NULL,
                      api_key = "k", progress = FALSE)
  expect_false(dir.exists(file.path(f, "members")))
  expect_false(any(vapply(state$log, function(x) grepl("members", x$path), TRUE)))
  expect_equal(calls$n, 0L)
})

test_that("re-issuing the same query keeps the collection; refresh syncs the members", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  pf <- withr::local_tempdir()
  pro_collection(q1, name = "c", project_folder = pf, api_key = "k", progress = FALSE)
  pro_collection(q1, name = "c", project_folder = pf, api_key = "k", progress = FALSE)
  expect_equal(posts(state, "/collections$"), 1)
  expect_equal(posts(state, "imports$"), 1)

  # the query now finds W2..W5: W4, W5 are added and W1 is removed (an
  # import would only add)
  calls$ids <- paste0("W", 2:5)
  f <- pro_collection(q1, name = "c", project_folder = pf, refresh = TRUE,
                      api_key = "k", progress = FALSE)
  expect_equal(posts(state, "/collections$"), 1)
  expect_equal(posts(state, "imports$"), 1)
  expect_equal(sel_of(calls$url), "id")
  rec <- jsonlite::read_json(file.path(f, "_collection.json"))
  expect_equal(rec$collection_id, "col_1")
  expect_equal(rec$synced, list(added = 2, removed = 1))
  expect_equal(rec$member_count, 4)
  expect_setequal(state$cols$col_1$members, paste0("W", 2:5))
  expect_setequal(arrow::read_parquet(file.path(f, "members/parquet/members.parquet"))$id,
                  paste0("W", 2:5))
  expect_false(dir.exists(file.path(f, "_ids")))
})

test_that("an interrupted import is waited for when re-issued", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  pf <- withr::local_tempdir()
  # interrupt in the first poll of the import
  local({
    local_mocked_bindings(.col_wait = function(...) stop("interrupted"))
    expect_error(pro_collection(q1, name = "c", project_folder = pf, api_key = "k",
                                progress = FALSE), "interrupted")
  })
  f <- pro_collection(q1, name = "c", project_folder = pf, api_key = "k", progress = FALSE)
  expect_equal(posts(state, "imports$"), 1) # not started again
  expect_equal(jsonlite::read_json(file.path(f, "_collection.json"))$member_count, 3)
  expect_true(file.exists(file.path(f, "members/parquet/members.parquet")))
})

test_that("a changed query deletes the collection and creates a new one", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  pf <- withr::local_tempdir()
  pro_collection(q1, name = "c", project_folder = pf, select = c("id", "title"),
                 api_key = "k", progress = FALSE)
  f <- pro_collection(q2, name = "c", project_folder = pf, api_key = "k", progress = FALSE)
  expect_true(any(vapply(state$log, function(x) {
    x$method == "DELETE" && x$path == "/collections/col_1"
  }, TRUE)))
  expect_equal(jsonlite::read_json(file.path(f, "_collection.json"))$collection_id, "col_2")
  expect_false(dir.exists(file.path(f, "records")))
})

test_that("a collection deleted on OpenAlex is re-created", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  pf <- withr::local_tempdir()
  pro_collection(q1, name = "c", project_folder = pf, api_key = "k", progress = FALSE)
  state$cols[["col_1"]] <- NULL
  f <- pro_collection(q1, name = "c", project_folder = pf, api_key = "k", progress = FALSE)
  expect_equal(jsonlite::read_json(file.path(f, "_collection.json"))$collection_id, "col_2")
})

test_that("a name in use but not in project_folder stops without deleting", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  pro_collection(q1, name = "c", project_folder = withr::local_tempdir(),
                 api_key = "k", progress = FALSE)
  expect_error(
    pro_collection(q1, name = "c", project_folder = withr::local_tempdir(),
                   api_key = "k", progress = FALSE),
    "not recorded in `project_folder`"
  )
  expect_false(any(vapply(state$log, function(x) x$method == "DELETE", TRUE)))
})

test_that("a named list gives one collection per element, named after it", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  pf <- withr::local_tempdir()
  out <- pro_collection(list(a = q1, b = list(x = q2)), project_folder = pf,
                        api_key = "k", progress = FALSE)
  expect_equal(names(out), c("a", "b_x"))
  expect_equal(basename(out), c("a.collection", "b_x.collection"))
  expect_setequal(vapply(state$cols, function(x) x$display_name, ""), c("a", "b_x"))
})

test_that("invalid input stops before anything is created", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  pf <- withr::local_tempdir()
  expect_error(pro_collection(q1, project_folder = pf, api_key = "k"), "`name` is required")
  expect_error(pro_collection(list(q1), project_folder = pf, api_key = "k"), "needs a name")
  expect_error(pro_collection(q1, name = "c", api_key = "k"), "`project_folder` is required")
  expect_error(pro_collection(paste0(q1, "&group_by=type"), name = "c", project_folder = pf,
                              api_key = "k", progress = FALSE), "group_by")
  expect_error(pro_collection(paste0(q1, "&sample=10"), name = "c", project_folder = pf,
                              api_key = "k", progress = FALSE), "sample")
  expect_error(pro_collection(q1, name = strrep("x", 101), project_folder = pf,
                              api_key = "k", progress = FALSE), "100 characters")
  expect_equal(posts(state, "/collections"), 0)
})

test_that("select syncs the records: add re-downloads, remove drops locally", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  pf <- withr::local_tempdir()
  f <- pro_collection(q1, name = "c", project_folder = pf, select = c("id", "title"),
                      api_key = "k", progress = FALSE)
  expect_equal(calls$n, 1L)
  qu <- httr2::url_parse(calls$url)$query
  expect_equal(qu$filter, "collection:col_1")
  expect_equal(qu$select, "id,title")
  expect_equal(qu$corpus, "all") # the filter alone returns only core works
  expect_equal(pq_cols(file.path(f, "records/parquet")), c("id", "title"))

  pro_collection(q1, name = "c", project_folder = pf, select = c("id", "title", "doi"),
                 api_key = "k", progress = FALSE)
  expect_equal(calls$n, 2L)
  expect_equal(pq_cols(file.path(f, "records/parquet")), c("id", "title", "doi"))

  n_req <- length(state$log)
  pro_collection(q1, name = "c", project_folder = pf, select = c("id", "doi"),
                 api_key = "k", progress = FALSE)
  expect_equal(calls$n, 2L) # no download
  expect_equal(pq_cols(file.path(f, "records/parquet")), c("id", "doi"))
  expect_false(any(vapply(state$log[-seq_len(n_req)], function(x) {
    grepl("members", x$path) || (x$method == "POST" && grepl("^/collections", x$path))
  }, TRUE))) # only the import status was looked up

  pro_collection(q1, name = "c", project_folder = pf, select = "all",
                 api_key = "k", progress = FALSE)
  expect_equal(calls$n, 3L)
  expect_null(httr2::url_parse(calls$url)$query$select)

  pro_collection(q1, name = "c", project_folder = pf, select = NULL,
                 api_key = "k", progress = FALSE)
  expect_false(dir.exists(file.path(f, "records")))
  expect_false(dir.exists(file.path(f, "members")))
  expect_null(jsonlite::read_json(file.path(f, "_collection.json"))$select)
})

test_that("a failed import and a 401 stop with OpenAlex's reason", {
  pf <- withr::local_tempdir()
  withr::local_options(openalexPro.collection_poll = 0)
  httr2::local_mocked_responses(function(req) {
    httr2::response(200L, headers = list("content-type" = "application/json"),
      body = charToRaw('{"id":"imp_1","status":"failed","error":{"code":"x_code","message":"boom"}}'))
  })
  expect_error(.col_wait("https://api.openalex.org", "col_1", "imp_1", "k", FALSE),
               "x_code: boom")
  httr2::local_mocked_responses(function(req) {
    httr2::response(401L, headers = list("content-type" = "application/json"),
      body = charToRaw('{"code":"unauthorized","message":"That API key isn\'t valid."}'))
  })
  expect_error(.col_req("https://api.openalex.org", "GET", "collections", "k"),
               "personal OpenAlex API key")
})

q3 <- "https://api.openalex.org/works?filter=publication_year%3A2022&search=coral"
chunks <- list(chunk_1 = q1, chunk_2 = q2, chunk_3 = q3)

test_that("a list with `name` is one collection: fetched, IDs added as members", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  pf <- withr::local_tempdir()
  f <- pro_collection(chunks, name = "dois", project_folder = pf, api_key = "k",
                      progress = FALSE)
  expect_equal(basename(f), "dois.collection")
  expect_null(names(f))
  expect_equal(posts(state, "/collections$"), 1)
  expect_equal(posts(state, "imports$"), 0)
  expect_equal(posts(state, "members$"), 1)
  expect_equal(calls$n, 1L)
  expect_equal(names(calls$url), names(chunks))
  expect_equal(sel_of(calls$url[[2]]), "id")
  expect_equal(httr2::url_parse(calls$url[[2]])$query$filter, "publication_year:2023")
  rec <- jsonlite::read_json(file.path(f, "_collection.json"))
  expect_equal(rec$via, "members")
  expect_true(rec$members_added)
  expect_equal(rec$added, 3)
  expect_equal(rec$member_count, 3)
  expect_null(rec$query_url) # the queries are in _parts.parquet, not here
  expect_null(rec$oqo)
  parts <- arrow::read_parquet(file.path(f, "_parts.parquet"))
  expect_equal(parts$part, names(chunks))
  expect_equal(parts$query_url, unname(unlist(chunks)))
  expect_false(dir.exists(file.path(f, "_ids")))
  expect_false(dir.exists(file.path(f, "records")))
  expect_equal(nrow(arrow::read_parquet(file.path(f, "members/parquet/members.parquet"))), 3)

  # the same list again: nothing fetched or added; refresh: both again
  pro_collection(chunks, name = "dois", project_folder = pf, api_key = "k", progress = FALSE)
  expect_equal(calls$n, 1L)
  expect_equal(posts(state, "members$"), 1)
  calls$ids <- paste0("W", 2:5)
  pro_collection(chunks, name = "dois", project_folder = pf, refresh = TRUE,
                 api_key = "k", progress = FALSE)
  expect_equal(calls$n, 2L)
  expect_false(calls$resume)
  expect_equal(posts(state, "members$"), 2)
  expect_equal(posts(state, "/collections$"), 1)
  expect_setequal(state$cols$col_1$members, paste0("W", 2:5)) # W1 removed
  rec <- jsonlite::read_json(file.path(f, "_collection.json"))
  expect_equal(rec[c("added", "removed")], list(added = 2, removed = 1))
  calls$ids <- NULL

  # one query changed: the collection is re-created
  chunks2 <- chunks
  chunks2$chunk_3 <- paste0(q3, "x")
  pro_collection(chunks2, name = "dois", project_folder = pf, api_key = "k", progress = FALSE)
  expect_true(any(vapply(state$log, function(x) {
    x$method == "DELETE" && x$path == "/collections/col_1"
  }, TRUE)))
  expect_equal(jsonlite::read_json(file.path(f, "_collection.json"))$collection_id, "col_2")
})

test_that("an interrupted members run resumes the fetch and adds the members", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  pf <- withr::local_tempdir()
  local({
    local_mocked_bindings(.col_add_members = function(...) stop("interrupted"))
    expect_error(pro_collection(chunks, name = "dois", project_folder = pf, api_key = "k",
                                progress = FALSE), "interrupted")
  })
  rec_file <- file.path(pf, "dois.collection", "_collection.json")
  expect_false(jsonlite::read_json(rec_file)$members_added)
  f <- pro_collection(chunks, name = "dois", project_folder = pf, api_key = "k",
                      progress = FALSE)
  expect_equal(calls$n, 2L)
  expect_true(calls$resume)
  expect_equal(posts(state, "/collections$"), 1)
  expect_equal(posts(state, "members$"), 1)
  expect_true(jsonlite::read_json(rec_file)$members_added)
})

test_that("records of a members collection come from its queries", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  pf <- withr::local_tempdir()
  f <- pro_collection(chunks, name = "d", project_folder = pf, select = c("id", "title"),
                      api_key = "k", progress = FALSE)
  expect_equal(calls$n, 1L) # IDs and records in one pass
  expect_equal(sel_of(calls$url[[1]]), "id,title")
  expect_equal(pq_cols(file.path(f, "records/parquet")), c("id", "title"))

  pro_collection(chunks, name = "d", project_folder = pf, select = c("id", "title", "doi"),
                 api_key = "k", progress = FALSE)
  expect_equal(calls$n, 2L)
  expect_equal(names(calls$url), names(chunks)) # not a `collection:` filter
  expect_equal(sel_of(calls$url[[1]]), "id,title,doi")
  expect_equal(posts(state, "members$"), 1)

  pro_collection(chunks, name = "d", project_folder = pf, select = c("id", "doi"),
                 api_key = "k", progress = FALSE)
  expect_equal(calls$n, 2L)
  expect_equal(pq_cols(file.path(f, "records/parquet")), c("id", "doi"))
})

test_that(".col_add_members() sends at most `batch` IDs per request", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  f <- pro_collection(chunks, name = "d", project_folder = withr::local_tempdir(),
                      select = NULL, api_key = "k", progress = FALSE)
  expect_false(dir.exists(file.path(f, "members")))
  r <- .col_add_members("https://api.openalex.org", "col_1", c("W1", paste0("W", 4:7)),
                        "k", progress = FALSE, batch = 2L)
  expect_equal(posts(state, "members$"), 1 + 3)
  expect_equal(r, list(added = 4, already_present = 1))
})

test_that("a query over 20,000 characters of OQL stops before anything is created", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  pf <- withr::local_tempdir()
  long <- paste0("https://api.openalex.org/works?search=", strrep("a", 20000))
  expect_error(pro_collection(long, name = "c", project_folder = pf, api_key = "k",
                              progress = FALSE), "at most 20,000.*chunk_limit")
  expect_equal(posts(state, "/collections"), 0)
})

test_that("access is set when asked, and only when it differs", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  pf <- withr::local_tempdir()
  patches <- function() sum(vapply(state$log, function(x) x$method == "PATCH", TRUE))
  f <- pro_collection(q1, name = "c", project_folder = pf, access = "shared_by_link",
                      api_key = "k", progress = FALSE)
  expect_equal(patches(), 1)
  expect_equal(jsonlite::read_json(file.path(f, "_collection.json"))$access, "shared_by_link")
  pro_collection(q1, name = "c", project_folder = pf, access = "shared_by_link",
                 api_key = "k", progress = FALSE)
  pro_collection(q1, name = "c", project_folder = pf, api_key = "k", progress = FALSE)
  expect_equal(patches(), 1) # same access, or NULL: no change
  expect_equal(jsonlite::read_json(file.path(f, "_collection.json"))$access, "shared_by_link")

  f2 <- pro_collection(chunks, name = "d", project_folder = pf, access = "shared_by_link",
                       api_key = "k", progress = FALSE)
  expect_equal(patches(), 2)
  expect_equal(jsonlite::read_json(file.path(f2, "_collection.json"))$access, "shared_by_link")

  expect_error(pro_collection(q1, name = "c", project_folder = pf, access = "public",
                              api_key = "k", progress = FALSE),
               "public_needs_review")
  expect_error(pro_collection(q1, name = "c", project_folder = pf, access = "everyone",
                              api_key = "k", progress = FALSE), "should be one of")
})

test_that(".col_remove_members() sends at most `batch` IDs per request", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  calls$ids <- paste0("W", 1:5)
  pro_collection(chunks, name = "d", project_folder = withr::local_tempdir(),
                 select = NULL, api_key = "k", progress = FALSE)
  n0 <- length(state$log)
  removed <- .col_remove_members("https://api.openalex.org", "col_1",
                                 c(paste0("W", 1:4), "W99"), "k", progress = FALSE, batch = 2L)
  expect_equal(removed, 4)
  expect_equal(sum(vapply(state$log[-seq_len(n0)], function(x) x$method == "DELETE", TRUE)), 3)
  expect_equal(state$cols$col_1$members, "W5")
})

test_that("without a local record, refresh takes over the collection of that name", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  pro_collection(chunks, name = "Dois", project_folder = withr::local_tempdir(),
                 api_key = "k", progress = FALSE)
  state$cols$col_1$members <- c(state$cols$col_1$members, "W77") # stale member
  pf <- withr::local_tempdir() # the local folder is gone

  expect_error(pro_collection(chunks, name = "dois", project_folder = pf, api_key = "k",
                              progress = FALSE), "refresh = TRUE")
  calls$ids <- paste0("W", 2:4)
  f <- pro_collection(chunks, name = "dois", project_folder = pf, refresh = TRUE,
                      api_key = "k", progress = FALSE)
  # created once; the second POST is the refused attempt without `refresh`
  expect_equal(posts(state, "/collections$"), 2)
  expect_length(state$cols, 1)
  expect_false(any(vapply(state$log, function(x) {
    x$method == "DELETE" && grepl("^/collections/col_[0-9]+$", x$path)
  }, TRUE)))
  rec <- jsonlite::read_json(file.path(f, "_collection.json"))
  expect_equal(rec$collection_id, "col_1") # same ID
  expect_setequal(state$cols$col_1$members, paste0("W", 2:4)) # W1, W77 removed
  expect_equal(rec[c("added", "removed")], list(added = 1, removed = 2))
  expect_true(file.exists(file.path(f, "_parts.parquet")))
  expect_setequal(arrow::read_parquet(file.path(f, "members/parquet/members.parquet"))$id,
                  paste0("W", 2:4))
  # and the next run finds the local record
  pro_collection(chunks, name = "dois", project_folder = pf, api_key = "k", progress = FALSE)
  expect_equal(calls$n, 2L)

  # the single-query route takes over too; an entity mismatch stops
  pf2 <- withr::local_tempdir()
  f2 <- pro_collection(q1, name = "dois", project_folder = pf2, refresh = TRUE,
                       api_key = "k", progress = FALSE)
  expect_equal(jsonlite::read_json(file.path(f2, "_collection.json"))$collection_id, "col_1")
  expect_equal(posts(state, "imports$"), 0)
  state$cols$col_1$entity_type <- "authors"
  expect_error(pro_collection(q1, name = "dois", project_folder = withr::local_tempdir(),
                              refresh = TRUE, api_key = "k", progress = FALSE),
               "holds authors")
})

test_that("a changed query with refresh keeps the collection and syncs its members", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  deletes <- function() {
    sum(vapply(state$log, function(x) {
      x$method == "DELETE" && grepl("^/collections/col_[0-9]+$", x$path)
    }, TRUE))
  }

  # single query: q1 -> q2
  pf <- withr::local_tempdir()
  pro_collection(q1, name = "c", project_folder = pf, api_key = "k", progress = FALSE)
  calls$ids <- paste0("W", 3:6)
  f <- pro_collection(q2, name = "c", project_folder = pf, refresh = TRUE,
                      api_key = "k", progress = FALSE)
  rec <- jsonlite::read_json(file.path(f, "_collection.json"))
  expect_equal(deletes(), 0)
  expect_equal(rec$collection_id, "col_1")
  expect_equal(rec$query_url, q2)
  expect_equal(rec$synced, list(added = 3, removed = 2))
  expect_setequal(state$cols$col_1$members, paste0("W", 3:6))

  # list of queries: one chunk changed
  calls$ids <- NULL
  f <- pro_collection(chunks, name = "d", project_folder = pf, api_key = "k", progress = FALSE)
  id <- jsonlite::read_json(file.path(f, "_collection.json"))$collection_id
  chunks2 <- chunks
  chunks2$chunk_3 <- paste0(q3, "x")
  calls$ids <- paste0("W", 2:4)
  pro_collection(chunks2, name = "d", project_folder = pf, refresh = TRUE,
                 api_key = "k", progress = FALSE)
  rec <- jsonlite::read_json(file.path(f, "_collection.json"))
  expect_equal(deletes(), 0)
  expect_equal(rec$collection_id, id)
  expect_equal(arrow::read_parquet(file.path(f, "_parts.parquet"))$query_url[[3]],
               paste0(q3, "x"))
  expect_equal(rec[c("added", "removed")], list(added = 1, removed = 1))
  expect_setequal(state$cols[[id]]$members, paste0("W", 2:4))

  # without refresh, a changed query still re-creates the collection
  pro_collection(chunks, name = "d", project_folder = pf, api_key = "k", progress = FALSE)
  expect_equal(deletes(), 1)
  expect_false(identical(jsonlite::read_json(file.path(f, "_collection.json"))$collection_id, id))
})
