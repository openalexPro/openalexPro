#' Extract DOIs or Components from Character Vectors
#'
#' Extracts DOIs or specific DOI components (resolver, prefix, or suffix) from a character vector.
#' Assumes that each element of `x` contains at most one DOI (with or without resolver).
#'
#' Percent-encoded characters are decoded first, also when encoded twice
#' (`%255B` -> `%5B` -> `[`), so an encoded DOI is recognised in full and an
#' encoded line break (`%0A`) ends it. A DOI followed directly by a `%` that is
#' not an encoding, such as the unfilled placeholders in `10.18461/ijfsd.v2i4.%x`
#' or `10.37002/biobrasil.v%vi%i.798`, is not recognised at all rather than
#' cut short to something that looks valid.
#' A full stop or semicolon at the end is taken as punctuation and dropped.
#'
#' @param x A character vector potentially containing DOIs (e.g., raw DOIs,
#'   DOI URLs, or strings with embedded DOIs).
#' @param non_doi_value Value to use for elements where no DOI or component is
#'   found. If `NULL`, only matched elements are returned.
#' @param normalize Logical. If `TRUE` (default), convert extracted DOIs and
#'   suffixes to lowercase and trim surrounding whitespace. Has no effect for
#'   `what = "prefix"` or `what = "resolver"`.
#' @param lower Logical. With `normalize = TRUE`, convert to lowercase
#'   (default). `FALSE` keeps the upper and lower case of the input, e.g. to
#'   compare the cleaned DOI with the field it came from.
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
  lower = TRUE,
  what = c("doi", "resolver", "prefix", "suffix")
) {
  what <- match.arg(what, choices = c("doi", "resolver", "prefix", "suffix"))

  nm <- names(x)

  x[is.na(x)] <- ""
  # Decode percent-encoding, repeatedly for double encoding (%255B -> [).
  # Invalid sequences such as `%x` are kept, and rejected by `(?!%)` below.
  for (i in 1:3) {
    decoded <- curl::curl_unescape(x)
    if (identical(decoded, x)) break
    x <- decoded
  }

  # Common regex patterns
  # The character class must admit < > [ ] : real DOIs use them. SICI-style
  # DOIs such as 10.1175/1520-0450(1963)002<0713:ooasds>2.0.co;2 are common
  # in older AMS/ASLO/Wiley content (~0.4% of OpenAlex works). Without them
  # the match stops at the first < and returns a TRUNCATED string that still
  # looks like a valid DOI, which is worse than no match at all.
  # "]" comes first and "-" last in the class, so neither needs escaping.
  # A "#" is taken only as the SICI check character (`...>3.0.co;2-#`), not
  # as a URL fragment. The possessive `++` with `(?!%)` rejects a DOI that
  # runs into a `%` left after decoding (an unfilled placeholder, `v%vi%i`)
  # instead of returning the part before it.
  doi_pattern <- "10\\.[0-9]{4,9}/(?:[]._;()/:<>[A-Z0-9-]|(?<=;2-)#)++(?!%)"
  resolver_pattern <- "https?://[^\\s/]+/?"
  prefix_pattern <- "10\\.[0-9]{4,9}"

  if (what == "doi") {
    m <- regexpr(doi_pattern, x, ignore.case = TRUE, perl = TRUE)
    matches <- regmatches(x, m)
  } else if (what == "resolver") {
    m <- regexpr(resolver_pattern, x, ignore.case = TRUE)
    matches <- regmatches(x, m)
  } else if (what == "prefix") {
    m <- regexpr(prefix_pattern, x, ignore.case = TRUE)
    matches <- regmatches(x, m)
  } else if (what == "suffix") {
    # First get the DOI
    m <- regexpr(doi_pattern, x, ignore.case = TRUE, perl = TRUE)
    full_dois <- regmatches(x, m)
    matches <- sub("^10\\.[0-9]{4,9}/", "", full_dois, ignore.case = TRUE)
  }

  # A full stop or semicolon at the end is sentence punctuation
  # (`doi:10.1098/rstb.2016.0173.`), not part of the DOI.
  if (what %in% c("doi", "suffix")) {
    matches <- sub("[.;]+$", "", matches)
  }

  matched_idx <- which(m != -1)
  if (length(matched_idx)) {
    names(matches) <- nm[matched_idx]
  }

  if (normalize && length(matches)) {
    # Step 1: trim (+ lowercase)
    matches <- trimws(matches)
    if (lower) matches <- tolower(matches)
  }

  if (normalize && length(matched_idx) > 0) {
    # Step 2: character whitelist check for certain components
    if (what %in% c("doi", "prefix", "suffix")) {
      valid_pattern <- "^[]0-9a-z./:;()_<>#[-]+$"
      valid <- grepl(valid_pattern, matches, ignore.case = TRUE)

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
