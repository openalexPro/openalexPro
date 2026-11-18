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
    if (length(p) == 1L) { # create
      if (any(vapply(state$cols, function(x) x$display_name == body$display_name, TRUE))) {
        return(err(400L, "display_name_duplicate"))
      }
      state$next_id <- state$next_id + 1L
      id <- paste0("col_", state$next_id)
      state$cols[[id]] <- list(id = paste0("https://openalex.org/collections/", id),
        display_name = body$display_name, entity_type = body$entity_type,
        member_count = 0L, access = "private", imports = list())
      return(json(state$cols[[id]][-6], 201L))
    }
    id <- p[[2]]
    col <- state$cols[[id]]
    if (is.null(col)) return(err(404L, "collection_not_found"))
    if (length(p) == 2L) {
      if (method == "DELETE") {
        state$cols[[id]] <- NULL
        return(httr2::response(204L))
      }
      return(json(col[-6]))
    }
    if (p[[3]] == "members") {
      csv <- paste0("id,added_at\n", paste0("W", seq_len(col$member_count),
                                            ",2026-11-18T00:00:00", collapse = "\n"), "\n")
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
      state$cols[[id]]$member_count <- n_members
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
  local_mocked_bindings(pro_fetch = function(query_url, project_folder, ...) {
    calls$n <- calls$n + 1L
    calls$url <- query_url
    sel <- httr2::url_parse(query_url)$query$select
    cols <- strsplit(sel %||% "id,title,doi", ",")[[1]]
    dir.create(file.path(project_folder, "parquet"), recursive = TRUE, showWarnings = FALSE)
    df <- as.data.frame(stats::setNames(lapply(cols, function(x) paste0(x, 1:3)), cols))
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

test_that("re-issuing the same query keeps the collection; refresh imports again", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  pf <- withr::local_tempdir()
  pro_collection(q1, name = "c", project_folder = pf, api_key = "k", progress = FALSE)
  pro_collection(q1, name = "c", project_folder = pf, api_key = "k", progress = FALSE)
  expect_equal(posts(state, "/collections$"), 1)
  expect_equal(posts(state, "imports$"), 1)

  f <- pro_collection(q1, name = "c", project_folder = pf, refresh = TRUE,
                      api_key = "k", progress = FALSE)
  expect_equal(posts(state, "/collections$"), 1)
  expect_equal(posts(state, "imports$"), 2)
  rec <- jsonlite::read_json(file.path(f, "_collection.json"))
  expect_equal(rec$collection_id, "col_1")
  expect_length(rec$imports, 2)
  expect_equal(rec$credits_import, 20)
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

imports_sent <- function(state) {
  vapply(Filter(function(x) x$method == "POST" && grepl("imports$", x$path), state$log),
         function(x) x$body$oql, "")
}

test_that("a list with `name` is one collection, filled by one import per query", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  pf <- withr::local_tempdir()
  f <- pro_collection(chunks, name = "dois", project_folder = pf, api_key = "k",
                      progress = FALSE)
  expect_equal(basename(f), "dois.collection")
  expect_null(names(f))
  expect_equal(posts(state, "/collections$"), 1)
  expect_equal(imports_sent(state), paste("get works", sub(".*\\.org", "", c(q1, q2, q3))))
  rec <- jsonlite::read_json(file.path(f, "_collection.json"))
  expect_equal(unlist(rec$parts), names(chunks))
  expect_equal(unlist(rec$query_url), unname(unlist(chunks)))
  expect_length(rec$oqo, 3)
  expect_equal(vapply(rec$imports, function(x) x$part, 1L), 1:3)
  expect_true(all(vapply(rec$imports, function(x) x$status == "done", TRUE)))
  expect_true(file.exists(file.path(f, "parts", "chunk_2", "_query_oql.txt")))
  expect_equal(jsonlite::read_json(file.path(f, "parts", "chunk_2", "_query.json"))$records, 3)
  expect_true(file.exists(file.path(f, "_queries_oql.txt")))
  expect_true(file.exists(file.path(f, "members/parquet/members.parquet")))

  # same parts again: nothing imported; refresh: every part again
  pro_collection(chunks, name = "dois", project_folder = pf, api_key = "k", progress = FALSE)
  expect_equal(posts(state, "imports$"), 3)
  pro_collection(chunks, name = "dois", project_folder = pf, refresh = TRUE,
                 api_key = "k", progress = FALSE)
  expect_equal(posts(state, "imports$"), 6)
  expect_equal(posts(state, "/collections$"), 1)

  # one part changed: the collection is re-created
  chunks2 <- chunks
  chunks2$chunk_3 <- paste0(q3, "x")
  pro_collection(chunks2, name = "dois", project_folder = pf, api_key = "k", progress = FALSE)
  expect_equal(posts(state, "/collections$"), 2)
  expect_equal(jsonlite::read_json(file.path(f, "_collection.json"))$collection_id, "col_2")
})

test_that("an interrupted multi-part import resumes with the missing parts", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  local_fake_fetch(calls)
  pf <- withr::local_tempdir()
  real_wait <- .col_wait
  k <- new.env(); k$n <- 0L
  local({
    local_mocked_bindings(.col_wait = function(...) {
      k$n <- k$n + 1L
      if (k$n == 2L) stop("interrupted") # while part 2 runs
      real_wait(...)
    })
    expect_error(pro_collection(chunks, name = "dois", project_folder = pf, api_key = "k",
                                progress = FALSE), "interrupted")
  })
  expect_equal(posts(state, "imports$"), 2)
  f <- pro_collection(chunks, name = "dois", project_folder = pf, api_key = "k",
                      progress = FALSE)
  # part 2 is waited for, not started again; only part 3 is new
  expect_equal(imports_sent(state)[3], paste("get works", sub(".*\\.org", "", q3)))
  expect_equal(posts(state, "imports$"), 3)
  rec <- jsonlite::read_json(file.path(f, "_collection.json"))
  expect_equal(vapply(rec$imports, function(x) x$part, 1L), 1:3)
})

test_that("a query over 20,000 characters of OQL stops before anything is created", {
  state <- new.env(); calls <- new.env()
  local_collections(state)
  pf <- withr::local_tempdir()
  long <- paste0("https://api.openalex.org/works?search=", strrep("a", 20000))
  expect_error(pro_collection(long, name = "c", project_folder = pf, api_key = "k",
                              progress = FALSE), "at most 20,000.*chunk_limit")
  expect_error(pro_collection(list(chunk_1 = q1, chunk_2 = long), name = "c",
                              project_folder = pf, api_key = "k", progress = FALSE),
               "Query `chunk_2`.*smaller chunks")
  expect_equal(posts(state, "/collections"), 0)
})
