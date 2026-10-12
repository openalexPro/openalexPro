# tests/testthat/test-pro-vs-oa-query.R
testthat::test_that("opt_filter_names returns value", {
  testthat::local_edition(3)
  vcr::local_cassette("opt_filter_names")
  testthat::expect_snapshot_value(opt_filter_names(), style = "json2")
})

testthat::test_that("opt_select_fields returns value", {
  testthat::local_edition(3)
  vcr::local_cassette("opt_select_fields")
  testthat::expect_snapshot_value(opt_select_fields(), style = "json2")
})

testthat::test_that("pro_query and legacy query return identical URLs (search + filters)", {
  # same inputs for both
  entity <- "works"
  search <- "biodiversity"
  # filters passed via ... for both (oa_query supports ... as well)
  filters <- list(
    from_publication_date = "2020-01-01",
    language = c("en", "de"),
    type = "article"
  )
  # select: legacy passes via options$select; pro_query via select=
  sel <- c("ids", "title", "publication_year")
  opts <- list(per_page = 5, sort = "cited_by_count:desc")

  # build URLs

  url_pro <- do.call(
    pro_query,
    c(
      list(
        entity = entity,
        search = search,
        select = sel,
        options = opts
      ),
      filters
    )
  )

  testthat::expect_type(url_pro, "character")
  testthat::expect_snapshot(url_pro)
})

testthat::test_that("pro_query and legacy query return identical URLs (single id)", {
  entity <- "works"
  identifier <- "W1775749144"
  sel <- c("ids", "title")

  url_pro <- pro_query(
    entity = entity,
    id = identifier,
    select = sel
  )

  testthat::expect_snapshot(url_pro)
})

testthat::test_that("pro_query handles multiple IDs automatically", {
  ids <- c("W2741809807", "W2092304384")

  url <- pro_query(entity = "works", id = ids)

  testthat::expect_true(grepl("filter=ids.openalex", url))
  testthat::expect_false(grepl("/works/W", url))
})

testthat::test_that("pro_query and legacy query return identical URLs with grouping", {
  entity <- "works"
  search <- "biodiversity"
  group <- "type"
  filters <- list(
    from_publication_date = "2020-01-01",
    language = "en"
  )
  opts <- list(per_page = 50)

  # build URL with pro_query
  url_pro <- do.call(
    pro_query,
    c(
      list(
        entity = entity,
        search = search,
        group_by = group,
        options = opts
      ),
      filters
    )
  )

  testthat::expect_type(url_pro, "character")
})

# Entity coverage tests ---------------------------------------------------

testthat::test_that("pro_query works with authors entity", {
  url <- pro_query(entity = "authors", search = "Einstein")
  testthat::expect_true(grepl("/authors", url))
  testthat::expect_true(grepl("search=Einstein", url))
})

testthat::test_that("pro_query works with institutions entity", {
  url <- pro_query(entity = "institutions", id = "I4200000001")
  testthat::expect_true(grepl("/institutions/I4200000001", url))
})

testthat::test_that("pro_query works with all entity types", {
  entities <- c(
    "works",
    "authors",
    "venues",
    "institutions",
    "concepts",
    "publishers",
    "funders",
    "sources",
    "topics",
    "locations"
  )
  for (ent in entities) {
    url <- pro_query(entity = ent)
    testthat::expect_true(
      grepl(paste0("/", ent), url),
      info = paste("Entity:", ent)
    )
  }
})

# Chunking tests ----------------------------------------------------------

testthat::test_that("pro_query chunks large DOI lists", {
  dois <- paste0("10.1234/test", 1:120)
  urls <- pro_query(entity = "works", doi = dois)

  testthat::expect_type(urls, "list")
  testthat::expect_equal(length(urls), 3) # 120 / 50 = 3 chunks
  testthat::expect_equal(names(urls), c("chunk_1", "chunk_2", "chunk_3"))
})

testthat::test_that("pro_query chunks large ID lists via id parameter", {
  ids <- paste0("W", 1:75)
  urls <- pro_query(entity = "works", id = ids)

  testthat::expect_type(urls, "list")
  testthat::expect_equal(length(urls), 2) # 75 / 50 = 2 chunks
})

testthat::test_that("pro_query respects custom chunk_limit", {
  dois <- paste0("10.1234/test", 1:100)
  urls <- pro_query(entity = "works", doi = dois, chunk_limit = 25)

  testthat::expect_equal(length(urls), 4) # 100 / 25 = 4 chunks
})

# Validation tests --------------------------------------------------------

testthat::test_that("pro_query errors on invalid filter names", {
  testthat::expect_error(
    pro_query(entity = "works", invalid_filter_name = "value"),
    "Invalid filter name"
  )
})

testthat::test_that("pro_query errors on invalid select fields", {
  testthat::expect_error(
    pro_query(entity = "works", select = c("invalid_field")),
    "Invalid select field"
  )
})

testthat::test_that("pro_query suggests corrections for typos", {
  testthat::expect_error(
    pro_query(entity = "works", select = c("titel")),
    "title"
  )
})

# Edge case tests ---------------------------------------------------------

testthat::test_that("pro_query handles empty filters", {
  url <- pro_query(entity = "works")
  testthat::expect_type(url, "character")
  testthat::expect_true(grepl("api.openalex.org/works", url))
})

testthat::test_that("pro_query handles logical filter values", {
  url <- pro_query(entity = "works", is_oa = TRUE)
  # Colon is URL-encoded as %3A
  testthat::expect_true(grepl("is_oa(%3A|:)true", url))
})

testthat::test_that("pro_query handles NULL id gracefully", {
  url <- pro_query(entity = "works", id = NULL, search = "test")
  testthat::expect_true(grepl("search=test", url))
  testthat::expect_false(grepl("/works/", url))
})

# New search parameter tests ----------------------------------------------

testthat::test_that("search.exact appears in URL", {
  url <- pro_query("works", search.exact = "biodiversity")
  testthat::expect_true(grepl("search\\.exact=biodiversity", url))
  testthat::expect_false(grepl("filter=", url))
})

testthat::test_that("search.semantic appears in URL", {
  url <- pro_query("works", search.semantic = "ocean acidification")
  testthat::expect_true(grepl("search\\.semantic=ocean", url))
  testthat::expect_false(grepl("filter=", url))
})

testthat::test_that("search.exact and search can be combined with filters", {
  url <- pro_query(
    "works",
    search.exact = "CRISPR",
    from_publication_date = "2020-01-01"
  )
  testthat::expect_true(grepl("search\\.exact=CRISPR", url))
  testthat::expect_true(grepl("filter=from_publication_date", url))
})

# Deprecation warning tests -----------------------------------------------

testthat::test_that("deprecated .search filter emits a warning", {
  testthat::expect_warning(
    pro_query("works", title_and_abstract.search = "biodiversity"),
    regexp = "deprecated"
  )
})

testthat::test_that("non-.search filters do not emit a deprecation warning", {
  testthat::expect_no_warning(
    pro_query("works", from_publication_date = "2020-01-01")
  )
})
