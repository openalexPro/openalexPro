#' Find the openalex-snapshot binary
#'
#' Resolves the path to the \code{openalex-snapshot} binary using the following
#' order of precedence:
#' \enumerate{
#'   \item Explicit \code{oas_bin} argument
#'   \item Package option \code{getOption("openalexPro.oas_bin")}
#'   \item \code{Sys.which("openalex-snapshot")} (PATH search)
#' }
#'
#' @param oas_bin Optional path to the binary. If \code{NULL}, falls back to
#'   the package option then PATH.
#'
#' @return Character string: absolute path to the binary.
#' @keywords internal
find_oas_binary <- function(oas_bin = NULL) {
  bin <- oas_bin
  if (is.null(bin)) bin <- getOption("openalexPro.oas_bin")
  if (is.null(bin) || nchar(bin) == 0) bin <- Sys.which("openalex-snapshot")
  if (is.null(bin) || nchar(bin) == 0 || !file.exists(bin)) {
    cli::cli_abort(c(
      "The {.code openalex-snapshot} binary was not found.",
      "i" = "Provide its path via the {.arg oas_bin} argument,",
      "i" = "or set {.code options(openalexPro.oas_bin = '/path/to/binary')},",
      "i" = "or ensure it is on PATH.",
      "i" = "Download from {.url https://github.com/rkrug/openalex-snapshot/releases}",
      "i" = "or build from source with {.code cargo build --release}."
    ))
  }
  bin
}

#' Run an openalex-snapshot subcommand
#'
#' Calls \code{openalex-snapshot} with the given argument vector via
#' \code{system2()} and aborts with an informative error if the process exits
#' with a non-zero status code.
#'
#' @param args Character vector of arguments (subcommand first, then flags).
#' @param oas_bin Optional path to the binary; passed to [find_oas_binary()].
#' @param error_call The call environment for error messages.
#'
#' @return Invisibly returns \code{0L} on success.
#' @keywords internal
run_oas <- function(args, oas_bin = NULL, error_call = rlang::caller_env()) {
  bin    <- find_oas_binary(oas_bin)
  status <- system2(bin, args)
  if (status != 0L) {
    cli::cli_abort(
      c(
        "The {.code openalex-snapshot} command failed.",
        "x" = "Exit code: {status}",
        "i" = "Command: {.code {paste(c(basename(bin), args), collapse = ' ')}}"
      ),
      call = error_call
    )
  }
  invisible(0L)
}
