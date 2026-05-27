# Download full-text PDFs or TEI XML for OpenAlex works

Downloads full-text content from the OpenAlex content endpoint
(`content.openalex.org`) for a vector of work IDs. One file is written
per ID. Downloads can be parallelised via the `workers` argument.

## Usage

``` r
pro_download_content(
  ids,
  format = c("pdf", "grobid-xml"),
  output = ".",
  workers = 1L,
  api_key = pro_api_key(),
  endpoint = "https://content.openalex.org"
)
```

## Arguments

- ids:

  Character vector of OpenAlex work IDs (e.g. `"W2741809807"`) or full
  OpenAlex URLs (`"https://openalex.org/W2741809807"`). Full URLs are
  normalised automatically.

- format:

  File format to download. One of `"pdf"` (default) or `"grobid-xml"`
  (TEI XML).

- output:

  Directory to save downloaded files into. Defaults to the current
  working directory. Created if it does not exist.

- workers:

  Number of parallel download workers. Defaults to `1` (sequential). Set
  higher for faster batch downloads, subject to the content endpoint's
  rate limits.

- api_key:

  OpenAlex API key (character string) or \`NULL\`. Defaults to the
  `openalexPro.apikey` environment variable. If \`NULL\` or \`""\`,
  requests are sent without an API key.

- endpoint:

  Base URL of the content endpoint. Defaults to
  `"https://content.openalex.org"`.

## Value

A data frame with one row per ID and columns:

- `id`:

  The (normalised) work ID.

- `file`:

  Full path to the saved file, or `NA` if not downloaded.

- `status`:

  One of `"ok"`, `"not_found"` (HTTP 404), or `"error"`.

- `message`:

  Error message, or `NA` on success.

## Costs

Content downloads cost **\$0.01 per file** — 10x the cost of a metadata
search query. Use `has_content.pdf:true` or
`has_content.grobid-xml:true` as filter arguments to
[`pro_query()`](https://rkrug.github.io/openalexPro/reference/pro_query.md)
to discover which works have downloadable content before downloading.

## Formats

- `"pdf"`:

  Full-text PDF (~60 million files available).

- `"grobid-xml"`:

  Machine-readable TEI XML parsed by Grobid (~43 million files).
  Suitable for structured text extraction.

## Licensing

PDFs and XMLs retain their original copyright. OpenAlex does not grant
additional rights. Check the `best_oa_location.license` field of each
work for the applicable licence.

## Examples

``` r
if (FALSE) { # \dontrun{
# Download a single PDF
result <- pro_download_content(
  ids    = "W2741809807",
  format = "pdf",
  output = tempdir()
)

# Find works with PDFs available, then download them
urls <- pro_query(
  entity          = "works",
  has_content.pdf = TRUE,
  from_publication_date = "2023-01-01",
  options = list(per_page = 10)
)
works <- pro_request(urls, output = tempdir())
# ... extract IDs from works data, then:
result <- pro_download_content(ids = work_ids, format = "pdf", workers = 4)

# XPAC works: discover via pro_query() with include_xpac = TRUE, then download
# (pro_download_content() works with any valid OpenAlex ID, including XPAC IDs)
urls_xpac <- pro_query(
  entity          = "works",
  has_content.pdf = TRUE,
  from_publication_date = "2023-01-01",
  options = list(include_xpac = TRUE, per_page = 10)
)
works_xpac <- pro_request(urls_xpac, output = tempdir())
# ... extract IDs from works_xpac data, then:
result_xpac <- pro_download_content(ids = xpac_ids, format = "pdf", workers = 4)
} # }
```
