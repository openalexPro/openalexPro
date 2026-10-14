#' Fetch works from OpenAlex
#'
#' All returned values from OpenAlex will be saved as
#' json files in the `output` directory and the return value is the directory of the
#' json files.
#'
#' If query_url is a list, the function is called for each element of the list in parallel
#' using a maximum of `workers` parallel R sessions. The results from the individual URLs
#' in the list are returned in a folder named after the names of the list elements in the
#' `output` folder.
#'
#' When starting the download, a file `00_in.progress` which is deleted upon completion.
#'
#' If one query of a list fails (e.g. HTTP 404 for an ID that does not exist),
#' the other queries still complete. At the end, one error names each failed
#' query with OpenAlex's reason. The failed queries keep their
#' `00_in.progress`, so `resume = TRUE` fetches only them again.
#'
#' Pages are fetched with cursor paging. A `per_page` in the query is kept;
#' `page` and `cursor` are replaced, with a warning. A `sample` is fetched by
#' page number, as OpenAlex ends cursor paging of a sample after the first
#' page; if it spans several pages and has no `seed`, one is chosen and
#' reported. Semantic search (`search.semantic`) is fetched as its single page
#' of at most 50 results.
#'
#' Each query directory also gets a record of the query: `_query.json` (the
#' URL, how it was sent, the query as OpenAlex ran it as OQL and OQO, records,
#' requests, credits, cost, time), and for papers `_query_oql.txt` and a
#' formatted, self-contained `_query_oql.html` with the query in OpenAlex's
#' readable query language (OQL). The OQL is translated back and compared with
#' the query that ran; the files say whether it reproduces it exactly. Single
#' records get only `_query.json`.
#'
#' @param query_url The URL of the API query or a list of URLs returned from `pro_query()`.
#' @param pages The maximum number of pages (of 200 records) downloaded per
#'   query; for a list, the limit applies to each leaf query. 100000 pages
#'   are 20,000,000 records; for more, use the snapshot instead. If `NULL`,
#'   all pages will be downloaded.
#' @param output directory where the JSON files are saved. Required (the
#'   default `NULL` stops with an error) unless `count_only = TRUE`.
#' @param overwrite Logical. If `TRUE`, `output` will be deleted before
#'   downloading. For a list `query_url`, the entire top-level `output`
#'   directory is removed upfront. If `FALSE` (the default) and `output`
#'   already exists, the function stops with an error.
#' @param api_key Character string API key or `NULL`. Defaults to
#'   `pro_api_key()`. If `NULL` or `""`, requests are sent
#'   without an API key (subject to OpenAlex's unauthenticated limits).
#' @param workers Number of parallel workers to use if `query_url` is a list. Defaults to 1.
#' @param verbose Logical indicating whether to show verbose messages.
#' @param progress Logical indicating whether to show a progress bar. Default `TRUE`.
#' @param count_only return count only as a data.frame.
#' @param resume Logical.  When `TRUE`, keep an existing `output` and refetch
#'   only the leaf queries that did not complete.  Completion is detected with
#'   the `00_in.progress` sentinel each leaf directory carries while it is
#'   being written.  A single URL is treated as one leaf.  Default `FALSE`.
#' @param error_log location of error log of API calls. (default: `NULL` (none)).
#' @param via How each query is sent. `"url"` (default): as a GET request with
#'   the query in the URL, as built by [pro_query()]. `"oqo"`: translated once
#'   (free) into an OpenAlex Query Object and sent via POST, with the same
#'   results. It has no URL length limit, accepts more than 100 values per
#'   filter (so `pro_query(..., chunk_limit = 200)` fetches a DOI or ID list
#'   in about one page per chunk), checks the query before any credits are spent, and records the
#'   exact query in `_query.json`. Single records (`works/W123`) are always
#'   fetched via GET.
#'
#' @return If `count_only` is `FALSE` (the default) the complete path to the expanded and
#'   normalized `output`. If `count_only` is `TRUE`, a data.frame with metadata about
#'   the query (count, db_response_time_ms, page, per_page, error). When `query_url` is
#'   a list, an additional `query` column identifies each query.
#'
#' @md
#'
#' @importFrom utils tail packageVersion
#' @importFrom httr2 req_url_query req_perform resp_body_json resp_body_string
#' @importFrom future plan multisession sequential
#' @importFrom future.apply future_lapply
#' @importFrom cli cli_progress_bar cli_progress_update cli_progress_done cli_alert_info
#' @importFrom progressr with_progress progressor handlers
#'
#' @export
pro_request <- function(
  query_url,
  pages = 100000,
  output = NULL,
  overwrite = FALSE,
  api_key = pro_api_key(),
  workers = 1,
  verbose = FALSE,
  progress = TRUE,
  count_only = FALSE,
  error_log = NULL,
  resume = FALSE,
  via = c("url", "oqo")
) {
  via <- match.arg(via)
  if (
    is.null(api_key) ||
      (is.character(api_key) && length(api_key) == 1 && !nzchar(api_key))
  ) {
    api_key <- NULL
  } else if (!is.character(api_key) || length(api_key) != 1) {
    stop(
      "`api_key` must be NULL or a length-1 character string.",
      call. = FALSE
    )
  }

  if (!is.null(error_log)) {
    message("error log file: ", error_log)
  }

  # A URL may carry at most 100 values per filter (OpenAlex answers HTTP 400
  # otherwise); an OQO sent via POST may carry more.
  if (via == "url") {
    .oa_check_value_limit(unlist(query_url, use.names = FALSE))
  }

  # ---------------------------------------------------------------------------
  # LIST METHOD: multiple queries -> futures with total-items progress
  # ---------------------------------------------------------------------------
  if (is.list(query_url)) {
    old_plan <- future::plan()
    on.exit(future::plan(old_plan), add = TRUE)

    if (workers > 1) {
      future::plan(future::multisession, workers = workers)
    } else {
      future::plan(future::sequential)
    }

    # Delete output directory upfront if overwrite requested
    if (!is.null(output) && dir.exists(output) && !isTRUE(resume)) {
      if (!overwrite) {
        stop(
          "Directory ",
          output,
          " exists.\n",
          "Either specify `overwrite = TRUE` or delete it."
        )
      }
      unlink(output, recursive = TRUE)
    }

    # Flatten nested list to leaf (URL, path) pairs
    leaf_queries <- collect_leaf_queries(query_url)
    leaf_urls <- vapply(leaf_queries, `[[`, character(1), "url")
    leaf_paths <- lapply(leaf_queries, `[[`, "path")

    # Handle count_only case
    if (count_only) {
      result <- future.apply::future_lapply(
        seq_along(leaf_queries),
        function(i) {
          pro_count(
            query_url = leaf_urls[[i]],
            api_key = api_key,
            via = via
          )
        },
        future.seed = TRUE
      )

      out <- do.call(rbind, result)
      out$query <- vapply(leaf_paths, paste, character(1), collapse = "/")

      return(out)
    }

    # Progress counts leaves; each leaf advances it by 1 in fractions per page,
    # once its first page has told it how many pages there are. This avoids a
    # count request per leaf up front, which doubled the requests (and cost)
    # for chunked DOI / ID lists.
    if (progress) {
      cli::cli_alert_info("Downloading {length(leaf_queries)} queries")
      progressr::handlers("cli")
    }

    # Run parallel downloads with progress
    # Note: auto_finish = FALSE prevents warnings when actual pages differ from estimate
    progressr::with_progress(
      {
        p <- if (progress) {
          progressr::progressor(steps = length(leaf_queries), auto_finish = FALSE)
        } else {
          NULL
        }

        # future.scheduling = Inf: one future per leaf, so workers pick up the
        # next leaf when free. The default pre-splits the leaves into one block
        # per worker, which leaves workers idle when leaf sizes differ a lot.
        result <- future.apply::future_lapply(
          seq_along(leaf_queries),
          future.scheduling = Inf,
          function(i) {
            path_parts <- leaf_paths[[i]]
            query_output <- if (is.null(output)) {
              NULL
            } else {
              do.call(file.path, c(list(output), as.list(path_parts)))
            }

            # Resume at leaf granularity. `00_in.progress` is created
            # when a leaf starts and unlinked when it completes, so its
            # absence from an existing directory means that leaf finished --
            # including the legitimate case of an empty result set. A leaf
            # that still carries the sentinel was interrupted: cursor paging
            # cannot be resumed mid-stream (the cursor token is not
            # persisted), so it is refetched whole.
            if (isTRUE(resume) && !is.null(query_output) &&
                dir.exists(query_output) &&
                !file.exists(file.path(query_output, "00_in.progress"))) {
              if (!is.null(p)) p(amount = 1)
              return(invisible(NULL))
            }

            # A failing query (e.g. HTTP 404 for an ID that does not exist)
            # must not stop the others: return its error message and report
            # all failures at the end. Its `00_in.progress` stays, so
            # `resume = TRUE` fetches it again.
            tryCatch(
              {
                fetch_query_pages(
                  query_url = leaf_urls[[i]],
                  pages = pages,
                  output = query_output,
                  overwrite = isTRUE(resume),
                  api_key = api_key,
                  verbose = verbose,
                  error_log = error_log,
                  progressor = p,
                  via = via
                ) |>
                  attr("cost")
              },
              # api_call() wraps the HTTP error; its parent carries the status
              # and OpenAlex's message without the wrapper's call trace.
              error = function(e) conditionMessage(e$parent %||% e)
            )
          },
          future.seed = TRUE
        )
      },
      enable = progress
    )

    # Per leaf: the cost (success), NULL (skipped by resume) or the error
    # message (failure)
    failed <- which(vapply(result, is.character, logical(1)))
    if (progress || verbose) {
      .pr_report_cost(result[!vapply(result, is.character, logical(1))])
    }
    if (length(failed) > 0L) {
      .pr_report_failures(failed, result, leaf_paths, output)
    }

    return(output)
  }

  # ---------------------------------------------------------------------------
  # SCALAR METHOD: single query
  # ---------------------------------------------------------------------------
  if (count_only) {
    out <- pro_count(
      query_url = query_url,
      api_key = api_key,
      via = via
    )
    return(out)
  }

  # Resume: same sentinel logic as for a leaf in the list method above.
  if (isTRUE(resume) && !is.null(output) && dir.exists(output) &&
      !file.exists(file.path(output, "00_in.progress"))) {
    return(normalizePath(output))
  }

  # Use helper function with cli progress for single query
  res <- fetch_query_pages(
    query_url = query_url,
    pages = pages,
    output = output,
    overwrite = overwrite || isTRUE(resume),
    api_key = api_key,
    verbose = verbose,
    error_log = error_log,
    progressor = NULL,
    use_cli_progress = progress,
    via = via
  )
  if (progress || verbose) {
    .pr_report_cost(list(attr(res, "cost")))
  }
  as.vector(res) # the output path, as before (without the cost attribute)
}


#' Fetch pages for a single query (internal helper)
#'
#' @param query_url Single query URL
#' @param pages Max pages to download
#' @param output Output directory
#' @param overwrite Whether to overwrite existing output
#' @param api_key API key
#' @param verbose Show verbose messages
#' @param error_log Error log file path
#' @param progressor Optional progressr progressor for parallel progress
#' @param use_cli_progress Use cli progress bar (for sequential/scalar use)
#'
#' @return Output directory path
#' @keywords internal
#' @noRd
fetch_query_pages <- function(
  query_url,
  pages,
  output,
  overwrite,
  api_key,
  verbose,
  error_log,
  progressor = NULL,
  use_cli_progress = FALSE,
  via = "url"
) {
  # Argument Checks -----------------------------------------------------------
  if (is.null(output)) {
    stop("No `output` specified!")
  }

  if (dir.exists(output)) {
    if (!overwrite) {
      stop(
        "Directory ",
        output,
        " exists.\n",
        "Either specify `overwrite = TRUE` or delete it."
      )
    }
    if (verbose) {
      message(
        "Deleting and recreating `",
        output,
        "` to avoid inconsistencies."
      )
    }
    unlink(output, recursive = TRUE)
  }

  # Preparations --------------------------------------------------------------
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  progress_file <- file.path(output, "00_in.progress")
  file.create(progress_file)
  success <- FALSE

  # Cost of this query, summed from the response headers of every page
  started <- Sys.time()
  cost <- c(requests = 0, credits = 0, usd = 0)
  add_cost <- function(resp) {
    num <- function(h) {
      x <- suppressWarnings(as.numeric(httr2::resp_header(resp, h, "0")))
      if (is.na(x)) 0 else x
    }
    cost <<- cost + c(1, num("x-ratelimit-credits-used"), num("x-ratelimit-cost-usd"))
  }
  on.exit(
    {
      if (isTRUE(success)) {
        unlink(progress_file)
      }
    },
    add = TRUE
  )

  output <- normalizePath(output)

  # Base request with query and custom user agent. A `per_page` in the query
  # is kept; `page` / `cursor` are replaced by our own paging (OpenAlex
  # rejects `page` together with `cursor`). Three paging modes:
  # - semantic search rejects cursor paging and returns at most 50 results:
  #   a single page;
  # - a `sample` ends cursor paging after the first page, so it is paged by
  #   page number (up to OpenAlex's maximum sample of 10,000), which needs a
  #   `seed` once it spans several pages;
  # - everything else uses cursor paging.
  #
  # With via = "oqo" the query is translated once to an OQO and every page is
  # a POST with the OQO in the body; the paging works the same way. A single
  # record (`works/W123`) is never translated.
  user_q <- httr2::url_parse(query_url)$query
  oq <- if (identical(via, "oqo")) .oa_to_oqo(query_url, api_key) else NULL
  if (is.null(oq)) {
    semantic <- "search.semantic" %in% names(user_q)
    sample_n <- user_q$sample
    seed <- user_q$seed
  } else {
    semantic <- .oqo_is_semantic(oq$oqo)
    sample_n <- oq$oqo$sample
    seed <- oq$oqo$seed
  }
  sampled <- !semantic && !is.null(sample_n)
  per_page <- as.integer(user_q$per_page %||% if (semantic) 50L else 200L)
  replaced <- intersect(c("page", "cursor"), names(user_q))
  if (!semantic && length(replaced) > 0L) {
    warning(
      "`", paste(replaced, collapse = "`, `"), "` in the query ",
      "is replaced: `pro_request()` does the paging.",
      call. = FALSE
    )
  }
  paging <- if (semantic) {
    list(per_page = per_page)
  } else if (sampled) {
    list(per_page = per_page, page = 1L, cursor = NULL)
  } else {
    list(per_page = per_page, page = NULL, cursor = "*")
  }
  if (sampled && is.null(seed) && isTRUE(as.numeric(sample_n) > per_page)) {
    # Without a seed, OpenAlex rejects page 2 of a sample. Not drawn from R's
    # RNG, so the caller's random state is left alone.
    seed <- as.integer((as.numeric(Sys.time()) * 1000) %% .Machine$integer.max)
    message(
      "`sample` spans several pages, which needs a `seed`: using seed = ",
      seed, ". Add it to the query to reproduce this sample."
    )
    if (is.null(oq)) paging$seed <- seed else oq$oqo$seed <- as.character(seed)
  }

  # One request per page, built from the current paging state
  make_req <- function(paging) {
    req <- if (is.null(oq)) {
      do.call(httr2::req_url_query, c(list(httr2::request(query_url)), paging))
    } else {
      body <- c(
        list(oqo = oq$oqo),
        oq$view,
        Filter(Negate(is.null), paging[setdiff(names(paging), "seed")])
      )
      httr2::request(oq$root) |>
        httr2::req_method("POST") |>
        httr2::req_body_json(body, auto_unbox = TRUE)
    }
    req |>
      .oa_auth(api_key) |>
      httr2::req_user_agent(
        paste0("openalexPro/", packageVersion("openalexPro"))
      )
  }
  req <- make_req(paging)
  if (verbose && !is.null(oq)) {
    message("Query (OQL): ", oq$oql)
  }

  # Initialize page counter
  page <- 1L

  # First request to inspect meta
  resp <- api_call(
    req,
    error_log = error_log
  )
  add_cost(resp)

  data <- resp |>
    httr2::resp_body_json()
  # OpenAlex echoes the query it ran (OQL, OQO, URL) and the result size
  x_query <- data$meta$x_query
  records <- data$meta$count

  # Decided from the response, not the URL: with OQL / OQO the grouping is
  # inside the query. Grouped responses carry a numeric `meta$groups_count`,
  # list responses `null`.
  single_record <- is.null(data$meta)
  page_prefix <- if (single_record) {
    "single_"
  } else if (!is.null(data$meta$groups_count)) {
    "group_by_page_"
  } else {
    "results_page_"
  }

  # SINGLE-RECORD CASE --------------------------------------------------------
  if (single_record) {
    resp |>
      httr2::resp_body_string() |>
      writeLines(
        con = file.path(
          output,
          paste0(page_prefix, "1.json")
        )
      )
    if (!is.null(progressor)) {
      progressor(amount = 1)
    }
    .pr_write_query_record(output, query_url, if (is.null(oq)) "url" else "oqo",
                           oq %||% x_query, records, cost, started)
    .pr_write_query_text_for(output, oq, x_query, query_url, api_key, records)
    success <- TRUE
    return(structure(output, cost = cost))
  }

  # Calculate max_pages for cli progress bar
  max_pages <- NA_integer_
  if (!is.null(data$meta$count) && !is.null(data$meta$per_page)) {
    max_pages <- ceiling(data$meta$count / data$meta$per_page)
    if (!is.null(pages)) {
      max_pages <- min(max_pages, pages)
    }
  }

  # Share of the parallel progressor (one unit per leaf) for each page
  page_share <- if (is.na(max_pages) || max_pages < 1) 1 else 1 / max_pages
  share_done <- 0
  tick <- function() {
    amount <- min(page_share, 1 - share_done)
    share_done <<- share_done + amount
    progressor(amount = amount)
  }

  # Start cli progress bar if requested (scalar mode only)
  show_cli_progress <- use_cli_progress && !is.na(max_pages)
  cli_progress_count <- 0L
  if (show_cli_progress) {
    cli::cli_progress_bar(
      total = max_pages,
      format = "Downloading {cli::pb_bar} {cli::pb_current}/{cli::pb_total} [{cli::pb_elapsed}]",
      clear = FALSE
    )
  }

  # PAGINATED CASE ------------------------------------------------------------
  # Save the first page (already fetched above for meta inspection)
  resp |>
    httr2::resp_body_string() |>
    writeLines(
      con = file.path(
        output,
        paste0(page_prefix, page, ".json")
      )
    )

  # Update progress for first page
  if (!is.null(progressor)) {
    tick()
  } else if (show_cli_progress && cli_progress_count < max_pages) {
    cli_progress_count <- cli_progress_count + 1L
    cli::cli_progress_update(force = TRUE)
  }

  # Continue with remaining pages if needed. For a sample, meta$count is the
  # sample size.
  sample_pages <- if (sampled) ceiling(data$meta$count / per_page) else NA
  while (if (sampled) page < sample_pages else !is.null(data$meta$next_cursor)) {
    page <- page + 1L

    if (!is.null(pages) && page > pages) {
      break
    }

    if (sampled) {
      paging$page <- page
    } else {
      paging$cursor <- data$meta$next_cursor
    }
    req <- make_req(paging)

    if (verbose) {
      message("Downloading page ", page)
      if (is.null(oq)) {
        message("URL: ", sub("api_key=[^&]*", "api_key=<redacted>", req$url))
      }
    }

    resp <- api_call(
      req,
      error_log = error_log
    )
    add_cost(resp)

    data <- httr2::resp_body_json(resp)

    # grouping returns at the moment a last page with no groups - this must
    # not be saved!
    if (isTRUE(data$meta$groups_count == 0)) {
      break
    }

    resp |>
      httr2::resp_body_string() |>
      writeLines(
        con = file.path(
          output,
          paste0(page_prefix, page, ".json")
        )
      )

    # Update progress (only if we haven't reached the total yet)
    if (!is.null(progressor)) {
      tick()
    } else if (show_cli_progress && cli_progress_count < max_pages) {
      cli_progress_count <- cli_progress_count + 1L
      cli::cli_progress_update()
    }
  }

  # Fewer pages than estimated: complete this leaf's share
  if (!is.null(progressor) && share_done < 1) {
    progressor(amount = 1 - share_done)
  }

  # Only call done if progress bar wasn't auto-closed by reaching total
  if (show_cli_progress && cli_progress_count < max_pages) {
    cli::cli_progress_done()
  }

  .pr_write_query_record(output, query_url, if (is.null(oq)) "url" else "oqo",
                         oq %||% x_query, records, cost, started)
  .pr_write_query_text_for(output, oq, x_query, query_url, api_key, records)
  success <- TRUE

  structure(output, cost = cost)
}


#' Write `_query.json`: what was asked, how, and what it cost
#'
#' The leading underscore keeps it out of the page discovery and out of
#' arrow's `open_dataset()`.
#'
#' @keywords internal
#' @noRd
.pr_write_query_record <- function(output, query_url, via, x_query, records,
                                   cost, started) {
  record <- list(
    query_url = sub("([?&])api_key=[^&]*&?", "\\1", query_url),
    via = via,
    oql = x_query$oql,
    oqo = x_query$oqo,
    records = records,
    requests = unname(cost[["requests"]]),
    credits = unname(cost[["credits"]]),
    cost_usd = unname(cost[["usd"]]),
    started = format(started, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    finished = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    openalexPro = as.character(utils::packageVersion("openalexPro"))
  )
  jsonlite::write_json(
    record, file.path(output, "_query.json"),
    auto_unbox = TRUE, pretty = TRUE, null = "null", digits = NA
  )
}


#' Write the readable OQL files for a finished query
#'
#' The OQO that ran: the translated one (`via = "oqo"`), or the one OpenAlex
#' echoes in `meta$x_query` (`via = "url"`). A single record has neither.
#' @keywords internal
#' @noRd
.pr_write_query_text_for <- function(output, oq, x_query, query_url, api_key,
                                     records) {
  .pr_write_query_text(
    output,
    oqo = oq$oqo %||% x_query$oqo,
    oql_fallback = oq$oql %||% x_query$oql,
    root = oq$root %||% sub("(^https?://[^/?#]+).*", "\\1", query_url),
    api_key = api_key,
    records = records,
    query_url = sub("([?&])api_key=[^&]*&?", "\\1", query_url)
  )
}


#' Report the summed cost of the downloaded queries
#'
#' @param costs List of named numeric vectors (requests, credits, usd).
#' @keywords internal
#' @noRd
.pr_report_cost <- function(costs) {
  costs <- Filter(Negate(is.null), costs)
  if (length(costs) == 0L) {
    return(invisible(NULL))
  }
  total <- Reduce(`+`, costs)
  cli::cli_alert_info(paste0(
    "{total[['requests']]} request{?s}, {total[['credits']]} credit{?s} ",
    "(${formatC(total[['usd']], format = 'f', digits = 4)})"
  ))
  invisible(total)
}


#' Flatten a nested query list into (path, url) leaf pairs
#'
#' @param x A character URL or a (possibly nested) named list of URLs.
#' @param path_parts Character vector of name segments accumulated so far.
#' @return A flat list of `list(path = character, url = character)` entries.
#' @keywords internal
#' @noRd
collect_leaf_queries <- function(x, path_parts = character(0)) {
  if (is.character(x)) {
    return(list(list(path = path_parts, url = x)))
  }
  nms <- names(x)
  if (is.null(nms)) {
    nms <- paste0("query_", seq_along(x))
  } else {
    unnamed <- !nzchar(nms)
    nms[unnamed] <- paste0("query_", which(unnamed))
  }
  result <- list()
  for (i in seq_along(x)) {
    result <- c(result, collect_leaf_queries(x[[i]], c(path_parts, nms[i])))
  }
  result
}


#' Stop with a summary of the leaf queries that failed
#'
#' @keywords internal
#' @noRd
.pr_report_failures <- function(failed, result, leaf_paths, output) {
  shown <- utils::head(failed, 10L)
  reasons <- vapply(
    result[shown],
    function(m) substr(gsub("\\s*\n\\s*", " ", m), 1L, 200L),
    character(1)
  )
  queries <- vapply(leaf_paths[shown], paste, character(1), collapse = "/")
  stop(
    length(failed), " of ", length(result), " queries failed (",
    length(result) - length(failed), " completed).\n",
    paste0("  ", queries, ": ", reasons, collapse = "\n"),
    if (length(failed) > length(shown)) {
      paste0("\n  ... and ", length(failed) - length(shown), " more")
    },
    "\nOutput: ", output,
    "\nRe-run with `resume = TRUE` to fetch only the failed and unfinished queries.",
    call. = FALSE
  )
}
