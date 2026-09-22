#' Extract DOIs or Components from Character Vectors
#'
#' Extracts DOIs or specific DOI components (resolver, prefix, or suffix) from a character vector.
#' Assumes that each element of `x` contains at most one DOI (with or without resolver).
#'
#' @param x A character vector potentially containing DOIs (e.g., raw DOIs,
#'   DOI URLs, or strings with embedded DOIs).
#' @param non_doi_value Value to use for elements where no DOI or component is
#'   found. If `NULL`, only matched elements are returned.
#' @param normalize Logical. If `TRUE` (default), convert extracted DOIs and
#'   suffixes to lowercase and trim surrounding whitespace. Has no effect for
#'   `what = "prefix"` or `what = "resolver"`.
#' @param what What to extract from each element. One of:
#' \describe{
#'   \item{"doi"}{The full DOI name (prefix + "/" + suffix). Example:
#'     `"10.5281/zenodo.1234567"` (default)}
#'   \item{"resolver"}{The resolver URL (e.g., `"https://doi.org/"`,
#'     `"http://dx.doi.org/"`) if present}
#'   \item{"prefix"}{The DOI prefix only (e.g., `"10.5281"`)}
#'   \item{"suffix"}{The DOI suffix only (e.g., `"zenodo.1234567"`)}
#' }
#'
#' @return A character vector:
#'   - If `non_doi_value` is not `NULL`, a vector of the same length as `x`,
#'     with unmatched entries replaced.
#'   - If `non_doi_value` is `NULL`, a vector of only matched entries.
#'
#' @examples
#' x <- c(
#'   "https://doi.org/10.5281/zenodo.1234567",
#'   " 10.1000/XYZ456  ",
#'   "no doi here",
#'   NA
#' )
#'
#' extract_doi(x)  # Full DOIs (default)
#' extract_doi(x, what = "resolver")
#' extract_doi(x, what = "prefix")
#' extract_doi(x, what = "suffix")
#' extract_doi(x, non_doi_value = NA_character_)
#' extract_doi(x, non_doi_value = NULL)
#'
#' @export

extract_doi <- function(
  x,
  non_doi_value = "",
  normalize = TRUE,
  what = c("doi", "resolver", "prefix", "suffix")
) {
  what <- match.arg(what, choices = c("doi", "resolver", "prefix", "suffix"))

  nm <- names(x)

  x[is.na(x)] <- ""

  # Common regex patterns
  # The character class must admit < > [ ] : real DOIs use them. SICI-style
  # DOIs such as 10.1175/1520-0450(1963)002<0713:ooasds>2.0.co;2 are common
  # in older AMS/ASLO/Wiley content (~0.4% of OpenAlex works). Without them
  # the match stops at the first < and returns a TRUNCATED string that still
  # looks like a valid DOI, which is worse than no match at all.
  # In a POSIX bracket expression a backslash is literal, so "]" must come
  # first and "-" last rather than being escaped.
  doi_pattern <- "10\\.[0-9]{4,9}/[]._;()/:<>[A-Z0-9-]+"
  resolver_pattern <- "https?://[^\\s/]+/?"
  prefix_pattern <- "10\\.[0-9]{4,9}"

  if (what == "doi") {
    m <- regexpr(doi_pattern, x, ignore.case = TRUE)
    matches <- regmatches(x, m)
  } else if (what == "resolver") {
    m <- regexpr(resolver_pattern, x, ignore.case = TRUE)
    matches <- regmatches(x, m)
  } else if (what == "prefix") {
    m <- regexpr(prefix_pattern, x, ignore.case = TRUE)
    matches <- regmatches(x, m)
  } else if (what == "suffix") {
    # First get the DOI
    m <- regexpr(doi_pattern, x, ignore.case = TRUE)
    full_dois <- regmatches(x, m)
    matches <- sub("^10\\.[0-9]{4,9}/", "", full_dois, ignore.case = TRUE)
  }

  matched_idx <- which(m != -1)
  if (length(matched_idx)) {
    names(matches) <- nm[matched_idx]
  }

  if (normalize && length(matches)) {
    # Step 1: lowercase + trim
    matches <- tolower(trimws(matches))
  }

  if (normalize && length(matched_idx) > 0) {
    # Step 2: character whitelist check for certain components
    if (what %in% c("doi", "prefix", "suffix")) {
      valid_pattern <- "^[]0-9a-z./:;()_<>[-]+$"
      valid <- grepl(valid_pattern, matches, ignore.case = FALSE)

      if (is.null(non_doi_value)) {
        # Keep only valid entries
        matches <- matches[valid]
        names(matches) <- nm[matched_idx][valid]
      } else {
        # Replace invalid entries with fallback
        matches[!valid] <- non_doi_value
      }
    }
  }

  if (is.null(non_doi_value)) {
    # Only return matched DOIs (order preserved among matches, but overall length is shortened)
    out <- matches
    names(out) <- names(matches)
  } else {
    # Return vector aligned to x
    out <- rep(non_doi_value, length(x))
    names(out) <- nm
    out[matched_idx] <- matches
  }

  return(out)
}
