test_that("hive_names sets the partition key per nesting level", {
  f <- c("/in/a/x/results_page_1.json", "/in/b/results_page_1.json")
  rel <- function(hn) sub("^/out/", "", openalexPro:::.prr_output_paths(f, "/in", "/out", hn))

  expect_equal(rel(NULL), c("query=a/query_l2=x/results_page_1.parquet", "query=b/results_page_1.parquet"))
  expect_equal(
    rel(c("topic", "year")),
    c("topic=a/year=x/results_page_1.parquet", "topic=b/results_page_1.parquet")
  )
  # NA and missing levels keep the default
  expect_equal(rel(c(NA, "year"))[1], "query=a/year=x/results_page_1.parquet")
  expect_equal(rel("topic")[1], "topic=a/query_l2=x/results_page_1.parquet")
})

test_that("hive_names is validated", {
  check <- openalexPro:::.prr_check_hive_names
  expect_true(check(NULL))
  expect_true(check(c("a", NA, "b_2")))
  expect_error(check(c("a", "a")), "unique")
  expect_error(check("a=b"), "hive_names")
  expect_error(check("has space"), "hive_names")
  expect_error(check(1), "hive_names")
  expect_error(pro_request_parquet(input_json = "x", output = "y", hive_names = "a/b"), "hive_names")
})

test_that("a query named key=value supplies its own partition key", {
  f <- c("/in/year=2020/results_page_1.json", "/in/plain/results_page_1.json")
  rel <- function(hn) sub("^/out/", "", openalexPro:::.prr_output_paths(f, "/in", "/out", hn))
  expect_equal(rel(NULL)[1], "year=2020/results_page_1.parquet")
  expect_equal(rel(NULL)[2], "query=plain/results_page_1.parquet")
  # hive_names wins for its level
  expect_equal(rel("yr")[1], "yr=2020/results_page_1.parquet")
})
