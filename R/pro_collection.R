# pro_collection.R -------------------------------------------------------------
#
# Build OpenAlex collections (server-side ID sets) from pro_query() queries:
# create the collection, import the query on OpenAlex's servers, wait for it,
# and download the member IDs (free CSV -> parquet) and, if selected, the
# records. Everything is recorded in `<project_folder>/<name>.collection/`.

#' Create OpenAlex collections from queries
#'
#' Turns each query into an OpenAlex
#' [collection](https://help.openalex.org/api/collections): a saved set of IDs
#' on OpenAlex's servers that can be reused in later queries
#' (`pro_query(collection = "col_...")`) and combined with other collections.
#' OpenAlex runs the query itself (an *import*); `pro_collection()` waits for
#' it and then downloads what `select` asks for.
#'
#' Each query gets a folder `<project_folder>/<name>.collection/` with
#' \describe{
#'   \item{`_collection.json`}{the query (URL, OQL, OQO), the collection
#'     (`collection_id`, `display_name`, `entity_type`, `member_count`, ...),
#'     each import, the credits used and the `select` that was downloaded.}
#'   \item{`_query_oql.txt`, `_query_oql.html`}{the query in readable OQL.}
#'   \item{`members/parquet/`}{the member IDs (`id`, `added_at`).}
#'   \item{`records/`}{the records when `select` asks for more than `id`
#'     (the [pro_fetch()] layout).}
#' }
#'
#' **Running it again** with the same `project_folder` and `name`:
#' \itemize{
#'   \item Same query: the collection is kept (same ID). An import still
#'     running (e.g. after an interruption) is waited for. Only the downloads
#'     are brought in line with `select`: removed fields are dropped locally
#'     (no requests), added fields re-download the records. Credits are
#'     charged per request, not per field, so fetching only the new fields
#'     would cost the same.
#'   \item `refresh = TRUE`: the query is imported again into the same
#'     collection, adding works that match it now, and everything is
#'     downloaded again. An import only adds: members that no longer match
#'     stay.
#'   \item Changed query: the old collection is deleted and a new one is
#'     created under the same name (it gets a new ID).
#' }
#'
#' **Costs:** creating and managing collections and downloading the member
#' IDs are free. An import costs the same credits as paging through the
#' results yourself (one list request per 200 results). Imports run at about
#' 200 results per second (measured November 2026), so a collection of the
#' maximum 1,000,000 members takes over an hour. Interrupting `pro_collection()`
#' does not stop the import on the server; running it again waits for it.
#'
#' **Limits:** 1,000,000 members per collection, 500 collections per
#' account, names up to 100 characters and unique per account. A collection
#' with more than 300,000 members (100,000 for authors) cannot be used as a
#' filter, so its records cannot be downloaded with `select`; its member IDs
#' can. Queries with `group_by` or `sample` cannot be imported.
#'
#' **API key:** collections need a *personal* OpenAlex API key; organisation
#' keys and some older keys are refused (HTTP 401) even when they work for
#' queries.
#'
#' @param query_url A query from [pro_query()], or a named (nested) list of
#'   queries: each element becomes its own collection, named after its list
#'   names (nested names joined with `_`). A list of chunks from
#'   `pro_query()` would give one collection per chunk; use
#'   `pro_query(..., chunk_limit = 1e6)` to keep one query in one URL (the
#'   import has no URL length limit).
#' @param name Name of the collection (and of its folder) for a single query.
#'   For a list, the list names are used and `name` must be `NULL`.
#' @param project_folder Directory for the `<name>.collection` folders.
#' @param select What to download: `"id"` (default) the member IDs only;
#'   `NULL` nothing; `"all"` the full records; or a character vector of
#'   fields (see [opt_select_fields()]) for records with those fields. The
#'   member IDs are downloaded whenever `select` is not `NULL`.
#' @param refresh If `TRUE`, import an unchanged query again and re-download.
#' @param api_key A personal OpenAlex API key.
#' @param verbose Print the collection ID(s).
#' @param progress Show the steps and import progress.
#' @param ... Passed to [pro_fetch()] when records are downloaded (e.g.
#'   `workers`, `compact_parquet`).
#'
#' @return Invisibly, the path of the `.collection` folder, or a named
#'   character vector of paths for a list of queries.
#'
#' @examples
#' \dontrun{
#' q <- pro_query(search = "coral bleaching", publication_year = 2024)
#' f <- pro_collection(q, name = "coral bleaching 2024", project_folder = "proj")
#' id <- jsonlite::read_json(file.path(f, "_collection.json"))$collection_id
#'
#' # Later: records of the collection that are open access
#' pro_fetch(pro_query(collection = id, is_oa = TRUE), project_folder = "oa")
#'
#' # Add titles to the download (re-downloads the records)
#' pro_collection(q, name = "coral bleaching 2024", project_folder = "proj",
#'                select = c("id", "title"))
#' }
#'
#' @seealso [pro_fetch()], [pro_query()], `vignette("collections")`.
#' @md
#' @export
pro_collection <- function(
  query_url,
  name = NULL,
  project_folder,
  select = "id",
  refresh = FALSE,
  api_key = pro_api_key(),
  verbose = FALSE,
  progress = TRUE,
  ...
) {
  if (missing(project_folder) || !is.character(project_folder) ||
      length(project_folder) != 1L) {
    stop("`project_folder` is required.", call. = FALSE)
  }
  if (is.character(query_url)) {
    if (length(query_url) != 1L) {
      stop("`query_url` must be one URL or a named list of queries.", call. = FALSE)
    }
    if (is.null(name)) {
      stop("`name` is required for a single query.", call. = FALSE)
    }
    queries <- stats::setNames(list(query_url), name)
  } else {
    if (!is.null(name)) {
      stop("For a list of queries the list names are used; leave `name` NULL.",
           call. = FALSE)
    }
    queries <- .col_leaves(query_url)
  }
  bad <- names(queries)[nchar(names(queries)) > 100L]
  if (length(bad)) {
    stop("Collection names can have at most 100 characters: ", bad[[1]], call. = FALSE)
  }
  dir.create(project_folder, recursive = TRUE, showWarnings = FALSE)

  out <- vapply(seq_along(queries), function(i) {
    if (progress && length(queries) > 1L) {
      cli::cli_alert_info(sprintf("Collection %d of %d", i, length(queries)))
    }
    .col_one(queries[[i]], names(queries)[[i]], project_folder, select,
             refresh, api_key, verbose, progress, ...)
  }, character(1))
  names(out) <- names(queries)
  invisible(if (is.character(query_url)) unname(out) else out)
}

#' Flatten a (nested) named list of queries; names joined with `_`
#' @keywords internal
#' @noRd
.col_leaves <- function(x, prefix = NULL) {
  if (is.character(x)) {
    if (length(x) != 1L) {
      stop("Each query must be a single URL.", call. = FALSE)
    }
    return(stats::setNames(list(x), prefix))
  }
  nms <- names(x)
  if (!is.list(x) || is.null(nms) || any(!nzchar(nms))) {
    stop("Every query in the list needs a name: it names the collection.",
         call. = FALSE)
  }
  do.call(c, lapply(seq_along(x), function(i) {
    .col_leaves(x[[i]], paste(c(prefix, nms[[i]]), collapse = "_"))
  }))
}

#' One query -> one collection folder
#' @keywords internal
#' @noRd
.col_one <- function(url, name, project_folder, select, refresh, api_key,
                     verbose, progress, ...) {
  started <- Sys.time()
  folder <- file.path(project_folder, paste0(gsub("[/\\\\]", "_", name), ".collection"))
  rec_file <- file.path(folder, "_collection.json")
  root <- sub("(^https?://[^/?#]+).*", "\\1", url)
  env <- environment()
  step <- function(msg) {
    if (progress) {
      cli::cli_progress_step(gsub("([{}])", "\\1\\1", paste0("[", name, "] ", msg)),
                             .envir = env)
    }
  }

  # 1. Validate the query (free) before anything is created
  step("validating query")
  if (grepl("[?&](group_by|sample)=", url)) {
    stop("Queries with `group_by` or `sample` cannot be imported into a collection.",
         call. = FALSE)
  }
  oq <- .oa_to_oqo(url, api_key)
  if (is.null(oq)) {
    stop("A single record cannot be made into a collection.", call. = FALSE)
  }
  if (!is.null(oq$oqo$group_by) || !is.null(oq$oqo$sample)) {
    stop("Queries with `group_by` or `sample` cannot be imported into a collection.",
         call. = FALSE)
  }
  entity <- oq$oqo$get_rows %||% "works"

  # 2. Keep, re-create or create the collection
  rec <- if (file.exists(rec_file)) jsonlite::read_json(rec_file, simplifyVector = FALSE)
  col <- NULL
  imports <- list()
  prev_credits <- 0
  if (!is.null(rec)) {
    if (.oqo_equivalent(rec$oqo, oq$oqo)) {
      col <- .col_get(root, rec$collection_id, api_key)
      imports <- rec$imports %||% list()
      prev_credits <- as.numeric(rec$credits_import %||% 0)
      if (is.null(col)) {
        step("collection is gone on OpenAlex; re-creating it")
        unlink(file.path(folder, c("members", "records")), recursive = TRUE)
        imports <- list()
        prev_credits <- 0
      }
    } else {
      step(paste("query changed: deleting collection", rec$collection_id, "and re-creating it"))
      .col_req(root, "DELETE", c("collections", rec$collection_id), api_key,
               ok = c(204L, 404L))
      unlink(file.path(folder, c("members", "records")), recursive = TRUE)
    }
  }

  created <- is.null(col)
  credits0 <- .col_credits(root, api_key)
  if (created) {
    step("creating collection")
    col <- .col_json(.col_req(root, "POST", "collections", api_key,
      body = list(display_name = name, entity_type = entity), ok = 201L))
    dir.create(folder, recursive = TRUE, showWarnings = FALSE)
    # Written now so an interrupted run knows the collection
    .col_write_record(rec_file, url, oq, col, imports, select = NULL,
                      credits = NA, started = started)
  } else {
    step("collection exists")
  }
  id <- .col_id(col$id)
  if (verbose) cli::cli_alert_info(paste0("[", name, "] collection ", id))

  # A previous import may still run, or never have started (interruption)
  state <- .col_import_state(root, id, api_key)
  waited <- !is.null(state$running)
  if (waited) {
    step("waiting for the running import")
    imports <- .col_add_import(imports, .col_wait(root, id, state$running, api_key, progress))
  }
  imported <- created || isTRUE(refresh) || (!waited && !state$done)
  if (imported) {
    step("importing query")
    imp <- .col_json(.col_req(root, "POST", c("collections", id, "imports"), api_key,
      body = list(oql = oq$oql), ok = 202L))
    imports <- .col_add_import(imports, .col_wait(root, id, imp$id, api_key, progress))
  }
  fresh <- imported || waited
  col <- .col_get(root, id, api_key) %||% col
  credits <- sum(prev_credits, .col_credits(root, api_key) - credits0, na.rm = TRUE)
  if (fresh) {
    .pr_write_query_text(folder, oq$oqo, oq$oql, root, api_key,
                         records = col$member_count, query_url = .pr_strip_key(url))
  }

  # 3. Downloads, in line with `select`
  old_select <- if (!fresh && !is.null(rec)) unlist(rec$select)
  .col_sync_downloads(folder, root, id, entity, select, old_select, fresh,
                      api_key, verbose, progress, step, ...)

  .col_write_record(rec_file, url, oq, col, imports, select,
                    credits = credits,
                    started = started)
  normalizePath(folder)
}

#' Bring `members/` and `records/` in line with `select`
#' @keywords internal
#' @noRd
.col_sync_downloads <- function(folder, root, id, entity, select, old_select,
                                fresh, api_key, verbose, progress, step, ...) {
  members <- file.path(folder, "members")
  records <- file.path(folder, "records")
  if (is.null(select)) {
    unlink(c(members, records), recursive = TRUE)
    return(invisible())
  }
  if (fresh || !dir.exists(file.path(members, "parquet"))) {
    step("downloading member IDs")
    unlink(members, recursive = TRUE)
    dir.create(file.path(members, "parquet"), recursive = TRUE)
    csv <- file.path(members, "members.csv")
    resp <- .col_req(root, "GET", c("collections", id, "members"), api_key,
                     query = list(format = "csv"))
    writeBin(httr2::resp_body_raw(resp), csv)
    step("converting IDs to parquet")
    .col_csv_to_parquet(csv, file.path(members, "parquet", "members.parquet"))
    unlink(csv)
  }

  new_f <- setdiff(select, "id")
  old_f <- if (dir.exists(file.path(records, "parquet"))) setdiff(old_select, "id")
  if (length(new_f) == 0L) {
    unlink(records, recursive = TRUE)
    return(invisible())
  }
  all_new <- "all" %in% new_f
  refetch <- fresh || is.null(old_f) || !identical(all_new, "all" %in% old_f) ||
    !all(new_f %in% old_f)
  if (refetch) {
    step("downloading records")
    pro_fetch(
      pro_query(entity, collection = id,
                select = if (all_new) NULL else c("id", new_f)),
      project_folder = records, overwrite = TRUE, api_key = api_key,
      verbose = verbose, progress = progress, ...
    )
  } else if (!all_new && length(drop <- setdiff(old_f, new_f))) {
    step(paste("dropping", paste(drop, collapse = ", "), "from the records"))
    .col_drop_columns(file.path(records, "parquet"), drop)
  }
  invisible()
}

#' CSV -> parquet, committed by rename
#' @keywords internal
#' @noRd
.col_csv_to_parquet <- function(csv, parquet) {
  con <- .pro_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  part <- paste0(parquet, ".part")
  DBI::dbExecute(con, sprintf(
    "COPY (SELECT * FROM read_csv(%s, header = true, auto_detect = true)) TO %s (FORMAT parquet)",
    .pro_sql_str(csv), .pro_sql_str(part)
  ))
  file.rename(part, parquet)
}

#' Drop columns from every parquet file below `dir` (no requests)
#' @keywords internal
#' @noRd
.col_drop_columns <- function(dir, drop) {
  con <- .pro_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  for (f in list.files(dir, pattern = "\\.parquet$", recursive = TRUE, full.names = TRUE)) {
    cols <- DBI::dbGetQuery(con, sprintf(
      "SELECT name FROM parquet_schema(%s)", .pro_sql_str(f)))$name
    ex <- intersect(drop, cols)
    if (!length(ex)) next
    part <- paste0(f, ".part")
    DBI::dbExecute(con, sprintf(
      "COPY (SELECT * EXCLUDE (%s) FROM read_parquet(%s)) TO %s (FORMAT parquet)",
      paste0('"', gsub('"', '""', ex), '"', collapse = ", "),
      .pro_sql_str(f), .pro_sql_str(part)
    ))
    file.rename(part, f)
  }
}

#' Poll an import until it is done
#' @keywords internal
#' @noRd
.col_wait <- function(root, id, imp_id, api_key, progress) {
  delay <- getOption("openalexPro.collection_poll", 2)
  pb <- NULL
  repeat {
    s <- .col_json(.col_req(root, "GET", c("collections", id, "imports", imp_id), api_key))
    if (progress && !is.null(s$result_count) && s$result_count > 0) {
      if (is.null(pb)) {
        pb <- cli::cli_progress_bar(
          format = "importing {cli::pb_bar} {cli::pb_current}/{cli::pb_total} | {cli::pb_eta_str}",
          total = s$result_count
        )
      }
      cli::cli_progress_update(id = pb, set = s$added %||% 0)
    }
    if (identical(s$status, "done")) break
    if (identical(s$status, "failed")) {
      stop("The OpenAlex import failed: ", s$error$code %||% "", ": ",
           s$error$message %||% "", call. = FALSE)
    }
    Sys.sleep(delay)
    delay <- min(max(delay, 0.01) * 1.5, 30)
  }
  if (!is.null(pb)) cli::cli_progress_done(id = pb)
  if (isTRUE(s$stopped_at_limit)) {
    warning("The import stopped at the collection limit (1,000,000 members): ",
            "the collection holds only part of the query.", call. = FALSE)
  }
  s
}

#' Running import (id) and whether any import finished
#' @keywords internal
#' @noRd
.col_import_state <- function(root, id, api_key) {
  res <- .col_json(.col_req(root, "GET", c("collections", id, "imports"), api_key))$results
  status <- vapply(res, function(x) x$status %||% "", "")
  running <- res[status %in% c("queued", "running")]
  list(running = if (length(running)) running[[1]]$id, done = any(status == "done"))
}

#' Keep the useful fields of an import status
#' @keywords internal
#' @noRd
.col_add_import <- function(imports, s) {
  c(imports, list(s[intersect(names(s), c("id", "status", "result_count", "added",
                                          "already_present", "stopped_at_limit",
                                          "updated_date"))]))
}

#' GET a collection; NULL if it does not exist (any more)
#' @keywords internal
#' @noRd
.col_get <- function(root, id, api_key) {
  resp <- .col_req(root, "GET", c("collections", id), api_key, ok = c(200L, 404L))
  if (httr2::resp_status(resp) == 404L) NULL else .col_json(resp)
}

#' `https://openalex.org/collections/col_x` -> `col_x`
#' @keywords internal
#' @noRd
.col_id <- function(x) sub(".*/", "", x)

#' @keywords internal
#' @noRd
.col_json <- function(resp) httr2::resp_body_json(resp)

#' Credits used today so far (NA if unknown); free
#' @keywords internal
#' @noRd
.col_credits <- function(root, api_key) {
  x <- tryCatch(
    .col_json(.col_req(root, "GET", "rate-limit", api_key))$rate_limit$credits_used,
    error = function(e) NULL
  )
  if (is.null(x)) NA_real_ else as.numeric(x)
}

#' A collections API request; stops with OpenAlex's message on other statuses
#' @keywords internal
#' @noRd
.col_req <- function(root, method, path, api_key, body = NULL, query = NULL,
                     ok = 200L) {
  req <- httr2::request(root) |>
    httr2::req_url_path_append(path) |>
    httr2::req_method(method) |>
    .oa_auth(api_key) |>
    httr2::req_user_agent(paste0("openalexPro/", utils::packageVersion("openalexPro")))
  if (length(query)) req <- httr2::req_url_query(req, !!!query)
  if (!is.null(body)) req <- httr2::req_body_json(req, body, auto_unbox = TRUE)
  resp <- api_call(req, get_html_response = NULL)
  status <- httr2::resp_status(resp)
  if (status %in% ok) {
    return(resp)
  }
  b <- tryCatch(httr2::resp_body_json(resp), error = function(e) NULL)
  msg <- c(paste0(
    "OpenAlex ", method, " /", paste(path, collapse = "/"), ": HTTP ", status,
    if (!is.null(b$code)) paste0(" (", b$code, ")"),
    if (!is.null(b$message)) paste0(": ", b$message)
  ))
  if (status == 401L) {
    msg <- c(msg, i = paste0(
      "Collections need a personal OpenAlex API key; organisation keys and some ",
      "older keys are refused even when they work for queries. Pass it as `api_key`."
    ))
  }
  if (identical(b$code, "display_name_duplicate")) {
    msg <- c(msg, i = paste0(
      "A collection with this name exists but is not recorded in `project_folder`. ",
      "Choose another `name`, or delete that collection on OpenAlex."
    ))
  }
  cli::cli_abort(gsub("([{}])", "\\1\\1", msg), call = NULL)
}

#' Write `_collection.json`
#' @keywords internal
#' @noRd
.col_write_record <- function(file, url, oq, col, imports, select, credits, started) {
  record <- list(
    query_url = .pr_strip_key(url),
    via = "collection",
    oql = oq$oql,
    oqo = oq$oqo,
    records = col$member_count,
    credits_import = credits,
    started = format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    finished = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    openalexPro = as.character(utils::packageVersion("openalexPro")),
    collection_id = .col_id(col$id),
    collection_url = col$id,
    display_name = col$display_name,
    entity_type = col$entity_type,
    member_count = col$member_count,
    access = col$access,
    created_date = col$created_date,
    updated_date = col$updated_date,
    imports = imports,
    select = if (!is.null(select)) as.list(select)
  )
  jsonlite::write_json(record, file, auto_unbox = TRUE, pretty = TRUE,
                       null = "null", digits = NA)
}
