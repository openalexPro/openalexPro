#' Render and open the compatibility report
#'
#' Renders the Quarto report at `system.file("compatibility.qmd", package = "openalexPro")
#' and opens the resulting HTML in your default browser.
#'
#' This report is designed to help you validate client-API compatibility in
#' real time. During rendering, the report performs live requests against the
#' OpenAlex API and compares the responses to the package's expected behavior.
#' No cached data are used: every section issues fresh API calls so that the
#' output reflects the current state of the upstream service. The report
#' summarizes differences in fields, types, pagination and response shapes to
#' surface potential regressions from upstream changes or local client updates.
#'
#' Note: Because it depends on live API calls, rendering may take longer and
#' requires network access. Be mindful of API rate limits when running the
#' report repeatedly.
#'
#' @param output_dir Directory to write the rendered HTML and the data into. Defaults to
#'    the flder `./Compatibility Report`.
#' @param open Logical; if `TRUE` (default) opens the rendered HTML in the
#'   system browser.
#' @param quiet Logical; suppress rendering output if `TRUE`. Default: `FALSE`.
#' @return Invisibly returns the path to the rendered HTML file.
#'
#' @export
compatibility_report <- function(
  output_dir = "Compatibility Report",
  open = TRUE,
  quiet = FALSE
) {
  input <- system.file(
    "compatibility.qmd",
    package = "openalexPro",
    mustWork = FALSE
  )

  if (!file.exists(input)) {
    stop("Could not find inst/compatibility.qmd")
  }

  if (!requireNamespace("quarto", quietly = TRUE)) {
    stop(
      "Package 'quarto' is required to render the report. Please install it."
    )
  }

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  # Copy the QMD into the output_dir and render there (no output_file/output_dir args)
  input_copy <- file.path(output_dir, basename(input))
  file.copy(from = input, to = input_copy, overwrite = TRUE)

  quarto::quarto_render(
    input = input_copy,
    quiet = quiet
  )

  out_file <- sub("\\.qmd$", ".html", input_copy)
  out_file <- normalizePath(out_file, mustWork = TRUE)
  if (open) {
    utils::browseURL(out_file)
  }
  invisible(out_file)
}
