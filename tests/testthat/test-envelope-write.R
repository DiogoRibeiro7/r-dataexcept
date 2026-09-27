fixture_dir <- function() {
  system.file("schema", "fixtures", package = "dataexcept", mustWork = TRUE)
}

read_text <- function(path) {
  paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
}

parse <- function(json) jsonlite::parse_json(json, simplifyVector = FALSE)

test_that("a dataexcept error is written with identity, failure and attributes", {
  env <- condition_to_envelope(missing_column_error("customer_id", dataframe = "orders"))
  expect_identical(names(env), c("type", "module", "message", "failure", "attributes"))
  expect_identical(env$type, "MissingColumnError")
  expect_identical(env$module, "dataexcept")
  expect_identical(
    env$failure,
    list(kind = "unknown", retryable = NULL, retry_after_seconds = NULL)
  )
  expect_identical(env$attributes, list(column = "customer_id", dataframe = "orders"))
})

test_that("key order matches the Python serializer", {
  cnd <- validation_error("a", 1, parent = simpleError("root"))
  expect_identical(
    names(condition_to_envelope(cnd)),
    c("type", "module", "message", "failure", "attributes", "cause")
  )
})

test_that("condition_type() names the envelope type", {
  expect_identical(condition_type(missing_column_error("x")), "MissingColumnError")
  expect_identical(condition_type(simpleError("x")), "simpleError")
  expect_error(condition_type("x"), "condition object")
})

test_that("unclassified conditions have no failure record", {
  env <- condition_to_envelope(simpleError("boom"))
  expect_identical(env, list(type = "simpleError", module = "base", message = "boom"))
  expect_identical(condition_to_envelope(simpleWarning("w"))$module, "base")
  expect_identical(condition_to_envelope(simpleMessage("hello\n"))$message, "hello")

  custom <- errorCondition("custom", class = "my_error", detail = 3)
  env <- condition_to_envelope(custom)
  expect_identical(env$type, "my_error")
  expect_identical(env$module, "unknown")
  expect_identical(env$attributes, list(detail = 3))
})

test_that("rlang conditions are written without their machinery", {
  skip_if_not_installed("rlang")
  cnd <- tryCatch(
    rlang::abort("rlang boom", class = "myapp_error", detail = 1L, parent = simpleError("root")),
    error = identity
  )
  env <- condition_to_envelope(cnd)
  expect_identical(env$type, "myapp_error")
  expect_identical(env$message, "rlang boom")
  expect_identical(env$attributes, list(detail = 1L))
  expect_identical(env$cause$message, "root")

  env <- condition_to_envelope(tryCatch(rlang::abort("x"), error = identity))
  expect_identical(env$module, "rlang")
})

test_that("values degrade to a description rather than disappearing", {
  cnd <- new_dataexcept_error("x",
    nan = NaN, pos_inf = Inf, neg_inf = -Inf, na = NA, na_real = NA_real_,
    vec = c(1, NA, 3), long = seq_len(1000), df = data.frame(a = 1:3),
    mat = matrix(1:4, 2), fun = mean, env = globalenv(),
    date = as.Date("2026-09-27"),
    time = as.POSIXct("2026-09-27 10:00:00", tz = "UTC"),
    fac = factor(c("a", "b")), named = c(a = 1, b = 2),
    empty = character(), nested = list(a = list(b = 1)),
    type = "X", class = "x_error"
  )
  attrs <- condition_to_envelope(cnd)$attributes
  expect_identical(attrs$nan, "nan")
  expect_identical(attrs$pos_inf, "inf")
  expect_identical(attrs$neg_inf, "-inf")
  expect_null(attrs$na)
  expect_true("na" %in% names(attrs))
  expect_null(attrs$na_real)
  expect_identical(attrs$vec, list(1, NULL, 3))
  expect_identical(attrs$long, "<integer vector of length 1000>")
  expect_identical(attrs$df, "<data.frame: 3 rows x 1 columns>")
  expect_identical(attrs$mat, "<matrix: 2 x 2 integer>")
  expect_identical(attrs$fun, "<function>")
  expect_identical(attrs$env, "<environment>")
  expect_identical(attrs$date, "2026-09-27")
  expect_identical(attrs$time, "2026-09-27T10:00:00Z")
  expect_identical(attrs$fac, list("a", "b"))
  expect_identical(attrs$named, list(a = 1, b = 2))
  expect_identical(attrs$empty, list())
  expect_identical(attrs$nested, list(a = list(b = 1)))
})

test_that("I() writes a length-one vector as an array", {
  cnd <- dtype_mismatch_error("amount", "numeric", "character")
  expect_true("numeric" %in% cnd$expected)
  attrs <- condition_to_envelope(cnd)$attributes
  expect_identical(attrs$expected, list("numeric"))
  expect_identical(attrs$found, "character")

  attrs <- condition_to_envelope(merge_key_error("id", "id"))$attributes
  expect_identical(attrs$left_keys, list("id"))

  cnd <- new_dataexcept_error("x", tags = I("a"), n = I(1L), type = "X", class = "x_error")
  attrs <- condition_to_envelope(cnd)$attributes
  expect_identical(attrs$tags, list("a"))
  expect_identical(attrs$n, list(1L))
})

test_that("deeply nested values are truncated", {
  deep <- list(1)
  for (i in 1:10) deep <- list(deep)
  attrs <- condition_to_envelope(new_dataexcept_error("x", deep = deep))$attributes
  json <- write_json(attrs)
  expect_match(json, "<truncated>", fixed = TRUE)
})

test_that("private and machinery fields are not attributes", {
  cnd <- errorCondition("x", class = "my_error", .hidden = 1, visible = 2)
  cnd[["_private"]] <- 3
  expect_identical(condition_to_envelope(cnd)$attributes, list(visible = 2))
})

test_that("include_attributes = FALSE omits attributes", {
  env <- condition_to_envelope(validation_error("a", 1), include_attributes = FALSE)
  expect_false("attributes" %in% names(env))
  expect_true("failure" %in% names(env))
})

test_that("a chain beyond max_depth ends in the truncation marker", {
  cnd <- validation_error("a", 1,
    parent = validation_error("b", 2, parent = simpleError("root"))
  )
  env <- condition_to_envelope(cnd, max_depth = 1L)
  expect_identical(env$cause$cause, list(truncated = TRUE))
  env <- condition_to_envelope(cnd, max_depth = 0L)
  expect_identical(env$cause, list(truncated = TRUE))
  expect_error(condition_to_envelope(cnd, max_depth = -1), "non-negative")
})

test_that("text is redacted on the way out, including paths", {
  cnd <- simpleError("GET https://user:pw@h.example.com/private/path?token=t failed")
  env <- condition_to_envelope(cnd)
  expect_identical(env$message, "GET https://***:***@h.example.com/***?token=*** failed")

  cnd <- errorCondition("x", class = "e", url = "https://h/secret-path")
  expect_identical(condition_to_envelope(cnd)$attributes$url, "https://h/***")
})

test_that("JSON output is strict and numbers round-trip", {
  cnd <- new_dataexcept_error("x",
    a = 0.1 + 0.2, b = 1 / 3, c = 1e-20, d = 30,
    e = -0.5, f = 123456789012, g = 2^60, h = 5L, s = "quote \" and \\ and \n",
    type = "X", class = "x_error"
  )
  json <- condition_to_json(cnd)
  expect_false(grepl("NaN|Infinity", json))
  back <- parse(json)$attributes
  expect_identical(back$a, 0.1 + 0.2)
  expect_identical(back$b, 1 / 3)
  expect_identical(back$c, 1e-20)
  expect_equal(back$d, 30)
  expect_identical(back$e, -0.5)
  expect_equal(back$f, 123456789012)
  expect_equal(back$g, 2^60)
  expect_identical(back$s, "quote \" and \\ and \n")
  expect_match(json, "\"a\":0.30000000000000004", fixed = TRUE)
})

test_that("control characters and non-ASCII text survive", {
  # Built with intToUtf8() so the string is UTF-8 in every locale, including C.
  msg <- paste0("tab\there ", intToUtf8(233), " ", intToUtf8(10003), " ", intToUtf8(1))
  json <- condition_to_json(simpleError(msg))
  expect_true(validUTF8(json))
  expect_match(json, "\\u0001", fixed = TRUE)
  back <- parse(json)
  expect_identical(charToRaw(back$message), charToRaw(enc2utf8(msg)))
})

test_that("pretty printing produces the same document", {
  cnd <- validation_error("a", list(x = 1, y = list()), parent = simpleError("root"))
  expect_identical(
    parse(condition_to_json(cnd, pretty = TRUE)),
    parse(condition_to_json(cnd))
  )
  expect_match(condition_to_json(cnd, pretty = TRUE), "\n  \"module\": ", fixed = TRUE)
})

test_that("every Python reference fixture round-trips exactly", {
  files <- list.files(fixture_dir(), pattern = "\\.json$", full.names = TRUE)
  expect_length(files, 8L)
  for (path in files) {
    json <- read_text(path)
    cnd <- envelope_to_condition(json)
    expect_equal(parse(condition_to_json(cnd)), parse(json), info = basename(path))
  }
})

test_that("R envelopes round-trip through the reader", {
  cnd <- with_failure_metadata(
    api_error("https://h/v1?api_key=x",
      status_code = 503L,
      parent = simpleError("connection reset")
    ),
    failure_metadata("transient", TRUE, 2.5)
  )
  json <- condition_to_json(cnd)
  expect_identical(condition_to_json(envelope_to_condition(json)), json)
})
