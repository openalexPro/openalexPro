# helpers -----------------------------------------------------------------

#' @keywords internal
#' @noRd
.is_empty <- function(x) {
  is.null(x) || !length(x)
}

#' @keywords internal
#' @noRd
.oa_collapse <- function(x) {
  if (is.null(x)) {
    return(character(0))
  }
  x <- x[!is.na(x)]
  if (!length(x)) {
    return(character(0))
  }
  if (is.logical(x)) {
    x <- tolower(as.character(x))
  }
  if (length(x) == 1) as.character(x) else paste(x, collapse = "|")
}

#' @keywords internal
#' @noRd
.oa_build_filter <- function(fl) {
  if (.is_empty(fl)) {
    return(NULL)
  }

  # drop empty/all-NA entries
  fl <- Filter(function(v) !(length(v) == 0 || all(is.na(v))), fl)
  if (.is_empty(fl)) {
    return(NULL)
  }

  parts <- unlist(
    Map(
      function(k, v) {
        vv <- .oa_collapse(v)
        if (.is_empty(vv)) {
          return(character(0))
        }
        paste0(k, ":", vv)
      },
      names(fl),
      fl
    ),
    use.names = FALSE
  )

  if (length(parts)) paste(parts, collapse = ",") else NULL
}

# validation --------------------------------------------------------------

#' @keywords internal
#' @noRd
.fuzzy_suggest <- function(bad, allowed, max_dist = 3L) {
  if (.is_empty(allowed) || .is_empty(bad)) {
    return(rep(NA_character_, length(bad)))
  }
  vapply(
    bad,
    function(x) {
      d <- utils::adist(x, allowed)
      m <- which.min(d)
      if (length(m) && is.finite(d[m]) && d[m] <= max_dist) {
        allowed[m]
      } else {
        NA_character_
      }
    },
    character(1L)
  )
}

#' @keywords internal
#' @noRd
.build_validation_error <- function(bad, allowed, field_type, helper_fn_name) {
  sug <- .fuzzy_suggest(bad, allowed)
  have <- !is.na(sug)
  paste0(
    "Invalid ",
    field_type,
    ": ",
    paste(bad, collapse = ", "),
    ".",
    if (any(have)) {
      paste0(
        "\nDid you mean: ",
        paste(paste0(bad[have], " \u2192 ", sug[have]), collapse = ", "),
        "?"
      )
    } else {
      ""
    },
    "\nValid ",
    field_type,
    " are defined in `",
    helper_fn_name,
    "`."
  )
}

#' @keywords internal
#' @noRd
.validate_select <- function(select, entity = "works") {
  # Check `select` first: fetching the allowed fields costs a request.
  if (.is_empty(select)) {
    return(invisible(TRUE))
  }
  allowed <- opt_select_fields(entity = entity)
  if (.is_empty(allowed)) {
    return(invisible(TRUE))
  }

  bad <- setdiff(select, allowed)
  if (.is_empty(bad)) {
    return(invisible(TRUE))
  }

  msg <- .build_validation_error(
    bad,
    allowed,
    "select field(s)",
    sprintf('opt_select_fields(entity = "%s")', entity)
  )
  stop(msg, call. = FALSE)
}

#' @keywords internal
#' @noRd
.validate_filter <- function(fl, entity = "works") {
  if (.is_empty(fl)) {
    return(invisible(TRUE))
  }

  # Warn about deprecated .search filter fields
  search_filters <- grep("\\.search(\\.no_stem)?$", names(fl), value = TRUE)
  if (length(search_filters)) {
    cli::cli_warn(c(
      "!" = paste0(
        "The filter argument{?s} {.val {search_filters}} use{?s/} the ",
        "deprecated {.code field.search} syntax."
      ),
      "i" = paste0(
        "Use the {.arg search} parameter instead: ",
        "{.code pro_query(..., search = \"your terms\")}."
      ),
      "i" = "See {.url https://help.openalex.org/api/searching/} for details."
    ))
  }

  allowed <- opt_filter_names(entity = entity)
  if (.is_empty(allowed)) {
    return(invisible(TRUE))
  }

  bad <- setdiff(names(fl), allowed)
  if (.is_empty(bad)) {
    return(invisible(TRUE))
  }

  msg <- .build_validation_error(
    bad,
    allowed,
    "filter name(s)",
    sprintf('opt_filter_names(entity = "%s")', entity)
  )
  stop(msg, call. = FALSE)
}

# OQL / OQO ----------------------------------------------------------------

#' Build a root-endpoint URL for an OQL or OQO query
#'
#' @param classic Named logical: which classic arguments the caller supplied.
#' @keywords internal
#' @noRd
.oa_oql_url <- function(oql, oqo, select, options, endpoint, classic) {
  if (!is.null(oql) && !is.null(oqo)) {
    stop("Supply either `oql` or `oqo`, not both.", call. = FALSE)
  }
  if (any(classic)) {
    stop(
      "`", paste(names(classic)[classic], collapse = "`, `"), "` cannot be ",
      "combined with `oql` / `oqo`: express it inside the query.",
      call. = FALSE
    )
  }
  if (!is.null(oql) && !(is.character(oql) && length(oql) == 1L && nzchar(oql))) {
    stop("`oql` must be a single non-empty string.", call. = FALSE)
  }
  if (is.list(oqo)) {
    oqo <- as.character(jsonlite::toJSON(oqo, auto_unbox = TRUE))
  } else if (!is.null(oqo) && !(is.character(oqo) && length(oqo) == 1L)) {
    stop("`oqo` must be a list or a single JSON string.", call. = FALSE)
  }

  q <- c(
    list(
      oql = oql,
      oqo = oqo,
      select = if (!.is_empty(select)) paste(select, collapse = ",")
    ),
    options
  )
  q <- Filter(Negate(is.null), q)
  httr2::req_url_query(httr2::request(endpoint), !!!q)$url
}

# main builder ------------------------------------------------------------

#' Build an OpenAlex request (httr2)
#'
#' Construct an \code{httr2} request for the OpenAlex API. All filters must be
#' supplied as named \code{...} arguments (e.g., \code{from_publication_date = "2020-01-01"}).
#'
#' Filter names are validated against \code{opt_filter_names(entity = entity)}
#' and \code{select} fields against \code{opt_select_fields(entity = entity)},
#' i.e. against the names OpenAlex accepts for the queried entity.
#'
#' If multiple more then 50 `doi` or openalex `id`s are provided, the request
#' is automatically split into chunks of 50 and a named list of URLs is returned.
#'
#' @param entity Character; one of \code{"works"}, \code{"authors"},
#'   \code{"institutions"}, \code{"publishers"}, \code{"funders"},
#'   \code{"sources"}, \code{"topics"}, \code{"locations"}. \code{"venues"}
#'   (now \code{"sources"}) and \code{"concepts"} (now \code{"topics"}) are
#'   deprecated by OpenAlex and kept only for compatibility.
#' @param id Optional ID or vector of IDs (e.g., \code{"W1775749144"}). If a single ID
#'   is provided, fetches one entity directly. If multiple IDs are provided, they are
#'   automatically moved into the \code{ids.openalex} filter.
#' @param doi Optional DOI or vector of DOIs (e.g., \code{"10.1038/s41586-021-03819-2"}).
#'   Values are moved into the \code{doi} filter and automatically chunked into
#'   separate requests when the number of DOIs exceeds \code{chunk_limit}.
#' @param search Optional full-text search string. Applies stemming and
#'   stop-word removal. Supports boolean operators (\code{AND}, \code{OR},
#'   \code{NOT} in uppercase), quoted phrases (\code{"exact phrase"}) and
#'   proximity (\code{"word1 word2"~N}). Wildcards are rejected by the API
#'   (HTTP 400): use \code{search.exact}. Replaces the deprecated
#'   \code{filter = field.search:keyword} syntax.
#' @param search.exact Optional full-text search without stemming or stop-word
#'   removal. Supports the boolean/phrase/proximity syntax of \code{search},
#'   plus wildcards and fuzzy matching. Use when you need to match exact word
#'   forms (e.g. \code{"surgery"} should not match \code{"surgical"}).
#' @param search.semantic Optional semantic (AI-powered) search string. Uses
#'   embeddings to match conceptual meaning rather than exact keywords. Limited
#'   to 1 request per second and returns at most 50 results per query.
#' @param group_by Optional field to group by (facets), e.g. \code{"type"}.
#' @param select Optional character vector of fields to return.
#' @param options Optional named list of additional query parameters (e.g.,
#'   \code{list(sort = "cited_by_count:desc", sample = 100, seed = 42)}).
#'   \code{pro_request()} does the paging, so \code{page} and
#'   \code{cursor} given here are replaced (with a warning); \code{per_page}
#'   is kept (1--200, default 200). A \code{sample} (up to 10,000) is paged by
#'   page number and needs a \code{seed} when it spans several pages;
#'   \code{pro_request()} picks and reports one if none is given.
#' @param endpoint Base API URL. Defaults to \code{"https://api.openalex.org"}.
#' @param   chunk_limit Number of DOIS or ids per chunk if chunked. Default: 50
#' @param oql Optional OQL (OpenAlex Query Language) query string, e.g.
#'   \code{"works where year is (2020) and type is (article)"}. See section
#'   \emph{OQL and OQO}.
#' @param oqo Optional OQO (OpenAlex Query Object): a nested list, or a JSON
#'   string. See section \emph{OQL and OQO}.
#' @param ... Filters as named arguments. Values may be scalars or vectors (vectors
#'   are collapsed with \code{"|"} to express OR).
#'
#' @return An individual URL or a list of URLs.
#'
#' @section Search syntax:
#' All three search parameters (\code{search}, \code{search.exact},
#' \code{search.semantic}) accept a query string. For \code{search} and
#' \code{search.exact}, the following syntax is supported:
#' \itemize{
#'   \item Boolean: \code{biodiversity AND finance}, \code{climate OR weather},
#'     \code{ocean NOT pollution} (operators must be uppercase); group with
#'     parentheses. Words without an operator between them are combined with
#'     \code{AND}.
#'   \item Exact phrase: \code{"biodiversity finance"} (double quotes).
#'   \item Proximity: \code{"biodiversity finance"~5} (words within 5
#'     positions), or two phrases near each other:
#'     \code{"machine learning"~5~"neural network"}.
#' }
#' Only with \code{search.exact} (the stemmed \code{search} rejects wildcards
#' with HTTP 400, and stemming distorts fuzzy terms):
#' \itemize{
#'   \item Wildcard: \code{microbio*} (zero or more characters),
#'     \code{organi?ation} (exactly one). At least 3 characters before the
#'     wildcard; no leading wildcard.
#'   \item Fuzzy: \code{biodiversty~1} (up to N character edits, N = 0--2;
#'     at least 3 characters before the \code{~}).
#' }
#' See \url{https://help.openalex.org/api/searching/}.
#' \code{search.semantic} does not use keyword syntax; pass a natural-language
#' phrase or even a full abstract. It returns at most 50 results per call.
#'
#' @section OQL and OQO:
#' OpenAlex's query language (\code{oql}) and its JSON form (\code{oqo})
#' express queries the classic filter syntax cannot, such as nested
#' \code{and} / \code{or} conditions. The entity, all conditions, grouping
#' (\code{group by}), \code{sample} and \code{corpus} belong inside the query,
#' so \code{entity}, \code{id}, \code{doi}, the search arguments,
#' \code{group_by} and filters in \code{...} cannot be combined with it --
#' OpenAlex would silently ignore them. \code{select} and \code{options}
#' (e.g. \code{sort}) are passed alongside. The URL targets the API root
#' (\code{https://api.openalex.org/?oql=...}) and works with
#' \code{pro_request()}, \code{pro_count()} and \code{pro_fetch()} as usual.
#' An invalid query fails at request time with OpenAlex's parse error.
#' See \url{https://help.openalex.org/api/oql/}.
#'
#' @section Deprecated search filters:
#' Filter arguments with a \code{.search} suffix (e.g.
#' \code{title_and_abstract.search = "biodiversity"}) are deprecated by the
#' OpenAlex API. They still work but emit a warning. Use the \code{search},
#' \code{search.exact}, or \code{search.semantic} parameters instead. See
#' \url{https://help.openalex.org/api/searching/} for details.
#'
#' @examples
#' \dontrun{
#'
#' url <- pro_query(
#'   entity = "works",
#'   search = "biodiversity",
#'   from_publication_date = "2020-01-01",
#'   language = c("en","de"),
#'   select = c("id","title","publication_year"),
#'   options = list(per_page = 5)
#' )
#'
#' # OQL: nested conditions the filter syntax cannot express
#' url <- pro_query(
#'   oql = "works where year >= (2020) and (title has (coral) or title has (reef))"
#' )
#'
#' # OQO: the same kind of query as a nested list
#' url <- pro_query(oqo = list(
#'   get_rows = "works",
#'   filter_rows = list(list(column_id = "publication_year", value = 2020))
#' ))
#' }
#'
#' @export
#' @importFrom httr2 request req_url_path_append req_url_query req_headers
#' @importFrom utils adist
pro_query <- function(
  entity = c(
    "works",
    "authors",
    "venues",
    "institutions",
    "concepts",
    "publishers",
    "funders",
    "sources",
    "topics",
    "locations"
  ),
  id = NULL,
  doi = NULL,
  search = NULL,
  search.exact = NULL,
  search.semantic = NULL,
  group_by = NULL,
  select = NULL,
  options = NULL,
  endpoint = "https://api.openalex.org",
  chunk_limit = 50L,
  oql = NULL,
  oqo = NULL,
  ...
) {
  if (!is.null(oql) || !is.null(oqo)) {
    return(.oa_oql_url(
      oql = oql, oqo = oqo, select = select, options = options,
      endpoint = endpoint,
      classic = c(
        entity = !missing(entity), id = !is.null(id), doi = !is.null(doi),
        search = !is.null(search), search.exact = !is.null(search.exact),
        search.semantic = !is.null(search.semantic),
        group_by = !is.null(group_by), filters = ...length() > 0
      )
    ))
  }

  VALID_ENTITIES <- c(
    "works",
    "authors",
    "venues",
    "institutions",
    "concepts",
    "publishers",
    "funders",
    "sources",
    "topics",
    "locations"
  )
  entity <- match.arg(tolower(entity), VALID_ENTITIES)

  # gather filters via ...
  filter <- list(...)

  # move multiple IDs into filter automatically
  if (length(id) > 1) {
    filter <- c(filter, list(`ids.openalex` = unique(id)))
    id <- NULL
  }

  # move DOIs into filter (always via filter; chunked automatically)
  if (!is.null(doi) && length(doi) > 0) {
    filter <- c(filter, list(doi = unique(doi)))
  }

  # validate filters and select fields
  .validate_filter(filter, entity)
  .validate_select(select, entity)

  # prepare chunking ------------------------------------------------------
  # Split filters with large value lists (e.g., DOIs, IDs) into multiple requests
  # to avoid exceeding API limits

  chunk_targets <- c(
    "openalex",
    "ids.openalex",
    "doi",
    "cites",
    "cited_by"
  )

  filter_batches <- list(filter)
  if (length(filter)) {
    for (key in intersect(names(filter), chunk_targets)) {
      new_batches <- list()
      for (current_filter in filter_batches) {
        values <- current_filter[[key]]
        values <- values[!is.na(values)]
        if (length(values) > chunk_limit) {
          splits <- split(
            values,
            ceiling(seq_along(values) / chunk_limit)
          )
          new_batches <- c(
            new_batches,
            lapply(splits, function(chunk) {
              current_filter[[key]] <- chunk
              current_filter
            })
          )
        } else {
          new_batches <- c(new_batches, list(current_filter))
        }
      }
      filter_batches <- new_batches
    }
  }

  if (.is_empty(filter_batches)) {
    filter_batches <- list(filter)
  }

  # build strings
  select_str <- if (!.is_empty(select)) paste(select, collapse = ",") else NULL

  # base request + path
  req_base <- httr2::request(endpoint)
  path <- if (is.null(id)) entity else paste(entity, id, sep = "/")
  req_base <- httr2::req_url_path_append(req_base, path)

  # assemble query components shared across batches (drop NULLs later)
  shared_q <- list(
    search = search,
    `search.exact` = search.exact,
    `search.semantic` = search.semantic,
    group_by = group_by,
    select = select_str
  )
  if (length(options)) {
    shared_q <- c(shared_q, options)
  }

  urls <- vapply(
    filter_batches,
    function(batch_filter) {
      filter_str <- .oa_build_filter(batch_filter)
      q <- c(list(filter = filter_str), shared_q)
      q <- Filter(Negate(is.null), q)
      req <- req_base
      if (length(q)) {
        req <- httr2::req_url_query(req, !!!q)
      }
      req$url
    },
    character(1)
  )

  if (length(urls) > 1) {
    urls <- as.list(urls)
    names(urls) <- paste0("chunk_", seq_along(urls))
  }

  return(urls)
}
