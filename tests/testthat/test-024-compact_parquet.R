library(testthat)

# Compacting the Parquet output: pro_compact_parquet() and the
# `compact_parquet` argument. No API: JSON pages as pro_request() writes them.

# Pages with `sizes` records each, IDs W<first>, W<first + 1>, ...
write_pages <- function(dir, sizes, first = 1L) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  ends <- first - 1L + cumsum(sizes)
  for (p in seq_along(sizes)) {
    ids <- ends[p] - sizes[p] + seq_len(sizes[p])
    recs <- lapply(ids, function(i) {
      list(id = paste0("https://openalex.org/W", i), title = paste("Title", i),
           publication_year = 2000L + i %% 3L)
    })
    jsonlite::write_json(
      list(results = recs, meta = list(count = sum(sizes))),
      file.path(dir, sprintf("results_page_%d.json", p)), auto_unbox = TRUE
    )
  }
  writeLines('{"query_url":"x"}', file.path(dir, "_query.json"))
  invisible(dir)
}

convert <- function(json, pq, ...) {
  pro_request_parquet(json, pq, verbose = FALSE, progress = FALSE, ...)
}

# IDs in download order: files by first page, rows as stored
ids_in_order <- function(dir) {
  f <- list.files(dir, "\\.parquet$", full.names = TRUE)
  first <- as.integer(sub(".*_([0-9]+)(-[0-9]+)?\\.parquet$", "\\1", f))
  unlist(lapply(f[order(first)], function(x) arrow::read_parquet(x, col_select = "id")$id))
}

w <- function(i) paste0("https://openalex.org/W", i)

test_that("by default nothing is compacted: one file per page, as before", {
  tmp <- withr::local_tempdir()
  write_pages(file.path(tmp, "json"), c(2, 2, 1))
  convert(file.path(tmp, "json"), file.path(tmp, "pq"))
  expect_setequal(
    list.files(file.path(tmp, "pq")),
    c("_query.json", sprintf("results_page_%d.parquet", 1:3))
  )
})

test_that("compact_parquet combines whole pages in download order, at most n records", {
  tmp <- withr::local_tempdir()
  write_pages(file.path(tmp, "json"), c(2, 2, 2, 2, 1))
  pq <- file.path(tmp, "pq")
  convert(file.path(tmp, "json"), pq, compact_parquet = 5)
  # pages 1-2 (4 records); pages 3-5 (5 records)
  expect_setequal(
    list.files(pq, all.files = TRUE, no.. = TRUE),
    c("_query.json", "results_pages_1-2.parquet", "results_pages_3-5.parquet")
  )
  expect_equal(ids_in_order(pq), w(1:9))
  expect_equal(nrow(arrow::read_parquet(file.path(pq, "results_pages_3-5.parquet"))), 5L)
  # columns unchanged, `page` kept
  d <- dplyr::collect(arrow::open_dataset(pq))
  expect_setequal(names(d), c("id", "title", "publication_year", "page"))
  expect_equal(sort(as.integer(d$page)), c(1, 1, 2, 2, 3, 3, 4, 4, 5))
})

test_that("a page with more records than the limit gets a file of its own", {
  tmp <- withr::local_tempdir()
  write_pages(file.path(tmp, "json"), c(3, 1, 1))
  pq <- file.path(tmp, "pq")
  convert(file.path(tmp, "json"), pq, compact_parquet = 2)
  expect_setequal(
    list.files(pq, "\\.parquet$"),
    c("results_pages_1-1.parquet", "results_pages_2-3.parquet")
  )
  expect_equal(ids_in_order(pq), w(1:5))
})

test_that("each query is compacted on its own; partitions and query files intact", {
  tmp <- withr::local_tempdir()
  write_pages(file.path(tmp, "json", "a"), c(2, 2, 1))
  write_pages(file.path(tmp, "json", "b"), c(2, 1), first = 100L)
  pq <- file.path(tmp, "pq")
  convert(file.path(tmp, "json"), pq, compact_parquet = 100)
  expect_setequal(list.files(file.path(pq, "query=a")), c("_query.json", "results_pages_1-3.parquet"))
  expect_setequal(list.files(file.path(pq, "query=b")), c("_query.json", "results_pages_1-2.parquet"))
  # the partition comes from the folder only, as before
  expect_false("query" %in% names(arrow::read_parquet(file.path(pq, "query=a", "results_pages_1-3.parquet"))))
  d <- dplyr::collect(arrow::open_dataset(pq))
  expect_equal(as.vector(table(d$query)[c("a", "b")]), c(5L, 3L))
  expect_equal(sort(d$id), sort(c(w(1:5), w(100:102))))
})

test_that("an interrupted compaction is completed by running it again", {
  tmp <- withr::local_tempdir()
  write_pages(file.path(tmp, "json"), c(2, 2, 2, 2))
  pq <- file.path(tmp, "pq")
  convert(file.path(tmp, "json"), pq)
  keep <- file.path(tmp, "keep")
  dir.create(keep)
  file.copy(list.files(pq, "^results_page_", full.names = TRUE), keep)
  pro_compact_parquet(pq, rows = 4, verbose = FALSE)
  # killed after the first file was renamed but before its pages were
  # deleted, and while the second file was being written
  file.remove(file.path(pq, "results_pages_3-4.parquet"))
  file.copy(list.files(keep, full.names = TRUE), pq)
  writeLines("half a file", file.path(pq, "results_pages_3-4.parquet.part"))

  # with another size: pages 1-2 are in a file already, only 3 and 4 remain
  pro_compact_parquet(pq, rows = 2, verbose = FALSE)
  expect_setequal(
    list.files(pq, all.files = TRUE, no.. = TRUE),
    c("_query.json", "results_pages_1-2.parquet", "results_pages_3-3.parquet",
      "results_pages_4-4.parquet")
  )
  expect_equal(ids_in_order(pq), w(1:8))
})

test_that("resume does not convert compacted pages again", {
  tmp <- withr::local_tempdir()
  write_pages(file.path(tmp, "json"), c(2, 2, 2))
  pq <- file.path(tmp, "pq")
  convert(file.path(tmp, "json"), pq, compact_parquet = 4)
  # the JSON is still there (delete_input = FALSE); with and without compaction
  for (compact in list(NULL, 4)) {
    convert(file.path(tmp, "json"), pq, resume = TRUE, compact_parquet = compact)
    expect_setequal(list.files(pq, "\\.parquet$"), c("results_pages_1-2.parquet", "results_pages_3-3.parquet"))
    expect_equal(ids_in_order(pq), w(1:6))
  }
})

test_that("a compaction that fails warns and keeps the page files", {
  tmp <- withr::local_tempdir()
  write_pages(file.path(tmp, "json"), c(2, 2))
  pq <- file.path(tmp, "pq")
  local_mocked_bindings(.pc_write = function(...) stop("disk full"))
  expect_warning(
    convert(file.path(tmp, "json"), pq, compact_parquet = 10),
    "Could not compact .*disk full"
  )
  expect_setequal(list.files(pq), c("_query.json", "results_page_1.parquet", "results_page_2.parquet"))
  # the conversion itself completed
  expect_false(file.exists(file.path(pq, "00_in.progress")))
})

test_that("compaction checks its input before touching anything", {
  tmp <- withr::local_tempdir()
  write_pages(file.path(tmp, "json"), c(2))
  pq <- file.path(tmp, "pq")
  expect_error(convert(file.path(tmp, "json"), pq, compact_parquet = 0), "positive whole number")
  expect_error(convert(file.path(tmp, "json"), pq, compact_parquet = "250000"), "positive whole number")
  expect_false(dir.exists(pq))

  convert(file.path(tmp, "json"), pq)
  expect_error(pro_compact_parquet(pq, rows = 1.5), "positive whole number")
  expect_error(pro_compact_parquet(file.path(tmp, "nope"), rows = 10), "does not exist")
  file.create(file.path(pq, "00_in.progress"))
  expect_error(pro_compact_parquet(pq, rows = 10), "not complete")
  file.remove(file.path(pq, "00_in.progress"))
  dir.create(file.path(tmp, "pq_id_idx"))
  expect_error(pro_compact_parquet(pq, rows = 10), "openalexSnapshot index exists")
  expect_true(file.exists(file.path(pq, "results_page_1.parquet")))
})

test_that("pro_fetch passes compact_parquet on, and does not compact by default", {
  httr2::local_mocked_responses(function(req) {
    if (identical(httr2::url_parse(req$url)$path, "/query")) {
      return(httr2::response(404))
    }
    httr2::response(200, headers = list("content-type" = "application/json"), body = charToRaw(
      '{"meta":{"count":2,"per_page":200,"next_cursor":null},"results":[{"id":"https://openalex.org/W1"},{"id":"https://openalex.org/W2"}]}'
    ))
  })
  url <- "https://api.openalex.org/works?filter=type:article"
  tmp <- withr::local_tempdir()
  pro_fetch(via = "url", url, project_folder = file.path(tmp, "default"), progress = FALSE)
  expect_true(file.exists(file.path(tmp, "default", "parquet", "results_page_1.parquet")))
  pro_fetch(via = "url", url, project_folder = file.path(tmp, "compact"), progress = FALSE, compact_parquet = 10)
  expect_equal(list.files(file.path(tmp, "compact", "parquet"), "\\.parquet$"), "results_pages_1-1.parquet")
})

test_that("download order is kept across many pages", {
  # the order must not depend on how DuckDB reads the pages in parallel
  tmp <- withr::local_tempdir()
  write_pages(file.path(tmp, "json"), rep(50, 60))
  pq <- file.path(tmp, "pq")
  convert(file.path(tmp, "json"), pq, compact_parquet = 1000)
  expect_equal(length(list.files(pq, "\\.parquet$")), 3L)
  expect_equal(ids_in_order(pq), w(1:3000))
})
