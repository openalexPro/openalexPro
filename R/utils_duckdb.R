# DuckDB connection helpers.
#
# Every DuckDB connection in this package used to be a bare
# `dbConnect(duckdb::duckdb())`, which means DuckDB's defaults apply: a
# `memory_limit` of ~80% of system RAM, all cores, and a `temp_directory` of
# `.tmp` *relative to the working directory*. That is wrong in two ways when
# the connection is opened inside a parallel worker:
#
#   * N workers each believe they may use 80% of the machine, so the promise
#     is 0.8 * N of available RAM.
#   * All N share one spill directory and write colliding
#     duckdb_temp_storage_*.tmp files, which corrupts each other's spill.
#
# openalexSnapshot hit exactly this and solved it with `.oas_con()`; this is
# the same factory for openalexPro.

#' Default operator
#'
#' Defined locally rather than imported: base R only gained `%||%` in 4.4 and
#' the package supports older versions.
#'
#' @keywords internal
#' @noRd
`%||%` <- function(x, y) if (is.null(x)) y else x

#' Quote a value as a SQL string literal
#'
#' @param x Length-one character.
#' @return The value wrapped in single quotes, internal quotes doubled.
#' @keywords internal
#' @noRd
.pro_sql_str <- function(x) {
  paste0("'", gsub("'", "''", as.character(x)), "'")
}

#' Open a configured DuckDB connection
#'
#' @param memory_limit Passed to `SET memory_limit`; `NULL` leaves DuckDB's
#'   default in place.
#' @param temp_dir Spill directory. Created if missing. `NULL` leaves DuckDB's
#'   default (`.tmp`, relative to the working directory) in place -- which is
#'   unsafe for concurrent connections, so callers running in parallel should
#'   always pass one.
#' @param threads `SET threads`; `NULL` leaves DuckDB's default.
#' @param preserve_order `SET preserve_insertion_order`. Defaults to `FALSE`
#'   for throughput; set `TRUE` whenever a statement's `ORDER BY` must survive
#'   into the written file.
#' @param json Load the JSON extension (most callers here read JSON).
#' @return A DBI connection. The caller is responsible for disconnecting.
#' @keywords internal
#' @noRd
.pro_con <- function(
  memory_limit = NULL,
  temp_dir = NULL,
  threads = NULL,
  preserve_order = FALSE,
  json = FALSE
) {
  con <- DBI::dbConnect(duckdb::duckdb(), read_only = FALSE)
  DBI::dbExecute(con, paste0(
    "SET preserve_insertion_order = ",
    if (isTRUE(preserve_order)) "true" else "false"
  ))
  if (!is.null(memory_limit)) {
    DBI::dbExecute(con, paste0("SET memory_limit = ", .pro_sql_str(memory_limit)))
  }
  if (!is.null(threads)) {
    DBI::dbExecute(con, paste0("SET threads = ", as.integer(threads)))
  }
  if (!is.null(temp_dir)) {
    dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)
    DBI::dbExecute(con, paste0("SET temp_directory = ", .pro_sql_str(temp_dir)))
  }
  if (isTRUE(json)) {
    DBI::dbExecute(con, "INSTALL json; LOAD json;")
  }
  con
}

#' Total physical RAM in bytes
#'
#' Derived from DuckDB rather than from platform-specific calls: a bare
#' connection's `memory_limit` is 80% of physical RAM, so dividing by 0.8
#' recovers the total without `sysctl` / `/proc/meminfo` / a new dependency.
#'
#' Cached, because opening a connection to ask is not free.
#'
#' @return Bytes, or `NA_real_` if it cannot be determined.
#' @keywords internal
#' @noRd
.pro_total_ram_bytes <- local({
  cached <- NULL
  function() {
    if (!is.null(cached)) {
      return(cached)
    }
    out <- tryCatch(
      {
        con <- DBI::dbConnect(duckdb::duckdb())
        on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
        lim <- DBI::dbGetQuery(
          con, "SELECT current_setting('memory_limit') AS v"
        )$v[[1L]]
        .pro_parse_bytes(lim) / 0.8
      },
      error = function(e) NA_real_
    )
    if (!is.na(out)) cached <<- out
    out
  }
})

#' Parse a DuckDB byte-size string such as "28.7 GiB"
#'
#' @param x Character.
#' @return Bytes as a double, or `NA_real_`.
#' @keywords internal
#' @noRd
.pro_parse_bytes <- function(x) {
  x <- trimws(as.character(x))
  m <- regmatches(x, regexec("^([0-9.]+)\\s*([KMGTP]?)i?B?$", x, ignore.case = TRUE))[[1L]]
  if (length(m) != 3L) {
    return(NA_real_)
  }
  mult <- switch(toupper(m[[3L]]),
    "K" = 1024,
    "M" = 1024^2,
    "G" = 1024^3,
    "T" = 1024^4,
    "P" = 1024^5,
    1
  )
  as.numeric(m[[2L]]) * mult
}

#' Format bytes as a DuckDB memory-limit string
#'
#' @param bytes Numeric.
#' @return e.g. `"4.0GB"`, or `NULL` when `bytes` is not usable -- `NULL`
#'   meaning "emit no SET", so an undetectable RAM size degrades to DuckDB's
#'   own default rather than to an arbitrary number.
#' @keywords internal
#' @noRd
.pro_fmt_bytes <- function(bytes) {
  if (is.null(bytes) || !is.finite(bytes) || bytes <= 0) {
    return(NULL)
  }
  sprintf("%.0fMB", max(1024, bytes / 1024^2))
}

#' Per-worker memory budget
#'
#' Splits a fraction of physical RAM between the workers of one call. The
#' fraction is deliberately below DuckDB's own 80%: that default assumes sole
#' tenancy of the machine, which is false whenever several conversions -- or
#' several snowballs -- run at once.
#'
#' @param workers Number of concurrent workers (`NULL` or `1` = sequential).
#' @param fraction Fraction of physical RAM this call may use in total.
#' @return A memory-limit string, or `NULL` to leave DuckDB's default.
#' @keywords internal
#' @noRd
.pro_worker_memory <- function(workers = NULL, fraction = 0.5) {
  total <- .pro_total_ram_bytes()
  if (!is.finite(total)) {
    return(NULL)
  }
  n <- if (is.null(workers) || workers < 1L) 1L else as.integer(workers)
  .pro_fmt_bytes(total * fraction / n)
}

#' A private DuckDB spill directory
#'
#' `tempdir()` is evaluated inside the future worker and is therefore already
#' per-process; it is DuckDB's *relative* `.tmp` default that is shared. Adding
#' a per-task leaf makes two connections in the same process safe too.
#'
#' @param tag A short unique-per-task string.
#' @return Path (not yet created; `.pro_con()` creates it).
#' @keywords internal
#' @noRd
.pro_temp_dir <- function(tag) {
  file.path(tempdir(), "openalexPro_duckdb", gsub("[^A-Za-z0-9._-]", "_", tag))
}
