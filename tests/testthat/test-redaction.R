test_that("redaction matches the Python package exactly", {
  path <- test_path("fixtures", "redaction-parity.json")
  cases <- jsonlite::read_json(path, simplifyVector = FALSE)
  expect_gt(length(cases), 20L)
  for (case in cases) {
    input <- case$case
    expect_identical(redact_url(input), case$url, info = input)
    expect_identical(redact_url(input, keep_path = FALSE), case$url_nopath, info = input)
    expect_identical(redact_urls_in_text(input), case$text, info = input)
    expect_identical(redact_urls_in_text(input, keep_path = FALSE), case$text_nopath, info = input)
  }
})

test_that("a URL without credentials is returned exactly as given", {
  url <- "https://example.com/data?page=2&sort=desc"
  expect_identical(redact_url(url), url)
  expect_identical(redact_url("sqlite://"), "sqlite://")
})

test_that("non-URLs are returned unchanged", {
  expect_identical(redact_url("/local/path.csv"), "/local/path.csv")
  expect_identical(redact_url(""), "")
  expect_null(redact_url(NULL))
  expect_identical(redact_url(NA_character_), NA_character_)
  expect_identical(redact_urls_in_text("plain text"), "plain text")
  expect_identical(redact_urls_in_text(NA_character_), NA_character_)
  expect_null(redact_urls_in_text(NULL))
})

test_that("parameter names are matched by token, not by substring", {
  expect_true(is_sensitive_name("accessToken"))
  expect_true(is_sensitive_name("X-Amz-Signature"))
  expect_true(is_sensitive_name("API_KEY"))
  expect_true(is_sensitive_name("apiKey"))
  expect_false(is_sensitive_name("keyword"))
  expect_false(is_sensitive_name("monkey"))
  expect_false(is_sensitive_name("authors"))
  expect_false(is_sensitive_name("code"))
})
