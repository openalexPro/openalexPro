#' Download full-text PDFs or TEI XML for OpenAlex works
#'
#' Downloads full-text content from the OpenAlex content endpoint
#' (\code{content.openalex.org}) for a vector of work IDs. One file is written
#' per ID. Downloads can be parallelised via the \code{workers} argument.
#'
#' @section Costs:
#' Content downloads cost \strong{$0.01 per file} — 10x the cost of a
#' metadata search query. Use \code{has_content.pdf:true} or
#' \code{has_content.grobid-xml:true} as filter arguments to \code{pro_query()}
#' to discover which works have downloadable content before downloading.
#'
#' @section Formats:
#' \describe{
#'   \item{\code{"pdf"}}{Full-text PDF (~60 million files available).}
#'   \item{\code{"grobid-xml"}}{Machine-readable TEI XML parsed by Grobid
#'     (~43 million files). Suitable for structured text extraction.}
#' }
#'
#' @section Licensing:
#' PDFs and XMLs retain their original copyright. OpenAlex does not grant
#' additional rights. Check the \code{best_oa_location.license} field of each
#' work for the applicable licence.
#'
#' @param ids Character vector of OpenAlex work IDs (e.g.
#'   \code{"W2741809807"}) or full OpenAlex URLs
#'   (\code{"https://openalex.org/W2741809807"}). Full URLs are normalised
#'   automatically.
#' @param format File format to download. One of \code{"pdf"} (default) or
#'   \code{"grobid-xml"} (TEI XML).
#' @param output Directory to save downloaded files into. Defaults to the
#'   current working directory. Created if it does not exist.
#' @param workers Number of parallel download workers. Defaults to \code{1}
#'   (sequential). Set higher for faster batch downloads, subject to the
#'   content endpoint's rate limits.
#' @param api_key OpenAlex API key (character string) or `NULL`. Defaults to
#'   the \code{openalexPro.apikey} environment variable. If `NULL` or `""`,
#'   requests are sent without an API key.
#' @param endpoint Base URL of the content endpoint. Defaults to
#'   \code{"https://content.openalex.org"}.
#'
#' @return A data frame with one row per ID and columns:
#'   \describe{
#'     \item{\code{id}}{The (normalised) work ID.}
#'     \item{\code{file}}{Full path to the saved file, or \code{NA} if not
#'       downloaded.}
#'     \item{\code{status}}{One of \code{"ok"}, \code{"not_found"} (HTTP 404),
#'       or \code{"error"}.}
#'     \item{\code{message}}{Error message, or \code{NA} on success.}
#'   }
#'
#' @examples
#' \dontrun{
#' # Download a single PDF
#' result <- pro_download_content(
#'   ids    = "W2741809807",
#'   format = "pdf",
#'   output = tempdir()
#' )
#'
#' # Find works with PDFs available, then download them
#' urls <- pro_query(
#'   entity          = "works",
#'   has_content.pdf = TRUE,
#'   from_publication_date = "2023-01-01",
#'   options = list(per_page = 10)
#' )
#' works <- pro_request(urls, output = tempdir())
#' # ... extract IDs from works data, then:
#' result <- pro_download_content(ids = work_ids, format = "pdf", workers = 4)
#'
#' # XPAC works: discover via pro_query() with include_xpac = TRUE, then download
#' # (pro_download_content() works with any valid OpenAlex ID, including XPAC IDs)
#' urls_xpac <- pro_query(
#'   entity          = "works",
#'   has_content.pdf = TRUE,
#'   from_publication_date = "2023-01-01",
#'   options = list(include_xpac = TRUE, per_page = 10)
#' )
#' works_xpac <- pro_request(urls_xpac, output = tempdir())
#' # ... extract IDs from works_xpac data, then:
#' result_xpac <- pro_download_content(ids = xpac_ids, format = "pdf", workers = 4)
#' }
#'
#' @export
#' @importFrom httr2 request req_url_query req_user_agent req_perform resp_body_raw resp_body_string resp_status
#' @importFrom future plan multisession sequential
#' @importFrom future.apply future_lapply
#' @importFrom progressr with_progress progressor handlers
#' @importFrom cli cli_alert_info cli_alert_success cli_alert_warning
pro_download_content <- function(
  ids,
  format = c("pdf", "grobid-xml"),
  output = ".",
  workers = 1L,
  api_key = pro_api_key(),
  endpoint = "https://content.openalex.org"
) {
  format <- match.arg(format)

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

  if (!length(ids) || all(is.na(ids))) {
    stop("'ids' must be a non-empty character vector.", call. = FALSE)
  }

  # Normalise: strip full URL prefix -> bare ID
  ids <- sub("^https?://openalex\\.org/", "", ids)

  # Create output directory if needed
  if (!dir.exists(output)) {
    dir.create(output, recursive = TRUE)
  }
  output <- normalizePath(output)

  # Set up parallel plan
  old_plan <- future::plan()
  on.exit(future::plan(old_plan), add = TRUE)
  if (workers > 1L) {
    future::plan(future::multisession, workers = workers)
  } else {
    future::plan(future::sequential)
  }

  cli::cli_alert_info("Downloading {length(ids)} {format} file{?s}...")

  progressr::with_progress({
    p <- progressr::progressor(steps = length(ids))

    results <- future.apply::future_lapply(
      ids,
      function(id) {
        url <- paste0(endpoint, "/works/", id, ".", format)
        out_file <- file.path(output, paste0(id, ".", format))

        result <- tryCatch(
          {
            req <- httr2::request(url)
            if (!is.null(api_key)) {
              req <- httr2::req_url_query(req, api_key = api_key)
            }
            req <- httr2::req_user_agent(
              req,
              paste0("openalexPro/", utils::packageVersion("openalexPro"))
            )

            resp <- suppressMessages(api_call(
              req,
              max_retries = 5,
              get_html_response = NULL
            ))
            status_code <- httr2::resp_status(resp)

            if (status_code == 404L) {
              list(
                id = id,
                file = NA_character_,
                status = "not_found",
                message = "Content not available in this format"
              )
            } else if (status_code >= 400L) {
              list(
                id = id,
                file = NA_character_,
                status = "error",
                message = paste0("HTTP ", status_code)
              )
            } else {
              if (format == "pdf") {
                writeBin(httr2::resp_body_raw(resp), out_file)
              } else {
                writeLines(httr2::resp_body_string(resp), out_file)
              }
              list(
                id = id,
                file = out_file,
                status = "ok",
                message = NA_character_
              )
            }
          },
          error = function(e) {
            list(
              id = id,
              file = NA_character_,
              status = "error",
              message = conditionMessage(e)
            )
          }
        )

        p()
        result
      },
      future.seed = TRUE
    )
  })

  # Assemble data frame
  out <- data.frame(
    id = vapply(results, `[[`, character(1), "id"),
    file = vapply(results, `[[`, character(1), "file"),
    status = vapply(results, `[[`, character(1), "status"),
    message = vapply(results, `[[`, character(1), "message"),
    stringsAsFactors = FALSE
  )

  n_ok <- sum(out$status == "ok")
  n_404 <- sum(out$status == "not_found")
  n_err <- sum(out$status == "error")

  cli::cli_alert_success("{n_ok} file{?s} downloaded successfully.")
  if (n_404 > 0) {
    cli::cli_alert_warning("{n_404} ID{?s} had no content available (404).")
  }
  if (n_err > 0) {
    cli::cli_alert_warning("{n_err} download{?s} failed with errors.")
  }

  out
}
