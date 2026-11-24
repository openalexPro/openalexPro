library(testthat)

# Recorded with vcr; the /query endpoint is free.

test_that("pro_translate() translates OQL and a classic URL", {
  skip_on_cran()
  vcr::local_cassette("pro_translate")
  oql <- "get works where type is [erratum](erratum)"
  tr <- pro_translate(list(oql = oql))
  expect_true(all(c("oqo", "oql", "oql_oneline", "oxurl", "validation") %in% names(tr)))
  expect_equal(tr$oqo$get_rows, "works")
  expect_true(isTRUE(tr$validation$valid))

  from_url <- pro_translate(list(oxurl = "/works?filter=type:erratum"))
  expect_equal(from_url$oql_oneline, tr$oql_oneline)

  from_oqo <- pro_translate(list(oqo = tr$oqo))
  expect_equal(from_oqo$oql_oneline, tr$oql_oneline)
})

test_that("pro_translate() stops with OpenAlex's validation messages", {
  skip_on_cran()
  vcr::local_cassette("pro_translate_invalid")
  expect_error(
    pro_translate(list(oxurl = "/works?filter=no_such_filter:1")),
    "could not translate"
  )
})

test_that("pro_translate() checks `body` before any request", {
  expect_error(pro_translate("get works"), "exactly one of")
  expect_error(pro_translate(list(oql = "x", oxurl = "/works")), "exactly one of")
  expect_error(pro_translate(list(query = "x")), "exactly one of")
})
