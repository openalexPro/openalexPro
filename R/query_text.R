# query_text.R ----------------------------------------------------------------
#
# Human-readable record of each query, for methods sections and supplements:
# `_query_oql.txt` (plain text) and `_query_oql.html` (self-contained, keywords
# highlighted), next to `_query.json`.
#
# The OQL is OpenAlex's own rendering of the OQO that actually ran. OpenAlex's
# current translator renders some details lossily (e.g. a wildcard from a
# classic URL), so the OQL is translated back and compared with that OQO: the
# files say whether the printed OQL reproduces the query exactly, or is only a
# readable description (then the OQO in `_query.json` is the exact query).

#' Write `_query_oql.txt` and `_query_oql.html` for a downloaded query
#'
#' Best effort: uses two free `/query` calls; if OpenAlex cannot be reached the
#' files are written from `oql_fallback` and marked as not checked. Never
#' fails the download.
#'
#' @param output Query directory.
#' @param oqo The OQO that ran (list), or `NULL` (then nothing is written).
#' @param oql_fallback One-line OQL to use if `/query` is not reachable.
#' @param root API root, e.g. `"https://api.openalex.org"`.
#' @param records Number of records (`meta$count`).
#' @param query_url The query URL (key-free), shown in the HTML.
#' @keywords internal
#' @noRd
.pr_write_query_text <- function(output, oqo, oql_fallback, root, api_key,
                                 records, query_url) {
  if (is.null(oqo)) {
    return(invisible(NULL))
  }
  tryCatch(
    {
      # 1. OpenAlex's readable rendering of the OQO that ran
      rendered <- .oa_query_endpoint(root, list(oqo = oqo), api_key)
      oql <- rendered$oql %||% oql_fallback
      oql_oneline <- rendered$oql_oneline %||% oql_fallback
      # 2. Does that OQL translate back to the same query?
      exact <- NA
      if (!is.null(oql_oneline)) {
        back <- .oa_query_endpoint(root, list(oql = oql_oneline), api_key)
        if (!is.null(back$oqo)) {
          exact <- .oqo_equivalent(back$oqo, oqo)
        }
      }
      if (is.null(oql)) {
        return(invisible(NULL))
      }
      info <- list(
        records = records,
        date = format(Sys.time(), "%Y-%m-%d", tz = "UTC"),
        version = as.character(utils::packageVersion("openalexPro")),
        exact = exact
      )
      writeLines(.oql_text(oql, info), file.path(output, "_query_oql.txt"))
      writeLines(
        .oql_html(oql, info, oqo, query_url),
        file.path(output, "_query_oql.html")
      )
    },
    error = function(e) invisible(NULL)
  )
  invisible(NULL)
}

#' Call `/query` without stopping on an invalid query
#'
#' @return The parsed response, or `NULL`.
#' @keywords internal
#' @noRd
.oa_query_endpoint <- function(root, body, api_key = NULL) {
  tryCatch(
    {
      req <- httr2::request(root) |>
        httr2::req_url_path_append("query") |>
        httr2::req_method("POST") |>
        httr2::req_body_json(body, auto_unbox = TRUE) |>
        .oa_auth(api_key) |>
        httr2::req_user_agent(paste0("openalexPro/", utils::packageVersion("openalexPro")))
      httr2::resp_body_json(api_call(req, get_html_response = NULL))
    },
    error = function(e) NULL
  )
}

#' Do two OQOs describe the same query?
#'
#' Order of AND-ed conditions and of the members of a group does not change
#' the query, so lists of conditions are compared as sets.
#'
#' @keywords internal
#' @noRd
.oqo_equivalent <- function(a, b) {
  canon <- function(x) {
    if (is.list(x) && !is.null(names(x)) && all(nzchar(names(x)))) {
      x <- Filter(Negate(is.null), x)
      x <- x[order(names(x))]
      for (k in names(x)) {
        x[[k]] <- if (k %in% c("filter_rows", "filters", "group_by")) {
          items <- lapply(x[[k]], canon)
          items[order(vapply(items, function(i) {
            as.character(jsonlite::toJSON(i, auto_unbox = TRUE))
          }, ""))]
        } else {
          canon(x[[k]])
        }
      }
      x
    } else if (is.list(x)) {
      lapply(x, canon)
    } else if (is.numeric(x)) {
      as.numeric(x) # 2020 and 2020L are the same value
    } else {
      x
    }
  }
  identical(
    as.character(jsonlite::toJSON(canon(a), auto_unbox = TRUE, digits = NA)),
    as.character(jsonlite::toJSON(canon(b), auto_unbox = TRUE, digits = NA))
  )
}

.oql_exact_note <- function(exact) {
  if (isTRUE(exact)) {
    "Exact: this OQL translates back to exactly the query that ran."
  } else if (isFALSE(exact)) {
    paste(
      "Not exact: OpenAlex's rendering of this query is lossy;",
      "this OQL is a readable description only. The exact query is the OQO",
      "in _query.json."
    )
  } else {
    "Not checked: OpenAlex's /query endpoint could not be reached."
  }
}

#' Plain-text version
#' @keywords internal
#' @noRd
.oql_text <- function(oql, info) {
  c(
    "# OpenAlex query (OQL)",
    paste0(
      "# Records: ", info$records %||% "-",
      " | Downloaded: ", info$date, " (UTC)",
      " | openalexPro ", info$version
    ),
    paste0("# ", .oql_exact_note(info$exact)),
    "",
    oql
  )
}

#' Highlight OQL as HTML (escaped)
#'
#' Tokens: OpenAlex labels `[Nature](S137773608)` (linked to the record when
#' the target is an OpenAlex ID), quoted strings, boolean operators inside
#' search groups (AND / OR / NOT), numbers, and OQL keywords.
#' @keywords internal
#' @noRd
.oql_highlight <- function(oql) {
  esc <- function(x) {
    x <- gsub("&", "&amp;", x, fixed = TRUE)
    x <- gsub("<", "&lt;", x, fixed = TRUE)
    x <- gsub(">", "&gt;", x, fixed = TRUE)
    gsub('"', "&quot;", x, fixed = TRUE)
  }
  keywords <- c(
    "get", "where", "and", "or", "not", "is", "has", "within", "sample",
    "seed", "group", "by", "then", "those", "summarize", "using", "with",
    "published", "from", "through", "since", "before", "after", "in",
    "of", "each", "count", "bins", "at", "stemmed", "similar", "to",
    "compare", "versus", "vs", "split", "into", "unknown", "null", "true",
    "false"
  )
  pattern <- paste0(
    "\\[([^\\]]+)\\]\\(([^)]+)\\)", # [label](target)
    "|\"[^\"]*\"", # "string"
    "|\\b(?:AND|OR|NOT)\\b", # boolean operators in search groups
    "|\\b\\d+(?:\\.\\d+)?\\b", # numbers
    "|\\b(?:", paste(keywords, collapse = "|"), ")\\b"
  )
  m <- gregexpr(pattern, oql, perl = TRUE)[[1]]
  if (m[1] == -1) {
    return(esc(oql))
  }
  starts <- as.integer(m)
  ends <- starts + attr(m, "match.length") - 1L
  out <- character(0)
  pos <- 1L
  for (i in seq_along(starts)) {
    if (starts[i] > pos) out <- c(out, esc(substr(oql, pos, starts[i] - 1L)))
    tok <- substr(oql, starts[i], ends[i])
    out <- c(out, if (startsWith(tok, "[")) {
      label <- sub("^\\[([^\\]]+)\\].*$", "\\1", tok, perl = TRUE)
      target <- sub("^.*\\]\\(([^)]+)\\)$", "\\1", tok)
      if (grepl("^[A-Za-z]\\d+$", target)) {
        sprintf(
          '<a class="label" href="https://openalex.org/%s" title="%s">%s</a>',
          esc(target), esc(target), esc(label)
        )
      } else {
        sprintf('<span class="label" title="%s">%s</span>', esc(target), esc(label))
      }
    } else if (startsWith(tok, "\"")) {
      sprintf('<span class="str">%s</span>', esc(tok))
    } else if (tok %in% c("AND", "OR", "NOT")) {
      sprintf('<span class="bool">%s</span>', tok)
    } else if (grepl("^\\d", tok)) {
      sprintf('<span class="num">%s</span>', tok)
    } else {
      sprintf('<span class="kw">%s</span>', tok)
    })
    pos <- ends[i] + 1L
  }
  if (pos <= nchar(oql)) out <- c(out, esc(substr(oql, pos, nchar(oql))))
  paste(out, collapse = "")
}

#' Shared CSS of the query pages (light and dark)
#' @keywords internal
#' @noRd
.oql_css <- function() {
  c(
    ":root{--bg:#fff;--fg:#1f2328;--muted:#59636e;--box:#f6f8fa;--line:#d1d9e0;",
    "--kw:#8250df;--bool:#cf222e;--str:#0a3069;--num:#0550ae;--label:#116329;",
    "--ok:#1a7f37;--warn:#9a6700;}",
    "@media (prefers-color-scheme: dark){:root{--bg:#0d1117;--fg:#e6edf3;--muted:#9198a1;",
    "--box:#161b22;--line:#3d444d;--kw:#d2a8ff;--bool:#ff7b72;--str:#a5d6ff;",
    "--num:#79c0ff;--label:#7ee787;--ok:#3fb950;--warn:#d29922;}}",
    "body{background:var(--bg);color:var(--fg);margin:0 auto;max-width:920px;",
    "padding:24px 16px;font:15px/1.5 -apple-system,Segoe UI,Helvetica,Arial,sans-serif;}",
    "h1{font-size:20px;margin:0 0 4px}",
    ".meta{color:var(--muted);margin:0 0 16px}",
    "pre{background:var(--box);border:1px solid var(--line);border-radius:6px;",
    "padding:14px 16px;overflow-x:auto;font:14px/1.6 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;",
    "white-space:pre-wrap;word-break:break-word;}",
    ".kw{color:var(--kw);font-weight:600}.bool{color:var(--bool);font-weight:700}",
    ".str{color:var(--str)}.num{color:var(--num)}",
    ".label{color:var(--label);text-decoration:none;border-bottom:1px dotted var(--label)}",
    ".note{border-left:4px solid var(--line);padding:6px 12px;margin:0 0 16px;background:var(--box)}",
    ".note.exact{border-color:var(--ok)}.note.inexact{border-color:var(--warn)}",
    "details{margin-top:16px}summary{cursor:pointer;color:var(--muted)}",
    "code{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:13px;word-break:break-all}",
    ".summary{border-collapse:collapse;width:100%;margin:0 0 20px}",
    ".summary th,.summary td{text-align:left;padding:4px 10px;border-bottom:1px solid var(--line)}",
    ".summary td.n{text-align:right;font-variant-numeric:tabular-nums}",
    ".summary a{color:var(--fg)}",
    "h2{font-size:16px;margin:28px 0 4px}",
    ".badge{font-size:12px;padding:1px 8px;border-radius:10px;border:1px solid var(--line);white-space:nowrap}",
    ".badge.exact{color:var(--ok);border-color:var(--ok)}.badge.inexact{color:var(--warn);border-color:var(--warn)}"
  )
}

#' Self-contained HTML version (no scripts, no external resources)
#' @keywords internal
#' @noRd
.oql_html <- function(oql, info, oqo, query_url) {
  esc <- function(x) {
    x <- gsub("&", "&amp;", x, fixed = TRUE)
    x <- gsub("<", "&lt;", x, fixed = TRUE)
    gsub(">", "&gt;", x, fixed = TRUE)
  }
  state <- if (isTRUE(info$exact)) "exact" else if (isFALSE(info$exact)) "inexact" else "unchecked"
  oqo_json <- as.character(jsonlite::toJSON(oqo, auto_unbox = TRUE, pretty = TRUE, digits = NA))
  c(
    "<!doctype html>",
    '<html lang="en"><head><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    "<title>OpenAlex query (OQL)</title>",
    "<style>",
    .oql_css(),
    "</style></head><body>",
    "<h1>OpenAlex query</h1>",
    sprintf(
      '<p class="meta">%s records &middot; downloaded %s (UTC) &middot; openalexPro %s</p>',
      esc(format(info$records %||% "-", big.mark = ",")), esc(info$date), esc(info$version)
    ),
    sprintf('<p class="note %s">%s</p>', state, esc(.oql_exact_note(info$exact))),
    paste0("<pre>", .oql_highlight(oql), "</pre>"),
    "<details><summary>Exact query (OQO)</summary>",
    paste0("<pre>", esc(oqo_json), "</pre></details>"),
    if (!is.null(query_url)) {
      c(
        "<details><summary>Request URL</summary>",
        paste0("<p><code>", esc(query_url), "</code></p></details>")
      )
    },
    "</body></html>"
  )
}

# Summary of all queries -------------------------------------------------------

#' Write `_queries_oql.txt` and `_queries_oql.html` for a list download
#'
#' One overview of all queries -- name, records, whether the OQL is exact, and
#' the OQL -- in the order of the query list, for a paper's supplement. Built
#' from the per-query files on disk, so queries skipped by `resume` are
#' included and failed ones are listed as not downloaded. Best effort.
#'
#' @param output Top output directory of [pro_request()].
#' @param leaf_paths List of name vectors, one per query (as in `pro_request`).
#' @keywords internal
#' @noRd
.pr_write_queries_summary <- function(output, leaf_paths) {
  if (is.null(output) || length(leaf_paths) == 0L || !dir.exists(output)) {
    return(invisible(NULL))
  }
  tryCatch(
    {
      rows <- lapply(leaf_paths, .pr_query_summary_row, output = output)
      info <- list(
        date = format(Sys.time(), "%Y-%m-%d", tz = "UTC"),
        version = as.character(utils::packageVersion("openalexPro"))
      )
      writeLines(.oql_summary_text(rows, info), file.path(output, "_queries_oql.txt"))
      writeLines(.oql_summary_html(rows, info), file.path(output, "_queries_oql.html"))
    },
    error = function(e) invisible(NULL)
  )
  invisible(NULL)
}

#' One query's entry for the summary, read from its directory
#' @keywords internal
#' @noRd
.pr_query_summary_row <- function(parts, output) {
  dir <- do.call(file.path, c(list(output), as.list(parts)))
  rec_file <- file.path(dir, "_query.json")
  txt_file <- file.path(dir, "_query_oql.txt")
  rec <- if (file.exists(rec_file)) jsonlite::read_json(rec_file) else NULL
  status <- "missing"
  oql <- character(0)
  if (file.exists(txt_file)) {
    txt <- readLines(txt_file, warn = FALSE)
    status <- if (startsWith(txt[3], "# Exact")) {
      "exact"
    } else if (startsWith(txt[3], "# Not exact")) {
      "inexact"
    } else {
      "unchecked"
    }
    oql <- txt[-(1:4)] # after the three header lines and the blank line
  } else if (!is.null(rec)) {
    status <- "none" # e.g. a single record: nothing to describe
  }
  records <- rec$records
  if (is.null(records) && file.exists(file.path(dir, "single_1.json"))) {
    records <- 1L # a single record carries no meta$count
  }
  list(
    name = paste(parts, collapse = "/"),
    records = records,
    credits = rec$credits,
    cost = rec$cost_usd,
    status = status,
    oql = oql
  )
}

# "1 record", "366 records", "- records" (unknown)
.oql_n_records <- function(n) {
  if (is.null(n)) {
    return("- records")
  }
  paste(format(n, big.mark = ","), if (identical(as.numeric(n), 1)) "record" else "records")
}

.oql_status_label <- function(status) {
  c(
    exact = "Exact", inexact = "Not exact", unchecked = "Not checked",
    none = "No OQL (single record)", missing = "Not downloaded"
  )[[status]]
}

.oql_summary_totals <- function(rows) {
  num <- function(x) sum(vapply(rows, function(r) as.numeric(r[[x]] %||% 0), 0))
  list(
    n = length(rows),
    records = num("records"),
    credits = num("credits"),
    cost = num("cost"),
    exact = sum(vapply(rows, function(r) r$status == "exact", TRUE)),
    with_oql = sum(vapply(rows, function(r) r$status %in% c("exact", "inexact", "unchecked"), TRUE))
  )
}

.oql_summary_text <- function(rows, info) {
  t <- .oql_summary_totals(rows)
  head <- c(
    "# OpenAlex queries (OQL)",
    paste0(
      "# ", t$n, " queries | ", format(t$records, big.mark = ","), " records",
      " | exact: ", t$exact, " of ", t$with_oql,
      " | ", t$credits, " credits ($", formatC(t$cost, format = "f", digits = 4), ")",
      " | downloaded ", info$date, " (UTC) | openalexPro ", info$version
    ),
    paste(
      "# Exact = the OQL translates back to exactly the query that ran;",
      "otherwise the OQO in each query's _query.json is the exact query."
    )
  )
  body <- unlist(lapply(rows, function(r) {
    c(
      "",
      paste0(
        "## ", r$name, " | ", .oql_n_records(r$records), " | ",
        .oql_status_label(r$status)
      ),
      r$oql
    )
  }))
  c(head, body)
}

.oql_summary_html <- function(rows, info) {
  esc <- function(x) {
    x <- gsub("&", "&amp;", x, fixed = TRUE)
    x <- gsub("<", "&lt;", x, fixed = TRUE)
    gsub(">", "&gt;", x, fixed = TRUE)
  }
  t <- .oql_summary_totals(rows)
  ids <- paste0("q", seq_along(rows))
  badge <- function(status) {
    sprintf('<span class="badge %s">%s</span>', status, esc(.oql_status_label(status)))
  }
  table <- c(
    '<table class="summary"><thead><tr><th>Query</th><th>Records</th><th>OQL</th></tr></thead><tbody>',
    vapply(seq_along(rows), function(i) {
      r <- rows[[i]]
      sprintf(
        '<tr><td><a href="#%s">%s</a></td><td class="n">%s</td><td>%s</td></tr>',
        ids[i], esc(r$name), esc(format(r$records %||% "-", big.mark = ",")), badge(r$status)
      )
    }, ""),
    "</tbody></table>"
  )
  sections <- unlist(lapply(seq_along(rows), function(i) {
    r <- rows[[i]]
    c(
      sprintf('<h2 id="%s">%s %s</h2>', ids[i], esc(r$name), badge(r$status)),
      sprintf('<p class="meta">%s</p>', esc(.oql_n_records(r$records))),
      if (length(r$oql) > 0L) {
        paste0("<pre>", .oql_highlight(paste(r$oql, collapse = "\n")), "</pre>")
      }
    )
  }))
  c(
    "<!doctype html>",
    '<html lang="en"><head><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    "<title>OpenAlex queries (OQL)</title>",
    "<style>", .oql_css(), "</style></head><body>",
    "<h1>OpenAlex queries</h1>",
    sprintf(
      '<p class="meta">%d queries &middot; %s records &middot; %d credits ($%s) &middot; downloaded %s (UTC) &middot; openalexPro %s</p>',
      t$n, esc(format(t$records, big.mark = ",")), as.integer(t$credits),
      formatC(t$cost, format = "f", digits = 4), esc(info$date), esc(info$version)
    ),
    sprintf(
      '<p class="note %s">%s</p>',
      if (t$exact == t$with_oql) "exact" else "inexact",
      esc(paste0(
        "Exact for ", t$exact, " of ", t$with_oql, " queries: the OQL translates ",
        "back to exactly the query that ran. Otherwise the OQO in that ",
        "query's _query.json is the exact query."
      ))
    ),
    table,
    sections,
    "</body></html>"
  )
}
