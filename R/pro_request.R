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
#' @param query_url The URL of the API query or a list of URLs returned from `pro_query()`.
#' @param pages The number of pages to be downloaded. The default is set to
#'   10000, which would be 2,000,000 works. It is recommended to not increase it
#'   beyond 100000 due to server load and to use the snapshot instead. If `NULL`,
#'   all pages will be downloaded. Default: 100000.
#' @param output directory where the JSON files are saved. Default is a
#'   temporary directory. Needs to be specified.
#' @param overwrite Logical. If `TRUE`, `output` will be deleted before
#'   downloading. For a list `query_url`, the entire top-level `output`
#'   directory is removed upfront. If `FALSE` (the default) and `output`
#'   already exists, the function stops with an error.
#' @param api_key Character string API key or `NULL`. Defaults to
#'   `Sys.getenv("openalexPro.apikey")`. If `NULL` or `""`, requests are sent
#'   without an API key (subject to OpenAlex's unauthenticated limits).
#' @param workers Number of parallel workers to use if `query_url` is a list. Defaults to 1.
#' @param verbose Logical indicating whether to show verbose messages.
#' @param progress Logical indicating whether to show a progress bar. Default `TRUE`.
#' @param count_only return count only as a data.frame.
#' @param error_log location of error log of API calls. (default: `NULL` (none)).
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
  api_key = Sys.getenv("openalexPro.apikey"),
  workers = 1,
  verbose = FALSE,
  progress = TRUE,
  count_only = FALSE,
  error_log = NULL
) {
  if (is.null(api_key) || (is.character(api_key) && length(api_key) == 1 && !nzchar(api_key))) {
    api_key <- NULL
  } else if (!is.character(api_key) || length(api_key) != 1) {
    stop("`api_key` must be NULL or a length-1 character string.", call. = FALSE)
  }

  if (!is.null(error_log)) {
    message("error log file: ", error_log)
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
    if (!is.null(output) && dir.exists(output)) {
      if (!overwrite) {
        stop(
          "Directory ", output, " exists.\n",
          "Either specify `overwrite = TRUE` or delete it."
        )
      }
      unlink(output, recursive = TRUE)
    }

    # Flatten nested list to leaf (URL, path) pairs
    leaf_queries <- collect_leaf_queries(query_url)
    leaf_urls    <- vapply(leaf_queries, `[[`, character(1), "url")
    leaf_paths   <- lapply(leaf_queries, `[[`, "path")

    # Handle count_only case
    if (count_only) {
      result <- future.apply::future_lapply(
        seq_along(leaf_queries),
        function(i) {
          pro_count(
            query_url = leaf_urls[[i]],
            api_key = api_key
          )
        },
        future.seed = TRUE
      )

      out <- do.call(rbind, result)
      out$query <- vapply(leaf_paths, paste, character(1), collapse = "/")

      return(out)
    }

    # Calculate total pages for progress bar
    if (progress) {
      cli::cli_alert_info("Fetching query counts...")
      counts <- vapply(
        leaf_urls,
        function(url) {
          pro_count(url, api_key = api_key)$count
        },
        numeric(1)
      )

      per_page <- 200
      max_pages_per_query <- if (is.null(pages)) Inf else pages
      pages_per_query <- pmin(ceiling(counts / per_page), max_pages_per_query)
      total_pages <- sum(pages_per_query)
      cli::cli_alert_info("Total pages to download: {total_pages}")

      progressr::handlers("cli")
    } else {
      total_pages <- 1 # Dummy value when progress is disabled
    }

    # Run parallel downloads with progress
    # Note: auto_finish = FALSE prevents warnings when actual pages differ from estimate
    progressr::with_progress(
      {
        p <- if (progress) {
          progressr::progressor(steps = total_pages, auto_finish = FALSE)
        } else {
          NULL
        }

        result <- future.apply::future_lapply(
          seq_along(leaf_queries),
          function(i) {
            path_parts <- leaf_paths[[i]]
            query_output <- if (is.null(output)) {
              NULL
            } else {
              do.call(file.path, c(list(output), as.list(path_parts)))
            }

            fetch_query_pages(
              query_url = leaf_urls[[i]],
              pages = pages,
              output = query_output,
              overwrite = FALSE,
              api_key = api_key,
              verbose = verbose,
              error_log = error_log,
              progressor = p
            )
          },
          future.seed = TRUE
        )
      },
      enable = progress
    )

    return(output)
  }

  # ---------------------------------------------------------------------------
  # SCALAR METHOD: single query
  # ---------------------------------------------------------------------------
  if (count_only) {
    out <- pro_count(
      query_url = query_url,
      api_key = api_key
    )
    return(out)
  }

  # Use helper function with cli progress for single query
  fetch_query_pages(
    query_url = query_url,
    pages = pages,
    output = output,
    overwrite = overwrite,
    api_key = api_key,
    verbose = verbose,
    error_log = error_log,
    progressor = NULL,
    use_cli_progress = progress
  )
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
  use_cli_progress = FALSE
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
  on.exit(
    {
      if (isTRUE(success)) {
        unlink(progress_file)
      }
    },
    add = TRUE
  )

  output <- normalizePath(output)

  if (grepl("group_by=", query_url, fixed = TRUE)) {
    page_prefix <- "group_by_page_"
  } else {
    page_prefix <- "results_page_"
  }

  # Base request with query and custom user agent
  query <- list(
    per_page = 200,
    cursor = "*"
  )
  if (!is.null(api_key)) {
    query$api_key <- api_key
  }

  req <- httr2::request(query_url)
  req <- do.call(httr2::req_url_query, c(list(req), query)) |>
    httr2::req_user_agent(
      paste0("openalexPro/", packageVersion("openalexPro"))
    )

  # Initialize page counter
  page <- 1L

  # First request to inspect meta
  resp <- api_call(
    req,
    error_log = error_log
  )

  data <- resp |>
    httr2::resp_body_json()

  single_record <- is.null(data$meta)
  if (single_record) {
    page_prefix <- "single_"
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
      progressor()
    }
    success <- TRUE
    return(output)
  }

  # Calculate max_pages for cli progress bar
  max_pages <- NA_integer_
  if (!is.null(data$meta$count) && !is.null(data$meta$per_page)) {
    max_pages <- ceiling(data$meta$count / data$meta$per_page)
    if (!is.null(pages)) {
      max_pages <- min(max_pages, pages)
    }
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
    progressor()
  } else if (show_cli_progress && cli_progress_count < max_pages) {
    cli_progress_count <- cli_progress_count + 1L
    cli::cli_progress_update(force = TRUE)
  }

  # Continue with remaining pages if needed
  while (!is.null(data$meta$next_cursor)) {
    page <- page + 1L

    if (!is.null(pages) && page > pages) {
      break
    }

    req <- req |>
      httr2::req_url_query(cursor = data$meta$next_cursor)

    if (verbose) {
      message("Downloading page ", page)
      message("URL: ", req$url)
    }

    resp <- api_call(
      req,
      error_log = error_log
    )

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
      progressor()
    } else if (show_cli_progress && cli_progress_count < max_pages) {
      cli_progress_count <- cli_progress_count + 1L
      cli::cli_progress_update()
    }
  }

  # Only call done if progress bar wasn't auto-closed by reaching total
  if (show_cli_progress && cli_progress_count < max_pages) {
    cli::cli_progress_done()
  }

  success <- TRUE

  output
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
