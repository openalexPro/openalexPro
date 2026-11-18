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
#'   \item{`_parts.parquet`}{for a list of queries in one collection (see
#'     **Several queries in one collection**): the name and URL of each query.
#'     `_collection.json` then holds no queries, so it stays small however
#'     long the list is.}
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
#' **Several queries in one collection:** OpenAlex imports a query of at
#' most 20,000 characters of OQL (about 600 to 800 DOIs); a longer single
#' query stops before anything is created. For long ID or DOI lists, split
#' them into chunks, e.g. `pro_query(doi = dois, chunk_limit = 200)`, and pass
#' the list with `name`. The queries are then not imported: they are fetched
#' with [pro_fetch()] (`select = "id"`, in parallel with `workers`) and the
#' IDs are added to the collection (`member_ids`, 10,000 per request, free).
#' This costs the same credits as imports and was about five times faster
#' with `workers = 8` (3,000 DOIs: 8.5 s instead of 45 to 55 s, November
#' 2026). Fields in `select` beyond `id` are fetched in the same pass, from
#' the queries themselves, so the records do not depend on the collection
#' filter limit. An interrupted run resumes the fetch and adds the members
#' again (adding is idempotent). A changed query re-creates the collection,
#' and `refresh = TRUE` fetches and adds everything again.
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
#'   queries. Without `name`, each element of the list becomes its own
#'   collection, named after its list names (nested names joined with `_`).
#'   With `name`, all queries in the list go into one collection (see
#'   **Several queries in one collection**).
#' @param name Name of the collection (and of its folder). Required for a
#'   single query. For a list: `NULL` gives one collection per element, a
#'   name gives one collection for the whole list.
#' @param project_folder Directory for the `<name>.collection` folders.
#' @param select What to download: `"id"` (default) the member IDs only;
#'   `NULL` nothing; `"all"` the full records; or a character vector of
#'   fields (see [opt_select_fields()]) for records with those fields. The
#'   member IDs are downloaded whenever `select` is not `NULL`.
#' @param refresh If `TRUE`, import an unchanged query again and re-download.
#' @param api_key A personal OpenAlex API key.
#' @param verbose Print the collection ID(s).
#' @param progress Show the steps and import progress.
#' @param ... Passed to [pro_fetch()] when records are downloaded, and when
#'   the queries of a list with `name` are fetched (e.g. `workers`,
#'   `compact_parquet`).
#'
#' @return Invisibly, the path of the `.collection` folder, or a named
#'   character vector of paths for a list of queries without `name`.
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
#'
#' # A long DOI list in one collection: the chunks are fetched in parallel
#' # and their IDs added as members
#' pro_collection(pro_query(doi = dois, chunk_limit = 200), name = "my dois",
#'                project_folder = "proj", workers = 8)
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
  } else if (is.null(name)) {
    queries <- .col_leaves(query_url)
  } else if (!is.character(name) || length(name) != 1L) {
    stop("`name` must be a single name.", call. = FALSE)
  }
  nms <- if (is.null(name)) names(queries) else name
  bad <- nms[nchar(nms) > 100L]
  if (length(bad)) {
    stop("Collection names can have at most 100 characters: ", bad[[1]], call. = FALSE)
  }
  dir.create(project_folder, recursive = TRUE, showWarnings = FALSE)
  if (!is.character(query_url) && !is.null(name)) {
    # all queries into one collection: fetched, their IDs added as members
    return(invisible(.col_members(unlist(.col_leaves(query_url)), name, project_folder,
                                  select, refresh, api_key, verbose, progress, ...)))
  }

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

#' One query -> one collection folder, filled by an import
#' @keywords internal
#' @noRd
.col_one <- function(url, name, project_folder, select, refresh, api_key,
                     verbose, progress, ...) {
  started <- Sys.time()
  folder <- .col_folder(project_folder, name)
  rec_file <- file.path(folder, "_collection.json")
  root <- .col_root(url)
  step <- .col_stepper(name, progress)

  # 1. Validate the query (free) before anything is created
  step("validating query")
  oq <- .col_check(url, api_key)
  entity <- oq$oqo$get_rows %||% "works"

  # 2. Keep, re-create or create the collection
  rec <- .col_read_record(rec_file)
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
        .col_clear(folder)
        imports <- list()
        prev_credits <- 0
      }
    } else {
      .col_replace(root, rec$collection_id, folder, api_key, step)
    }
  }

  created <- is.null(col)
  credits0 <- .col_credits(root, api_key)
  query <- function() {
    list(query_url = .pr_strip_key(url), via = "collection", oql = oq$oql, oqo = oq$oqo)
  }
  if (created) {
    col <- .col_create(root, name, entity, folder, api_key, step)
    # Written now so an interrupted run knows the collection
    .col_write_record(rec_file, c(query(), list(credits_import = NA)), col,
                      list(imports = imports), select = NULL, started = started)
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
  fetch_records <- function(sel, dir) {
    pro_fetch(pro_query(entity, collection = id, select = sel),
              project_folder = dir, overwrite = TRUE, api_key = api_key,
              verbose = verbose, progress = progress, ...)
  }
  .col_sync_downloads(folder, root, id, select,
                      old_select = if (!fresh && !is.null(rec)) unlist(rec$select),
                      fresh_members = fresh, fresh_records = fresh,
                      fetch_records = fetch_records, api_key = api_key, step = step)

  .col_write_record(rec_file, c(query(), list(credits_import = credits)), col,
                    list(imports = imports), select = select, started = started)
  normalizePath(folder)
}

#' Translate one query (free) and check that it can be imported
#' @keywords internal
#' @noRd
.col_check <- function(url, api_key) {
  no_import <- "Queries with `group_by` or `sample` cannot be imported into a collection."
  if (grepl("[?&](group_by|sample)=", url)) stop(no_import, call. = FALSE)
  oq <- .oa_to_oqo(url, api_key)
  if (is.null(oq)) {
    stop("A single record cannot be made into a collection.", call. = FALSE)
  }
  if (!is.null(oq$oqo$group_by) || !is.null(oq$oqo$sample)) stop(no_import, call. = FALSE)
  if (nchar(oq$oql) > 20000L) {
    stop("The query is ", format(nchar(oq$oql), big.mark = ","), " characters as OQL; ",
         "OpenAlex imports at most 20,000. Split it, e.g. ",
         "`pro_query(..., chunk_limit = 200)`, and pass the list of chunks with `name`: ",
         "they are fetched with pro_fetch() and their IDs added to one collection.",
         call. = FALSE)
  }
  oq
}

#' A list of queries -> one collection folder: the queries are fetched with
#' pro_fetch() (in parallel with `workers`) and the IDs added as members
#' (`member_ids`, 10,000 per request, free). Faster than one import per query,
#' and without the import's 20,000-character limit.
#' @keywords internal
#' @noRd
.col_members <- function(urls, name, project_folder, select, refresh, api_key,
                         verbose, progress, ...) {
  started <- Sys.time()
  folder <- .col_folder(project_folder, name)
  rec_file <- file.path(folder, "_collection.json")
  parts_file <- file.path(folder, "_parts.parquet")
  root <- .col_root(urls[[1]])
  step <- .col_stepper(name, progress)
  n <- length(urls)

  # 1. Checks without requests: pro_fetch() validates each query (free)
  #    before it spends credits
  step(sprintf("checking %d queries", n))
  bad <- names(urls)[grepl("[?&](group_by|sample)=", urls)]
  if (length(bad)) {
    stop("Query `", bad[[1]], "` uses `group_by` or `sample`, which cannot be made ",
         "into a collection.", call. = FALSE)
  }
  entity <- unique(sub("^/", "", vapply(urls, function(u) httr2::url_parse(u)$path, "")))
  if (length(entity) > 1L) {
    stop("All queries of one collection must list the same entity, not ",
         paste(entity, collapse = " and "), ".", call. = FALSE)
  }
  if (!nzchar(entity) || grepl("/", entity)) { # e.g. an `oql` query on the root
    entity <- .col_check(urls[[1]], api_key)$oqo$get_rows %||% "works"
  }

  # 2. Keep, re-create or create the collection
  rec <- .col_read_record(rec_file)
  col <- NULL
  prev_credits <- 0
  if (!is.null(rec)) {
    old <- .col_read_parts(parts_file)
    if (identical(rec$via, "members") && identical(old$part, names(urls)) &&
        identical(old$query_url, unname(urls))) {
      col <- .col_get(root, rec$collection_id, api_key)
      prev_credits <- as.numeric(rec$credits %||% 0)
      if (is.null(col)) {
        step("collection is gone on OpenAlex; re-creating it")
        .col_clear(folder)
        rec <- NULL
        prev_credits <- 0
      }
    } else {
      .col_replace(root, rec$collection_id, folder, api_key, step)
      rec <- NULL
    }
  }

  created <- is.null(col)
  credits0 <- .col_credits(root, api_key)
  query <- function(credits, done = list()) {
    c(list(via = "members", parts = n, parts_file = basename(parts_file),
           credits = credits), done)
  }
  if (created) {
    col <- .col_create(root, name, entity, folder, api_key, step)
    .col_write_parts(parts_file, urls)
    # Written now so an interrupted run knows the collection
    .col_write_record(rec_file, query(NA, list(members_added = FALSE)), col,
                      select = NULL, started = started)
  } else {
    step("collection exists")
  }
  id <- .col_id(col$id)
  if (verbose) cli::cli_alert_info(paste0("[", name, "] collection ", id))

  # 3. Fetch the IDs (and the records, if selected) and add them as members.
  #    Also after an interruption: adding is idempotent, and pro_fetch()
  #    resumes a fetch that did not finish.
  fields <- setdiff(select, "id")
  sel <- if ("all" %in% fields) NULL else c("id", fields)
  fetch_records <- function(sel, dir, resume = FALSE) {
    pro_fetch(lapply(urls, .col_with_select, sel), project_folder = dir,
              overwrite = TRUE, resume = resume, api_key = api_key,
              verbose = verbose, progress = progress, ...)
  }
  done <- rec[intersect(c("members_added", "added", "already_present"), names(rec))]
  fetched <- created || isTRUE(refresh) || !isTRUE(rec$members_added)
  if (fetched) {
    dir <- file.path(folder, if (length(fields)) "records" else "_ids")
    step(if (length(fields)) "fetching records" else "fetching IDs")
    fetch_records(sel, dir, resume = !created && !isTRUE(refresh) && dir.exists(dir))
    step("adding members")
    done <- c(list(members_added = TRUE),
              .col_add_members(root, id, .col_fetched_ids(dir), api_key, progress))
    unlink(file.path(folder, "_ids"), recursive = TRUE)
  }
  col <- .col_get(root, id, api_key) %||% col
  credits <- sum(prev_credits, .col_credits(root, api_key) - credits0, na.rm = TRUE)

  # 4. Downloads, in line with `select`; records fetched just now stay
  .col_sync_downloads(folder, root, id, select,
                      old_select = if (fetched) select else if (!is.null(rec)) unlist(rec$select),
                      fresh_members = fetched, fresh_records = FALSE,
                      fetch_records = fetch_records, api_key = api_key, step = step)

  .col_write_record(rec_file, query(credits, done), col, select = select,
                    started = started)
  normalizePath(folder)
}

#' Add member IDs, `batch` per request (OpenAlex takes at most 10,000)
#' @keywords internal
#' @noRd
.col_add_members <- function(root, id, ids, api_key, progress, batch = 10000L) {
  groups <- split(ids, ceiling(seq_along(ids) / batch))
  pb <- if (progress && length(groups) > 1L) {
    cli::cli_progress_bar(format = "adding members {cli::pb_bar} {cli::pb_current}/{cli::pb_total}",
                          total = length(ids))
  }
  added <- 0
  present <- 0
  for (g in groups) {
    r <- .col_json(.col_req(root, "POST", c("collections", id, "members"), api_key,
      body = list(member_ids = as.list(g)), ok = c(200L, 201L)))
    added <- added + (r$added %||% 0)
    present <- present + (r$already_present %||% 0)
    if (!is.null(pb)) cli::cli_progress_update(id = pb, inc = length(g))
  }
  if (!is.null(pb)) cli::cli_progress_done(id = pb)
  list(added = added, already_present = present)
}

#' Distinct short IDs in a pro_fetch() folder
#' @keywords internal
#' @noRd
.col_fetched_ids <- function(dir) {
  files <- list.files(file.path(dir, "parquet"), pattern = "\\.parquet$",
                      recursive = TRUE, full.names = TRUE)
  if (!length(files)) return(character(0))
  con <- .pro_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbGetQuery(con, sprintf(
    "SELECT DISTINCT regexp_replace(id, '^.*/', '') AS id FROM read_parquet([%s], union_by_name = true) WHERE id IS NOT NULL",
    paste(vapply(files, .pro_sql_str, ""), collapse = ", ")
  ))$id
}

#' `_parts.parquet`: the queries of a members collection (name, URL), in order
#' @keywords internal
#' @noRd
.col_write_parts <- function(file, urls) {
  con <- .pro_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  duckdb::duckdb_register(con, "parts", data.frame(
    i = seq_along(urls), part = names(urls), query_url = unname(urls),
    stringsAsFactors = FALSE
  ))
  part <- paste0(file, ".part")
  DBI::dbExecute(con, sprintf(
    "COPY (SELECT * FROM parts ORDER BY i) TO %s (FORMAT parquet, COMPRESSION zstd)",
    .pro_sql_str(part)
  ))
  file.rename(part, file)
}

#' @keywords internal
#' @noRd
.col_read_parts <- function(file) {
  if (!file.exists(file)) return(NULL)
  con <- .pro_con()
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  DBI::dbGetQuery(con, sprintf(
    "SELECT part, query_url FROM read_parquet(%s) ORDER BY i", .pro_sql_str(file)))
}

#' A query URL with `select` set (`NULL`: all fields)
#' @keywords internal
#' @noRd
.col_with_select <- function(url, sel) {
  u <- httr2::url_parse(url)
  u$query$select <- if (length(sel)) paste(sel, collapse = ",")
  httr2::url_build(u)
}

#' @keywords internal
#' @noRd
.col_folder <- function(project_folder, name) {
  file.path(project_folder, paste0(gsub("[/\\\\]", "_", name), ".collection"))
}

#' @keywords internal
#' @noRd
.col_root <- function(url) sub("(^https?://[^/?#]+).*", "\\1", url)

#' A cli step reporter for one collection
#' @keywords internal
#' @noRd
.col_stepper <- function(name, progress) {
  env <- parent.frame()
  function(msg) {
    if (progress) {
      cli::cli_progress_step(gsub("([{}])", "\\1\\1", paste0("[", name, "] ", msg)),
                             .envir = env)
    }
  }
}

#' @keywords internal
#' @noRd
.col_read_record <- function(file) {
  if (file.exists(file)) jsonlite::read_json(file, simplifyVector = FALSE)
}

#' Delete the local downloads and query files of a collection folder
#' @keywords internal
#' @noRd
.col_clear <- function(folder) {
  unlink(file.path(folder, c("members", "records", "_ids", "_parts.parquet",
                             "_query_oql.txt", "_query_oql.html")),
         recursive = TRUE)
}

#' The query changed: delete the old collection and the local files
#' @keywords internal
#' @noRd
.col_replace <- function(root, old_id, folder, api_key, step) {
  step(paste("query changed: deleting collection", old_id, "and re-creating it"))
  .col_req(root, "DELETE", c("collections", old_id), api_key, ok = c(204L, 404L))
  .col_clear(folder)
}

#' @keywords internal
#' @noRd
.col_create <- function(root, name, entity, folder, api_key, step) {
  step("creating collection")
  col <- .col_json(.col_req(root, "POST", "collections", api_key,
    body = list(display_name = name, entity_type = entity), ok = 201L))
  dir.create(folder, recursive = TRUE, showWarnings = FALSE)
  col
}

#' Bring `members/` and `records/` in line with `select`
#'
#' `fetch_records(sel, dir)` downloads the records with fields `sel` (`NULL`:
#' all) into `dir`.
#' @keywords internal
#' @noRd
.col_sync_downloads <- function(folder, root, id, select, old_select, fresh_members,
                                fresh_records, fetch_records, api_key, step) {
  members <- file.path(folder, "members")
  records <- file.path(folder, "records")
  if (is.null(select)) {
    unlink(c(members, records), recursive = TRUE)
    return(invisible())
  }
  if (fresh_members || !dir.exists(file.path(members, "parquet"))) {
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
  refetch <- fresh_records || is.null(old_f) || !identical(all_new, "all" %in% old_f) ||
    !all(new_f %in% old_f)
  if (refetch) {
    step("downloading records")
    fetch_records(if (all_new) NULL else c("id", new_f), records)
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

#' Write `_collection.json`: the route's query fields, the collection, `extra`
#' @keywords internal
#' @noRd
.col_write_record <- function(file, query, col, extra = list(), select, started) {
  record <- c(
    query,
    list(
      records = col$member_count,
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
      updated_date = col$updated_date
    ),
    extra,
    list(select = if (!is.null(select)) as.list(select))
  )
  jsonlite::write_json(record, file, auto_unbox = TRUE, pretty = TRUE,
                       null = "null", digits = NA)
}
