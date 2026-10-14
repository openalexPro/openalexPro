# oqo.R ----------------------------------------------------------------------
#
# Running a query as an OQO (OpenAlex Query Object) via POST, instead of as a
# GET URL: pro_request(via = "oqo").
#
# OpenAlex compiles every query to an OQO before running it. Translating once
# (free, POST /query) and sending the OQO directly (POST /) has no URL length
# limit, accepts more than 100 values per filter, and records exactly what ran.
#
# Translator quirk (2026-10): numeric view parameters in a translated URL
# (`sample`, `per_page`, `page`) come back as text and fail validation. So the
# paging parameters are removed before translating, and `sample` / `seed` are
# put back into the OQO as a number / string afterwards.

#' Translate a query URL into an OQO
#'
#' @param query_url A URL from [pro_query()]: classic (`/works?filter=...`) or
#'   root OQL / OQO (`/?oql=...`, `/?oqo=...`).
#' @param api_key API key or `NULL`.
#' @return `NULL` for a single record (`/works/W123`, free, stays GET); else a
#'   list with `oqo`, `oql` (canonical one-line OQL), `view` (`select`,
#'   `sort`: sent alongside the OQO) and `root` (the API root to POST to).
#'   Stops with OpenAlex's messages if the query is invalid -- before any
#'   credits are spent.
#' @keywords internal
#' @noRd
.oa_to_oqo <- function(query_url, api_key = NULL) {
  u <- httr2::url_parse(query_url)
  q <- u$query %||% list()
  path <- gsub("^/+|/+$", "", u$path %||% "")
  root <- sub("(^https?://[^/?#]+).*", "\\1", query_url)

  # A single record (`works/W123`) does not translate and costs nothing.
  if (grepl("/", path, fixed = TRUE)) {
    return(NULL)
  }

  view <- Filter(Negate(is.null), list(select = q$select, sort = q$sort))

  body <- if (!nzchar(path)) {
    if (!is.null(q$oqo)) {
      list(oqo = jsonlite::fromJSON(q$oqo, simplifyVector = FALSE))
    } else if (!is.null(q$oql)) {
      list(oql = q$oql)
    } else {
      stop("`query_url` has neither an entity path nor `oql` / `oqo`.", call. = FALSE)
    }
  } else {
    drop <- c("select", "sort", "per_page", "page", "cursor", "api_key", "sample", "seed")
    rest <- q[setdiff(names(q), drop)]
    oxurl <- paste0("/", path)
    if (length(rest) > 0L) {
      oxurl <- paste0(
        oxurl, "?",
        paste(
          paste0(names(rest), "=", vapply(rest, utils::URLencode, "", reserved = TRUE)),
          collapse = "&"
        )
      )
    }
    list(oxurl = oxurl)
  }

  translated <- .oa_translate(root, body, api_key)
  oqo <- translated$oqo
  if (!is.null(q$sample)) oqo$sample <- as.integer(q$sample)
  if (!is.null(q$seed)) oqo$seed <- as.character(q$seed)

  list(oqo = oqo, oql = translated$oql_oneline, view = view, root = root)
}

#' Translate and validate a query with OpenAlex's free `/query` endpoint
#'
#' @param root API root, e.g. `"https://api.openalex.org"`.
#' @param body List with exactly one of `oxurl`, `oql`, `oqo`.
#' @keywords internal
#' @noRd
.oa_translate <- function(root, body, api_key = NULL) {
  req <- httr2::request(root) |>
    httr2::req_url_path_append("query") |>
    httr2::req_method("POST") |>
    httr2::req_body_json(body, auto_unbox = TRUE) |>
    .oa_auth(api_key) |>
    httr2::req_user_agent(paste0("openalexPro/", utils::packageVersion("openalexPro")))
  # A 400 carries the validation messages: inspect it rather than abort.
  resp <- api_call(req, get_html_response = NULL)
  out <- tryCatch(httr2::resp_body_json(resp), error = function(e) NULL)
  errors <- out$validation$errors
  if (is.null(out$oqo) || isFALSE(out$validation$valid) || length(errors) > 0L) {
    msgs <- vapply(
      errors,
      function(e) paste0(e$type %||% "error", ": ", e$message %||% ""),
      character(1)
    )
    if (length(msgs) == 0L) {
      msgs <- paste("HTTP", httr2::resp_status(resp))
    }
    stop(
      "OpenAlex could not translate the query to an OQO:\n",
      paste0("  ", msgs, collapse = "\n"),
      call. = FALSE
    )
  }
  out
}

#' Does an OQO contain a semantic search? (no cursor paging, max 50)
#'
#' @keywords internal
#' @noRd
.oqo_is_semantic <- function(oqo) {
  walk <- function(rows) {
    any(vapply(rows, function(r) {
      if (!is.null(r$filters)) {
        return(walk(r$filters))
      }
      grepl("search\\.semantic$", r$column_id %||% "")
    }, logical(1)))
  }
  length(oqo$filter_rows) > 0L && walk(oqo$filter_rows)
}

#' Stop if a GET URL has more than 100 values in one filter
#'
#' OpenAlex rejects that for GET (HTTP 400 per request); via OQO it accepts
#' more.
#'
#' @param urls Character vector of query URLs.
#' @keywords internal
#' @noRd
.oa_check_value_limit <- function(urls, limit = 100L) {
  for (u in urls) {
    f <- httr2::url_parse(u)$query$filter
    if (is.null(f)) next
    parts <- strsplit(f, ",", fixed = TRUE)[[1]]
    parts <- parts[grepl(":", parts, fixed = TRUE)]
    n <- lengths(strsplit(sub("^[^:]*:", "", parts), "|", fixed = TRUE))
    if (any(n > limit)) {
      i <- which.max(n)
      stop(
        "Filter `", sub(":.*", "", parts[[i]]), "` has ", n[[i]], " values; ",
        "OpenAlex accepts at most ", limit, " per filter in a URL.\n",
        "Use `pro_query(..., chunk_limit = ", limit, ")` or less, ",
        "or `via = \"oqo\"` (which accepts more).",
        call. = FALSE
      )
    }
  }
  invisible(TRUE)
}
