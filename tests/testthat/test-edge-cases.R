test_that("numbers are written in the fewest digits that read back exactly", {
  cases <- c(20 / 21, 5 / 7, 0.1 + 0.2, 1e15 + 0.5, 1e-7, 123.456, 1 / 3, 2 / 3, pi, exp(1))
  expected <- c(
    "0.9523809523809523", "0.7142857142857143", "0.30000000000000004",
    "1000000000000000.5", "1e-07", "123.456", "0.3333333333333333",
    "0.6666666666666666", "3.141592653589793", "2.718281828459045"
  )
  expect_identical(vapply(cases, shortest_number, character(1)), expected)
  expect_identical(vapply(cases, json_number, character(1)), expected)
  expect_identical(vapply(cases, format_number, character(1)), expected)
})

test_that("invalid UTF-8 in a message still produces valid JSON", {
  msg <- rawToChar(as.raw(c(0x62, 0x61, 0x64, 0x20, 0xff, 0xfe)))
  json <- condition_to_json(simpleError(msg))
  expect_true(validUTF8(json))
  expect_true(is_envelope(json))
})

test_that("objects JSON cannot hold are described by their class", {
  setClass("DataexceptTestS4", representation(x = "numeric"), where = environment())
  cnd <- new_dataexcept_error("x",
    s4 = new("DataexceptTestS4", x = 1),
    elapsed = as.difftime(5, units = "secs"),
    arr = array(1:8, c(2, 2, 2)),
    type = "X", class = "x_error"
  )
  attrs <- condition_to_envelope(cnd)$attributes
  expect_identical(attrs$s4, "<S4 object of class DataexceptTestS4>")
  expect_identical(attrs$elapsed, "<object of class difftime>")
  expect_identical(attrs$arr, "<array: 2 x 2 x 2 integer>")
})

test_that("a condition stored as a field is written as its message", {
  cnd <- new_dataexcept_error("x",
    original = simpleError("disk unavailable at https://u:p@h/x"),
    type = "X", class = "x_error"
  )
  expect_identical(
    condition_to_envelope(cnd)$attributes$original,
    "disk unavailable at https://***:***@h/***"
  )
})

test_that("empty lists are written as [] and empty named lists as {}", {
  cnd <- new_dataexcept_error("x",
    arr = list(), obj = structure(list(), names = character()),
    partly = list(a = 1, 2),
    type = "X", class = "x_error"
  )
  json <- condition_to_json(cnd)
  expect_match(json, '"arr":[]', fixed = TRUE)
  expect_match(json, '"obj":{}', fixed = TRUE)
  expect_match(json, '"partly":[1,2]', fixed = TRUE)
})

test_that("long values are shortened in default messages", {
  msg <- conditionMessage(validation_error("f", strrep("x", 200)))
  expect_lt(nchar(msg), 100L)
  expect_match(msg, "...", fixed = TRUE)
})

test_that("a condition whose message has several lines is written as one string", {
  cnd <- structure(
    class = c("multi_line", "condition"),
    list(message = c("first", "second"), call = NULL)
  )
  expect_identical(condition_to_envelope(cnd)$message, "first\nsecond")
})

test_that("include_attributes must be a single logical", {
  expect_error(condition_to_envelope(simpleError("x"), include_attributes = NA), "TRUE or FALSE")
  expect_error(condition_to_envelope(simpleError("x"), include_attributes = "yes"), "TRUE or FALSE")
})

test_that("a dataexcept error whose metadata was removed writes the unknown record", {
  cnd <- validation_error("a", 1)
  cnd$.dataexcept$failure <- NULL
  expect_identical(
    condition_to_envelope(cnd)$failure,
    list(kind = "unknown", retryable = NULL, retry_after_seconds = NULL)
  )
})

test_that("a warning that is already classed passes through unchanged", {
  classed <- classify_warning(simpleWarning("NaNs produced"))
  seen <- NULL
  withCallingHandlers(
    with_classed_warnings(warning(classed)),
    warning = function(w) {
      seen <<- w
      invokeRestart("muffleWarning")
    }
  )
  expect_identical(seen, classed)
})

test_that("redaction handles degenerate input", {
  expect_identical(name_tokens("---"), character())
  expect_identical(redact_url("https://h/p?&&"), "https://h/p?&&")
  no_url <- "scheme:// with nothing after"
  expect_identical(redact_urls_in_text(no_url), no_url)
})

test_that("a JSON scalar is not an envelope", {
  expect_false(is_envelope('"just a string"'))
  expect_identical(json_nesting('"no brackets"'), 0L)
})

test_that("invalid UTF-8 is replaced when a condition is built", {
  msg <- rawToChar(as.raw(c(0x62, 0x61, 0x64, 0x20, 0xff)))
  expect_no_warning(cnd <- validation_error("f", 1, message = msg))
  # The replacement depends on the locale ("?" in UTF-8, "<ff>" in C); what
  # matters is that the result is valid.
  expect_true(validUTF8(conditionMessage(cnd)))
  expect_match(conditionMessage(cnd), "^bad ")
  expect_true(validUTF8(condition_to_json(cnd)))
})
