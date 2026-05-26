library(testthat)
library(arrow)
library(dplyr)

# ---------------------------------------------------------------------------
# Unit tests: collect_leaf_queries helper
# ---------------------------------------------------------------------------

test_that("collect_leaf_queries: single URL", {
  result <- collect_leaf_queries("https://example.com/works")
  expect_length(result, 1L)
  expect_equal(result[[1]]$url, "https://example.com/works")
  expect_equal(result[[1]]$path, character(0))
})

test_that("collect_leaf_queries: flat named list", {
  q <- list(a = "https://a.com", b = "https://b.com")
  result <- collect_leaf_queries(q)
  expect_length(result, 2L)
  expect_equal(result[[1]]$path, "a")
  expect_equal(result[[2]]$path, "b")
  expect_equal(result[[1]]$url, "https://a.com")
})

test_that("collect_leaf_queries: flat unnamed list", {
  q <- list("https://a.com", "https://b.com")
  result <- collect_leaf_queries(q)
  expect_length(result, 2L)
  expect_equal(result[[1]]$path, "query_1")
  expect_equal(result[[2]]$path, "query_2")
})

test_that("collect_leaf_queries: two-level nesting", {
  q <- list(
    grp_a = list(x = "https://a.com", y = "https://b.com"),
    grp_b = "https://c.com"
  )
  result <- collect_leaf_queries(q)
  expect_length(result, 3L)
  expect_equal(result[[1]]$path, c("grp_a", "x"))
  expect_equal(result[[2]]$path, c("grp_a", "y"))
  expect_equal(result[[3]]$path, c("grp_b"))
})

test_that("collect_leaf_queries: three-level nesting", {
  q <- list(l1 = list(l2 = list(l3 = "https://deep.com")))
  result <- collect_leaf_queries(q)
  expect_length(result, 1L)
  expect_equal(result[[1]]$path, c("l1", "l2", "l3"))
  expect_equal(result[[1]]$url, "https://deep.com")
})

# ---------------------------------------------------------------------------
# Integration test: pro_request_jsonl_parquet with nested JSONL directories
# ---------------------------------------------------------------------------

make_minimal_jsonl <- function(path, n = 2L, page = 1L) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  lines <- vapply(
    seq_len(n),
    function(i) sprintf('{"id":"W%d%d","title":"Paper %d","page":%d}', page, i, i, page),
    character(1)
  )
  writeLines(lines, path)
}

test_that("pro_request_jsonl_parquet: two-level hive partitioning", {
  base_jsonl <- file.path(tempdir(), "nested_jsonl_test")
  base_parquet <- file.path(tempdir(), "nested_parquet_test")
  on.exit({
    unlink(base_jsonl, recursive = TRUE, force = TRUE)
    unlink(base_parquet, recursive = TRUE, force = TRUE)
  })

  # Build two-level nested JSONL structure
  # grp_a/sub_x/results_page_1.json
  # grp_a/sub_y/results_page_1.json
  # grp_b/results_page_1.json
  make_minimal_jsonl(file.path(base_jsonl, "grp_a", "sub_x", "results_page_1.json"), page = 1L)
  make_minimal_jsonl(file.path(base_jsonl, "grp_a", "sub_y", "results_page_1.json"), page = 1L)
  make_minimal_jsonl(file.path(base_jsonl, "grp_b",          "results_page_1.json"), page = 1L)

  out <- pro_request_jsonl_parquet(
    input_jsonl = base_jsonl,
    output = base_parquet,
    verbose = FALSE
  )

  parquet_files <- sort(list.files(out, "*.parquet", recursive = TRUE))

  # Expect hive-partitioned paths
  expect_true(any(grepl("^query=grp_a/query_l2=sub_x/", parquet_files)))
  expect_true(any(grepl("^query=grp_a/query_l2=sub_y/", parquet_files)))
  expect_true(any(grepl("^query=grp_b/",                parquet_files)))

  # Dataset readable as a whole
  ds <- arrow::open_dataset(out)
  expect_true("id" %in% names(ds))
  expect_gt(nrow(dplyr::collect(ds)), 0L)
})

test_that("pro_request_jsonl_parquet: single-level hive partitioning unchanged", {
  base_jsonl <- file.path(tempdir(), "flat_jsonl_test")
  base_parquet <- file.path(tempdir(), "flat_parquet_test")
  on.exit({
    unlink(base_jsonl, recursive = TRUE, force = TRUE)
    unlink(base_parquet, recursive = TRUE, force = TRUE)
  })

  make_minimal_jsonl(file.path(base_jsonl, "chunk_1", "results_page_1.json"), page = 1L)
  make_minimal_jsonl(file.path(base_jsonl, "chunk_2", "results_page_1.json"), page = 1L)

  out <- pro_request_jsonl_parquet(
    input_jsonl = base_jsonl,
    output = base_parquet,
    verbose = FALSE
  )

  parquet_files <- sort(list.files(out, "*.parquet", recursive = TRUE))
  expect_true(any(grepl("^query=chunk_1/", parquet_files)))
  expect_true(any(grepl("^query=chunk_2/", parquet_files)))
  # No second-level partition key
  expect_false(any(grepl("query_l2=", parquet_files)))
})

# ---------------------------------------------------------------------------
# Integration test: nested pro_request with VCR cassettes
# ---------------------------------------------------------------------------

output_json_nested    <- file.path(tempdir(), "nested_json")
output_jsonl_nested   <- file.path(tempdir(), "nested_jsonl")
output_parquet_nested <- file.path(tempdir(), "nested_parquet")

unlink(output_json_nested,    recursive = TRUE, force = TRUE)
unlink(output_jsonl_nested,   recursive = TRUE, force = TRUE)
unlink(output_parquet_nested, recursive = TRUE, force = TRUE)

dois <- readRDS(testthat::test_path("..", "fixtures", "dois.rds"))

build_nested_req <- function(dois) {
  vcr::local_cassette("opt_filter_names")
  flat <- pro_query(entity = "works", doi = dois)
  # wrap two flat chunks into a two-level nested list
  list(
    grp_a = flat[seq_len(floor(length(flat) / 2))],
    grp_b = flat[seq(floor(length(flat) / 2) + 1L, length(flat))]
  )
}

test_that("pro_request with nested list creates nested output dirs", {
  req <- build_nested_req(dois)
  vcr::local_cassette("pro_request_parallel")

  out <- pro_request(
    query_url = req,
    output    = output_json_nested,
    verbose   = FALSE,
    progress  = TRUE
  )

  json_files <- sort(list.files(output_json_nested, "*.json", recursive = TRUE))
  # All files should be under grp_a/* or grp_b/*
  expect_true(all(grepl("^grp_[ab]/", json_files)))
  expect_snapshot(json_files)
})

test_that("pro_request_jsonl_R with nested subdirs", {
  out <- pro_request_jsonl_R(
    input  = output_json_nested,
    output = output_jsonl_nested,
    verbose = FALSE,
    progress = TRUE
  )

  jsonl_files <- sort(list.files(output_jsonl_nested, "*.json", recursive = TRUE))
  expect_true(all(grepl("^grp_[ab]/", jsonl_files)))
  expect_snapshot(jsonl_files)
})

test_that("pro_request_jsonl_parquet with nested subdirs produces hive partitions", {
  out <- pro_request_jsonl_parquet(
    input_jsonl = output_jsonl_nested,
    output      = output_parquet_nested,
    verbose     = FALSE
  )

  parquet_files <- sort(list.files(out, "*.parquet", recursive = TRUE))
  expect_true(any(grepl("^query=grp_a/query_l2=", parquet_files)))
  expect_true(any(grepl("^query=grp_b/query_l2=", parquet_files)))

  ds <- arrow::open_dataset(out)
  expect_true("id" %in% names(ds))
  expect_snapshot({
    parquet_files
    ds
    ds |>
      dplyr::select(page) |>
      dplyr::distinct() |>
      dplyr::arrange(page) |>
      dplyr::collect()
  })
})

unlink(output_json_nested,    recursive = TRUE, force = TRUE)
unlink(output_jsonl_nested,   recursive = TRUE, force = TRUE)
unlink(output_parquet_nested, recursive = TRUE, force = TRUE)
