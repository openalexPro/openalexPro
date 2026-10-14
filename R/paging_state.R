# paging_state.R ---------------------------------------------------------------
#
# Resuming a query in the middle: `_paging.json`.
#
# OpenAlex cursors are stateless positions in the sort order (sort values and
# the last work ID; for grouped results the last group key). They do not
# expire, and they contain nothing about the query -- every page request sends
# the full query again plus the cursor. So the state needed to continue is the
# exact query and the position:
#
# - written after each saved page that has a `next_cursor` (one-page queries
#   never write it), atomically (`.part` + rename);
# - cursor paging only: samples (page number + seed) and semantic search
#   (single page) restart from page 1, which is cheap;
# - `.ps_read()` never fails: anything it cannot trust leads back to today's
#   behaviour, fetching the query again from page 1.

.ps_file <- function(output) file.path(output, "_paging.json")

# The query URL without a key a user may have put into it
.pr_strip_key <- function(url) sub("([?&])api_key=[^&]*&?", "\\1", url)

.ps_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

#' Write `_paging.json` atomically
#' @keywords internal
#' @noRd
.ps_write <- function(output, state) {
  file <- .ps_file(output)
  part <- paste0(file, ".part")
  jsonlite::write_json(state, part, auto_unbox = TRUE, null = "null",
                       digits = NA, pretty = TRUE)
  if (!file.rename(part, file)) {
    stop("Could not write ", file, call. = FALSE)
  }
  invisible(file)
}

#' Read `_paging.json` if the query can be continued from it
#'
#' Returns `NULL` (fetch the query again from page 1) unless the state belongs
#' to the same query and the same way of sending it, and pages 1..N are on
#' disk with page N readable. Then page files above N -- saved after the last
#' state write -- are removed (they are fetched again), and the state is
#' returned with `data` = page N as parsed from disk.
#'
#' @keywords internal
#' @noRd
.ps_read <- function(output, query_url, via) {
  file <- .ps_file(output)
  unlink(paste0(file, ".part"))
  if (!file.exists(file)) {
    return(NULL)
  }
  restart <- function(why) {
    message(
      "Cannot resume `", basename(output), "` in the middle (", why, "): ",
      "fetching it again from the start."
    )
    NULL
  }
  s <- tryCatch(jsonlite::read_json(file, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(s) || !isTRUE(s$format == 1L)) {
    return(restart("_paging.json is unreadable"))
  }
  if (!identical(s$query_url, .pr_strip_key(query_url))) {
    return(restart("_paging.json belongs to a different query"))
  }
  if (!identical(s$via, via)) {
    return(restart(paste0("it was sent with via = \"", s$via, "\"")))
  }
  n <- s$page
  if (!is.numeric(n) || length(n) != 1L || n < 1 ||
      !(s$page_prefix %in% c("results_page_", "group_by_page_"))) {
    return(restart("_paging.json is incomplete"))
  }
  pages <- file.path(output, paste0(s$page_prefix, seq_len(n), ".json"))
  if (!all(file.exists(pages)) || any(file.size(pages) == 0)) {
    return(restart(paste0("pages 1 to ", n, " are not all there")))
  }
  data <- tryCatch(jsonlite::read_json(pages[n], simplifyVector = FALSE),
                   error = function(e) NULL)
  if (is.null(data$meta)) {
    return(restart(paste0("page ", n, " is unreadable")))
  }
  if (identical(s$status, "downloading") && is.null(data$meta$next_cursor)) {
    return(restart(paste0("page ", n, " has no cursor to continue from")))
  }
  # Pages saved after the last state write are fetched again
  on_disk <- list.files(output, "^(results_page|group_by_page)_[0-9]+\\.json$",
                        full.names = TRUE)
  number <- as.integer(sub(".*_([0-9]+)\\.json$", "\\1", on_disk))
  unlink(on_disk[number > n])
  s$data <- data
  s
}

#' Human-readable age of an ISO time stamp, e.g. "3.2 hours"
#' @keywords internal
#' @noRd
.ps_age <- function(iso) {
  t <- as.POSIXct(iso, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  if (is.na(t)) {
    return("unknown time")
  }
  format(round(difftime(Sys.time(), t), 1))
}

# Consistency after a resume ---------------------------------------------------

#' Check a resumed query for duplicates and missing records
#'
#' Duplicates are found exactly, by work ID, across all pages (records can move
#' anywhere in the sort order, e.g. when citation counts change). Missing
#' records can only be found as a net difference to OpenAlex's current count:
#' a record lost and another added elsewhere cancel out.
#'
#' @param policy One of `"error"`, `"warning"`, `"ignore"`, `"oldest"`,
#'   `"newest"`.
#' @param records_end OpenAlex's current count, or `NULL` when it cannot be
#'   compared (e.g. stopped by the `pages` limit).
#' @return A list for `_query.json` (`duplicates`, `duplicates_removed`,
#'   `missing_net`, `records_saved`), or an error with class
#'   `openalexPro_inconsistency` for `policy = "error"`.
#' @keywords internal
#' @noRd
.ps_check <- function(output, policy, records_end, cursor_created, name) {
  files <- list.files(output, "^results_page_[0-9]+\\.json$", full.names = TRUE)
  files <- files[order(as.integer(sub(".*_([0-9]+)\\.json$", "\\1", files)))]
  ids <- .ps_ids(files)
  dup <- duplicated(ids$id)
  n_dup <- sum(dup)
  unique_saved <- length(unique(ids$id))
  missing_net <- if (is.null(records_end)) NULL else as.integer(records_end) - unique_saved

  problems <- c(
    if (n_dup > 0L) {
      paste0(n_dup, if (n_dup == 1L) " record appears twice" else " records appear twice")
    },
    if (!is.null(missing_net) && missing_net != 0L) {
      paste0(
        abs(missing_net),
        if (missing_net > 0L) " fewer" else " more",
        " records than OpenAlex now reports (net difference: a record lost and ",
        "another added since cancel out)"
      )
    }
  )
  info <- list(duplicates = n_dup, duplicates_removed = 0L,
               missing_net = missing_net, records_saved = unique_saved)
  if (length(problems) == 0L || policy == "ignore") {
    return(info)
  }
  what <- paste0(
    "Resumed query `", name, "`: ", paste(problems, collapse = "; "), ". ",
    "The data changed since the cursor was created (", .ps_age(cursor_created),
    " ago)."
  )
  if (policy == "error") {
    rlang::abort(paste0(
      what, "\nNothing is lost: rerun with `resume = TRUE` and ",
      "`inconsistency_on_resume = \"newest\"` or `\"oldest\"` (keep one copy), ",
      "`\"warning\"` or `\"ignore\"` (keep both) -- this applies the choice ",
      "without downloading anything again. Or use `overwrite = TRUE` to fetch ",
      "the query again completely."
    ), class = "openalexPro_inconsistency")
  }
  if (policy %in% c("oldest", "newest") && n_dup > 0L) {
    info$duplicates_removed <- .ps_drop_copies(ids, keep = policy)
    rest <- problems[-1L]
    if (length(rest) > 0L) {
      warning("Resumed query `", name, "`: ", rest, ".", call. = FALSE)
    }
    return(info)
  }
  warning(what, call. = FALSE)
  info
}

#' IDs and pages of the records in page files (DuckDB, fast for many files)
#' @keywords internal
#' @noRd
.ps_ids <- function(files) {
  if (length(files) == 0L) {
    return(data.frame(id = character(0), file = character(0), pos = integer(0)))
  }
  con <- .pro_con(json = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  # Two unnest() in one SELECT are paired element by element: the record and
  # its position within the page.
  sql <- sprintf(
    "SELECT filename AS file, r.id AS id, pos
       FROM (SELECT filename,
                    unnest(results) AS r,
                    unnest(range(1, len(results) + 1)) AS pos
               FROM read_json([%s], columns = {results: 'STRUCT(id VARCHAR)[]'},
                              filename = true))",
    paste0("'", gsub("'", "''", files), "'", collapse = ", ")
  )
  out <- DBI::dbGetQuery(con, sql)
  # page order, then position within the page = download order
  out <- out[order(match(out$file, files), out$pos), , drop = FALSE]
  rownames(out) <- NULL
  out
}

#' Remove duplicate copies from their page files
#'
#' @param ids Data frame from `.ps_ids()` in download order.
#' @param keep `"oldest"` (first downloaded copy) or `"newest"` (last).
#' @return Number of copies removed.
#' @keywords internal
#' @noRd
.ps_drop_copies <- function(ids, keep) {
  drop <- if (keep == "oldest") {
    duplicated(ids$id)
  } else {
    duplicated(ids$id, fromLast = TRUE)
  }
  for (f in unique(ids$file[drop])) {
    remove_pos <- ids$pos[drop & ids$file == f]
    page <- jsonlite::read_json(f, simplifyVector = FALSE)
    page$results <- page$results[-remove_pos]
    part <- paste0(f, ".part")
    jsonlite::write_json(page, part, auto_unbox = TRUE, null = "null", digits = NA)
    if (!file.rename(part, f)) {
      stop("Could not rewrite ", f, call. = FALSE)
    }
  }
  sum(drop)
}
