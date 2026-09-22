test_that("extract_doi handles all `what` values correctly", {
  x <- c(
    "https://doi.org/10.5281/zenodo.1234567",
    "http://dx.doi.org/10.1000/XYZ123",
    "10.1234/example.doi",
    "This is a sentence without a DOI.",
    NA
  )

  # Expected outputs
  expected_doi <- c(
    "10.5281/zenodo.1234567",
    "10.1000/xyz123",
    "10.1234/example.doi",
    "", # fallback
    "" # fallback
  )

  expected_prefix <- c("10.5281", "10.1000", "10.1234", "", "")
  expected_resolver <- c("https://doi.org/", "http://dx.doi.org/", "", "", "")
  expected_suffix <- c("zenodo.1234567", "xyz123", "example.doi", "", "")

  # Test: full DOI extraction (default)
  expect_equal(
    extract_doi(x),
    expected_doi
  )

  # Test: prefix extraction
  expect_equal(
    extract_doi(x, what = "prefix"),
    expected_prefix
  )

  # Test: resolver extraction
  expect_equal(
    extract_doi(x, what = "resolver"),
    expected_resolver
  )

  # Test: suffix extraction
  expect_equal(
    extract_doi(x, what = "suffix"),
    expected_suffix
  )

  # Test: normalize = FALSE
  expect_equal(
    extract_doi(x, what = "doi", normalize = FALSE),
    c("10.5281/zenodo.1234567", "10.1000/XYZ123", "10.1234/example.doi", "", "")
  )

  # Test: non_doi_value = NA_character_
  expect_equal(
    extract_doi(x, non_doi_value = NA_character_),
    c("10.5281/zenodo.1234567", "10.1000/xyz123", "10.1234/example.doi", NA, NA)
  )

  # Test: non_doi_value = NULL
  expect_equal(
    extract_doi(x, non_doi_value = NULL),
    c("10.5281/zenodo.1234567", "10.1000/xyz123", "10.1234/example.doi")
  )

  # Test: non_doi_value = NULL
  expect_equal(
    extract_doi(x, what = "resolver", non_doi_value = NULL),
    c("https://doi.org/", "http://dx.doi.org/")
  )

  # Test: non_doi_value = NULL
  expect_equal(
    extract_doi(x, non_doi_value = "", normalize = TRUE),
    expected_doi
  )
})

test_that("extract_doi preserves names across output modes", {
  x <- c(
    first = "https://doi.org/10.5281/zenodo.1234567",
    second = "no doi here",
    third = NA_character_
  )

  aligned_out <- extract_doi(x)
  expect_identical(names(aligned_out), names(x))
  expect_identical(aligned_out[["first"]], "10.5281/zenodo.1234567")
  expect_identical(aligned_out[["second"]], "")
  expect_identical(aligned_out[["third"]], "")

  aligned_na <- extract_doi(x, non_doi_value = NA_character_)
  expect_identical(names(aligned_na), names(x))
  expect_identical(aligned_na[["first"]], "10.5281/zenodo.1234567")
  expect_true(is.na(aligned_na[["second"]]))
  expect_true(is.na(aligned_na[["third"]]))

  matched_only <- extract_doi(x, non_doi_value = NULL)
  expect_identical(names(matched_only), c("first"))
  expect_identical(matched_only[["first"]], "10.5281/zenodo.1234567")
})

test_that("extract_doi() preserves SICI-style DOIs containing < > [ ]", {
  # Regression: the character class used to exclude < > [ ], so the match
  # stopped at the first < and returned a TRUNCATED string that still looked
  # like a valid DOI -- silent corruption rather than a visible failure.
  # ~0.4% of OpenAlex works carry such DOIs.
  sici <- c(
    "10.1175/1520-0450(1963)002<0713:ooasds>2.0.co;2",
    "10.1002/(sici)1098-2418(199608/09)9:1/2<177::aid-rsa11>3.0.co;2-l",
    "10.1577/1548-8659(1973)35[142:amosss]2.0.co;2"
  )
  expect_identical(unname(extract_doi(sici, what = "doi")), sici)

  # and with a resolver prefix
  expect_identical(
    unname(extract_doi(paste0("https://doi.org/", sici), what = "doi")),
    sici
  )
})

test_that("extract_doi() still rejects strings that are not DOIs", {
  expect_identical(unname(extract_doi("not a doi", what = "doi")), "")
  expect_identical(unname(extract_doi("", what = "doi")), "")
  expect_identical(unname(extract_doi(NA, what = "doi")), "")
})

test_that("extract_doi() suffix and prefix handle SICI DOIs", {
  sici <- "10.1175/1520-0450(1963)002<0713:ooasds>2.0.co;2"
  expect_identical(unname(extract_doi(sici, what = "prefix")), "10.1175")
  expect_identical(unname(extract_doi(sici, what = "suffix")),
                   "1520-0450(1963)002<0713:ooasds>2.0.co;2")
})
