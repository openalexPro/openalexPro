## helpers ------------------------------------------------------------------

# Build a minimal fake httr2 response
fake_response <- function(status, body_raw = NULL, body_text = NULL,
                          content_type = "application/octet-stream") {
  headers <- list(`Content-Type` = content_type)
  if (!is.null(body_raw)) {
    httr2::response(status_code = status, headers = headers, body = body_raw)
  } else {
    httr2::response(status_code = status, headers = headers,
                    body = charToRaw(body_text %||% ""))
  }
}

# Minimal NULL-coalesce for test helper
`%||%` <- function(x, y) if (is.null(x)) y else x

## tests --------------------------------------------------------------------

testthat::test_that("pro_download_content downloads a PDF successfully", {
  out_dir <- withr::local_tempdir()
  fake_pdf <- as.raw(c(0x25, 0x50, 0x44, 0x46))  # %PDF magic bytes

  httr2::with_mocked_responses(
    function(req) httr2::response(200L,
      headers = list(`Content-Type` = "application/pdf"),
      body    = fake_pdf),
    {
      result <- pro_download_content(
        ids    = "W2741809807",
        format = "pdf",
        output = out_dir,
        api_key = "test-key"
      )
    }
  )

  testthat::expect_equal(nrow(result), 1L)
  testthat::expect_equal(result$status, "ok")
  testthat::expect_equal(result$id, "W2741809807")
  testthat::expect_true(file.exists(result$file))
  testthat::expect_equal(readBin(result$file, "raw", 4L), fake_pdf)
})

testthat::test_that("pro_download_content downloads grobid-xml successfully", {
  out_dir <- withr::local_tempdir()
  tei_body <- '<?xml version="1.0"?><TEI><text>hello</text></TEI>'

  httr2::with_mocked_responses(
    function(req) httr2::response(200L,
      headers = list(`Content-Type` = "application/xml"),
      body    = charToRaw(tei_body)),
    {
      result <- pro_download_content(
        ids    = "W2741809807",
        format = "grobid-xml",
        output = out_dir,
        api_key = "test-key"
      )
    }
  )

  testthat::expect_equal(result$status, "ok")
  saved <- paste(readLines(result$file, warn = FALSE), collapse = "\n")
  testthat::expect_true(grepl("TEI", saved))
})

testthat::test_that("pro_download_content returns not_found for 404", {
  out_dir <- withr::local_tempdir()

  httr2::with_mocked_responses(
    function(req) httr2::response(404L,
      headers = list(`Content-Type` = "text/plain"),
      body    = charToRaw("Not found")),
    {
      result <- pro_download_content(
        ids    = "W9999999999",
        format = "pdf",
        output = out_dir,
        api_key = "test-key"
      )
    }
  )

  testthat::expect_equal(result$status, "not_found")
  testthat::expect_true(is.na(result$file))
  testthat::expect_equal(length(list.files(out_dir)), 0L)
})

testthat::test_that("pro_download_content normalises full OpenAlex URLs", {
  out_dir <- withr::local_tempdir()
  fake_pdf <- as.raw(c(0x25, 0x50, 0x44, 0x46))

  httr2::with_mocked_responses(
    function(req) httr2::response(200L,
      headers = list(`Content-Type` = "application/pdf"),
      body    = fake_pdf),
    {
      result <- pro_download_content(
        ids    = "https://openalex.org/W2741809807",
        format = "pdf",
        output = out_dir,
        api_key = "test-key"
      )
    }
  )

  testthat::expect_equal(result$id, "W2741809807")
  testthat::expect_equal(result$status, "ok")
  testthat::expect_true(grepl("W2741809807\\.pdf$", result$file))
})

testthat::test_that("pro_download_content handles multiple IDs", {
  out_dir <- withr::local_tempdir()
  fake_pdf <- as.raw(c(0x25, 0x50, 0x44, 0x46))
  ids <- c("W1111111111", "W2222222222", "W3333333333")

  httr2::with_mocked_responses(
    function(req) httr2::response(200L,
      headers = list(`Content-Type` = "application/pdf"),
      body    = fake_pdf),
    {
      result <- pro_download_content(
        ids    = ids,
        format = "pdf",
        output = out_dir,
        api_key = "test-key"
      )
    }
  )

  testthat::expect_equal(nrow(result), 3L)
  testthat::expect_true(all(result$status == "ok"))
  testthat::expect_equal(length(list.files(out_dir, pattern = "\\.pdf$")), 3L)
})

testthat::test_that("pro_download_content works without api_key and omits api_key query param", {
  out_dir <- withr::local_tempdir()
  captured_url <- NULL
  fake_pdf <- as.raw(c(0x25, 0x50, 0x44, 0x46))

  withr::with_envvar(c(openalexPro.api_key = ""), {
    httr2::with_mocked_responses(
      function(req) {
        captured_url <<- req$url
        httr2::response(200L,
          headers = list(`Content-Type` = "application/pdf"),
          body = fake_pdf)
      },
      {
        result <- pro_download_content(
          ids = "W123",
          format = "pdf",
          output = out_dir,
          api_key = ""
        )
      }
    )
  })

  testthat::expect_equal(result$status, "ok")
  testthat::expect_false(grepl("api_key=", captured_url))
})

testthat::test_that("pro_download_content URL includes api_key query param", {
  out_dir <- withr::local_tempdir()
  captured_url <- NULL

  httr2::with_mocked_responses(
    function(req) {
      captured_url <<- req$url
      httr2::response(200L,
        headers = list(`Content-Type` = "application/pdf"),
        body    = as.raw(c(0x25, 0x50, 0x44, 0x46)))
    },
    {
      pro_download_content(
        ids     = "W123",
        format  = "pdf",
        output  = out_dir,
        api_key = "my-secret-key"
      )
    }
  )

  testthat::expect_true(grepl("api_key=my-secret-key", captured_url))
  testthat::expect_true(grepl("content\\.openalex\\.org/works/W123\\.pdf", captured_url))
})
