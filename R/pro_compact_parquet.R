# pro_compact_parquet.R --------------------------------------------------------
#
# Fewer, larger Parquet files. pro_request_parquet() writes one file per API
# page (up to 200 records), which keeps the conversion parallel and resumable,
# but thousands of small files are slow to read.
#
# - Per directory (query partition), never across queries; `_query*` stay.
# - A compacted file holds whole consecutive pages, at most `rows` records (a
#   larger page alone), in download order, named after its page range:
#   results_page_1 .. results_page_1250 -> results_pages_1-1250.parquet.
# - Committed file by file: written to `.part`, record count checked, renamed,
#   then its pages are deleted. The name is the commit: a rerun first deletes
#   pages that a compacted file already covers, then continues. An
#   interruption loses at most the file being written.

.pc_page_pattern      <- "^(results_page|group_by_page|single)_([0-9]+)\\.parquet$"
.pc_compacted_pattern <- "^(results_page|group_by_page|single)s_([0-9]+)-([0-9]+)\\.parquet$"

#' Compact a Parquet dataset into fewer, larger files
#'
#' [pro_request_parquet()] writes one Parquet file per API page (up to 200
#' records). That keeps the conversion parallel and resumable, but a large
#' query becomes thousands of small files, which are slow to read.
#' `pro_compact_parquet()` combines them into files of up to `rows` records.
#' Records, columns and their order do not change.
#'
#' Measured for 1.1 million works (5,460 page files): compaction took about
#' 20 seconds; afterwards aggregates and lookups by ID ran 35 to 50 times
#' faster, reading full records with DuckDB 4 times faster, and the dataset
#' was 40% smaller. Files of 50,000 to 1 million records made no difference
#' to read speed; `rows = 250000` is a good choice (about 0.25 GB of full
#' works records; newer works with abstracts and long reference lists are
#' larger).
#'
#' @details
#' - Each query's partition (`query=<name>/`) is compacted on its own; its
#'   `_query.json` and `_query_oql.*` files stay.
#' - A compacted file holds whole consecutive pages, in download order, and is
#'   named after them: pages 1 to 1250 become `results_pages_1-1250.parquet`.
#'   A page with more than `rows` records becomes a file of its own. The
#'   `page` column is kept.
#' - Files are compacted one at a time: each is written to a `.part` file, its
#'   record count checked, renamed, and only then are its pages deleted. If
#'   interrupted, run it again: it completes what was started.
#' - Files compacted before are left as they are; only page files are
#'   combined.
#' - If a partition cannot be compacted (for example because its pages have
#'   conflicting column types), a warning says so and its page files stay:
#'   the dataset is complete either way.
#' - Indexes built by `openalexSnapshot::build_corpus_index()` or
#'   `build_doi_index()` point to files and row numbers, and would be wrong
#'   after compaction. If such an index exists next to `parquet_dir`, the
#'   function stops: delete the index, compact, and build it again.
#'
#' @param parquet_dir Output directory of [pro_request_parquet()], or the
#'   `parquet` folder of a [pro_fetch()] project.
#' @param rows Maximum number of records per compacted file, e.g. `250000`.
#' @param verbose Logical. Report what was compacted. Default `TRUE`.
#'
#' @return `parquet_dir` (invisibly).
#'
#' @seealso The `compact_parquet` argument of [pro_request_parquet()] and
#'   [pro_fetch()], which compacts right after the conversion.
#'
#' @examples
#' \dontrun{
#' pro_compact_parquet("my_project/parquet", rows = 250000)
#' }
#'
#' @md
#' @export
pro_compact_parquet <- function(parquet_dir, rows, verbose = TRUE) {
  .pc_check_rows(rows, "rows")
  if (!dir.exists(parquet_dir)) {
    stop("`parquet_dir` does not exist: ", parquet_dir, call. = FALSE)
  }
  if (file.exists(file.path(parquet_dir, "00_in.progress"))) {
    stop(
      "The conversion into ", parquet_dir, " is not complete (00_in.progress). ",
      "Complete it with `resume = TRUE` first.",
      call. = FALSE
    )
  }
  dir_abs <- normalizePath(parquet_dir)
  index <- file.path(
    dirname(dir_abs), paste0(basename(dir_abs), c("_id_idx", "_doi_idx.parquet"))
  )
  if (any(file.exists(index))) {
    stop(
      "An openalexSnapshot index exists for ", parquet_dir, ": ",
      paste(basename(index[file.exists(index)]), collapse = ", "), ". ",
      "It points to files and row numbers that compaction changes. ",
      "Delete the index, compact, and build it again.",
      call. = FALSE
    )
  }
  .pc_compact(parquet_dir, rows, verbose)
  invisible(parquet_dir)
}

#' @keywords internal
#' @noRd
.pc_check_rows <- function(rows, arg) {
  if (!is.numeric(rows) || length(rows) != 1L || is.na(rows) ||
      rows < 1 || rows != round(rows)) {
    stop(
      "`", arg, "` must be a single positive whole number of records, ",
      "e.g. 250000.",
      call. = FALSE
    )
  }
  invisible(rows)
}

#' Compact every directory below `parquet_dir` that holds page files
#'
#' A directory that fails gives a warning and keeps its page files.
#'
#' @keywords internal
#' @noRd
.pc_compact <- function(parquet_dir, rows, verbose = FALSE) {
  files <- list.files(parquet_dir, .pc_page_pattern, recursive = TRUE, full.names = TRUE)
  dirs <- unique(dirname(files))
  n_written <- 0L
  for (d in dirs) {
    n_written <- n_written + tryCatch(
      .pc_compact_dir(d, rows),
      error = function(e) {
        unlink(list.files(d, "\\.parquet\\.part$", full.names = TRUE))
        warning(
          "Could not compact ", d, ": ", conditionMessage(e), "\n",
          "Its page files that were not compacted are kept; the dataset is ",
          "complete.",
          call. = FALSE
        )
        0L
      }
    )
  }
  if (verbose && length(files) > 0L) {
    message(
      "Compacted ", length(files), " page file(s) into ", n_written,
      " file(s) of up to ", format(rows, big.mark = ",", scientific = FALSE),
      " records."
    )
  }
  invisible(n_written)
}

#' Compact the page files of one directory
#'
#' @return Number of compacted files written.
#' @keywords internal
#' @noRd
.pc_compact_dir <- function(dir, rows) {
  unlink(list.files(dir, "\\.parquet\\.part$", full.names = TRUE))
  pages <- .pc_pages(dir)
  # Complete an interrupted run: pages a compacted file already holds
  covered <- .pc_covered(pages$file)
  unlink(pages$file[covered])
  pages <- pages[!covered, , drop = FALSE]
  if (nrow(pages) == 0L) {
    return(0L)
  }

  con <- .pro_con(
    memory_limit = .pro_worker_memory(1L),
    temp_dir = .pro_temp_dir(paste0("compact_", basename(dir))),
    preserve_order = TRUE
  )
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  pages$n <- .pc_count(con, pages$file)
  n_written <- 0L
  for (prefix in unique(pages$prefix)) {
    p <- pages[pages$prefix == prefix, , drop = FALSE]
    chunk <- .pc_chunks(p$n, rows)
    for (k in unique(chunk)) {
      ck <- p[chunk == k, , drop = FALSE]
      target <- file.path(dir, sprintf(
        "%ss_%d-%d.parquet", prefix, ck$number[1L], ck$number[nrow(ck)]
      ))
      .pc_write(con, ck$file, target, sum(ck$n))
      unlink(ck$file)
      n_written <- n_written + 1L
    }
  }
  n_written
}

#' Page files of a directory, in page order
#' @keywords internal
#' @noRd
.pc_pages <- function(dir) {
  f <- list.files(dir, .pc_page_pattern)
  p <- utils::strcapture(.pc_page_pattern, f, data.frame(prefix = "", number = 0L))
  p$file <- file.path(dir, f)
  p[order(p$prefix, p$number), , drop = FALSE]
}

#' Which page files are already part of a compacted file in their directory
#' @keywords internal
#' @noRd
.pc_covered <- function(files) {
  out <- logical(length(files))
  for (d in unique(dirname(files))) {
    comp <- list.files(d, .pc_compacted_pattern)
    if (length(comp) == 0L) next
    rng <- utils::strcapture(.pc_compacted_pattern, comp,
                             data.frame(prefix = "", from = 0L, to = 0L))
    i <- which(dirname(files) == d)
    pg <- utils::strcapture(.pc_page_pattern, basename(files[i]),
                            data.frame(prefix = "", number = 0L))
    out[i] <- vapply(seq_along(i), function(j) {
      isTRUE(any(rng$prefix == pg$prefix[j] &
                 pg$number[j] >= rng$from & pg$number[j] <= rng$to))
    }, logical(1))
  }
  out
}

#' Records per file (from the Parquet footers)
#' @keywords internal
#' @noRd
.pc_count <- function(con, files) {
  x <- DBI::dbGetQuery(con, sprintf(
    "SELECT filename, count(*) AS n
       FROM read_parquet(%s, filename = true, hive_partitioning = false,
                         union_by_name = true)
      GROUP BY filename",
    .pc_paths(files)
  ))
  n <- as.numeric(x$n[match(basename(files), basename(x$filename))])
  n[is.na(n)] <- 0 # a page without records
  n
}

#' Consecutive pages into chunks of at most `rows` records
#'
#' A page with more than `rows` records is a chunk of its own.
#'
#' @keywords internal
#' @noRd
.pc_chunks <- function(n, rows) {
  chunk <- integer(length(n))
  k <- 1L
  total <- 0
  for (i in seq_along(n)) {
    if (total > 0 && total + n[i] > rows) {
      k <- k + 1L
      total <- 0
    }
    chunk[i] <- k
    total <- total + n[i]
  }
  chunk
}

#' Write one compacted file: `.part`, check, rename
#'
#' Rows in download order: page number, then position within the page. The
#' explicit ORDER BY (with `preserve_insertion_order`) is needed: without it
#' DuckDB and arrow both wrote the records shuffled.
#'
#' @keywords internal
#' @noRd
.pc_write <- function(con, files, target, n_expected) {
  part <- paste0(target, ".part")
  unlink(part)
  DBI::dbExecute(con, sprintf(
    "COPY (
       SELECT * EXCLUDE (filename, file_row_number)
         FROM read_parquet(%s, filename = true, file_row_number = true,
                           hive_partitioning = false, union_by_name = true)
        ORDER BY CAST(regexp_extract(filename, '_([0-9]+)\\.parquet$', 1) AS BIGINT),
                 file_row_number
     ) TO %s (FORMAT PARQUET, COMPRESSION SNAPPY, ROW_GROUP_SIZE 100000)",
    .pc_paths(files), .pro_sql_str(part)
  ))
  n <- DBI::dbGetQuery(con, sprintf(
    "SELECT count(*) AS n FROM read_parquet(%s)", .pro_sql_str(part)
  ))$n
  if (!isTRUE(n == n_expected)) {
    unlink(part)
    stop(basename(target), " has ", n, " records instead of ", n_expected, call. = FALSE)
  }
  if (!file.rename(part, target)) {
    unlink(part)
    stop("Could not rename ", part, call. = FALSE)
  }
  invisible(target)
}

#' @keywords internal
#' @noRd
.pc_paths <- function(files) {
  paste0("[", paste(vapply(files, .pro_sql_str, character(1)), collapse = ", "), "]")
}
