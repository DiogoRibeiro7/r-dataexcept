pino_fixture <- function(name) {
  path <- system.file("schema", "fixtures", "pino", name,
    package = "dataexcept", mustWork = TRUE
  )
  jsonlite::read_json(path, simplifyVector = FALSE)
}

fixture_names <- function() {
  dir <- system.file("schema", "fixtures", "pino", package = "dataexcept", mustWork = TRUE)
  list.files(dir, pattern = "\\.json$")
}

test_that("every published envelope fixture has its Pino projection", {
  envelopes <- list.files(
    system.file("schema", "fixtures", package = "dataexcept"),
    pattern = "\\.json$"
  )
  expect_setequal(fixture_names(), envelopes)
  expect_length(fixture_names(), 8L)
})

for (name in fixture_names()) {
  test_that(sprintf("the projection of %s matches Python's", name), {
    expected <- pino_fixture(name)
    # From the envelope as text, and as a parsed list.
    expect_identical(envelope_to_pino(fixture(name)), expected)
    expect_identical(envelope_to_pino(jsonlite::parse_json(fixture(name))), expected)
    # From the condition read back from it, written again by R.
    cnd <- envelope_to_condition(fixture(name))
    expect_equal(jsonlite::parse_json(condition_to_pino_json(cnd)), expected)
  })
}

test_that("the projection keeps the Python key order", {
  record <- envelope_to_pino(fixture("failure-metadata.json"))
  expect_identical(names(record), c("type", "module", "message", "attributes", "failure"))
})

test_that("a condition is projected by way of its envelope", {
  cnd <- tryCatch(
    stop(file_read_error("orders.csv", parent = simpleError("disk unavailable"))),
    error = identity
  )
  record <- condition_to_pino(cnd)
  expect_identical(record$type, "FileReadError")
  expect_identical(record$module, "dataexcept")
  expect_identical(record$cause$message, "disk unavailable")
  expect_identical(record$failure$kind, "unknown")
  expect_null(record$stack)
  expect_identical(record$attributes, list(path = "orders.csv"))

  expect_null(condition_to_pino(cnd, include_attributes = FALSE)$attributes)
})

test_that("group members become errors, recursively", {
  group <- condition_group(list(
    condition_group(list(simpleError("bad row"), simpleError("bad column")), "rows"),
    simpleError("disk unavailable")
  ), "import")
  record <- condition_to_pino(group)
  expect_null(record$exceptions)
  expect_length(record$errors, 2L)
  expect_length(record$errors[[1]]$errors, 2L)
  expect_identical(record$errors[[1]]$errors[[2]]$message, "bad column")
})

test_that("an empty group keeps an empty errors array", {
  json <- '{"type": "G", "module": "m", "message": "none", "exceptions": []}'
  record <- envelope_to_pino(json)
  expect_identical(record$errors, list())
  expect_match(write_json(record), '"errors":[]', fixed = TRUE)
})

test_that("attributes stay nested, whatever they are called", {
  cnd <- new_dataexcept_error("x",
    type = "OwnError", class = "own_error",
    stack = "attribute", message_id = 7L
  )
  record <- condition_to_pino(cnd)
  expect_identical(record$attributes$stack, "attribute")
  expect_null(record$stack)
  expect_identical(record$message, "x")
})

test_that("a stack is written after the message when one is given", {
  record <- envelope_to_pino(fixture("ordinary-exception.json"),
    stack = "Error: boom\n    at https://user:pw@h.example.com/x?token=t"
  )
  expect_identical(names(record)[1:4], c("type", "module", "message", "stack"))
  expect_no_match(record$stack, "pw|token=t")
  expect_match(record$stack, "Error: boom", fixed = TRUE)
})

test_that("markers never get a stack", {
  expect_identical(
    envelope_to_pino('{"truncated": true}', stack = "s"),
    list(truncated = TRUE)
  )
  cycle <- '{"type": "E", "module": "m", "message": "x", "cycle": true}'
  expect_null(envelope_to_pino(cycle, stack = "s")$stack)
})

test_that("an rlang backtrace is the stack, and a call is not", {
  skip_if_not_installed("rlang")
  inner <- function() rlang::abort("deep failure", class = "own_error")
  outer <- function() inner()
  cnd <- tryCatch(outer(), error = identity)
  record <- condition_to_pino(cnd, include_stack = TRUE)
  expect_type(record$stack, "character")
  expect_match(record$stack, "inner()", fixed = TRUE)
  expect_identical(names(record)[4L], "stack")
  expect_null(condition_to_pino(cnd)$stack)

  f <- function() stop("base error")
  base <- tryCatch(f(), error = identity)
  expect_false(is.null(conditionCall(base)))
  expect_null(condition_to_pino(base, include_stack = TRUE)$stack)
})

test_that("a backtrace is written without terminal colours", {
  skip_if_not_installed("rlang")
  skip_if_not_installed("cli")
  old <- options(cli.num_colors = 256L)
  on.exit(options(old), add = TRUE)
  cnd <- tryCatch((function() rlang::abort("boom"))(), error = identity)
  stack <- condition_to_pino(cnd, include_stack = TRUE)$stack
  expect_false(grepl("\033", stack, fixed = TRUE))
  expect_identical(getOption("cli.num_colors"), 256L)
})

test_that("a backtrace that cannot be formatted is left out", {
  skip_if_not_installed("rlang")
  cnd <- simpleError("x")
  cnd$trace <- structure(list(), class = "rlang_trace")
  expect_null(condition_to_pino(cnd, include_stack = TRUE)$stack)
})

test_that("a backtrace is redacted like every other exported string", {
  skip_if_not_installed("rlang")
  fetch <- function(url) rlang::abort("fetch failed")
  cnd <- tryCatch(fetch("https://user:secret@api.example.com/v1?token=abc"), error = identity)
  stack <- condition_to_pino(cnd, include_stack = TRUE)$stack
  expect_no_match(stack, "secret|abc")
})

test_that("unknown fields are dropped and malformed children skipped", {
  envelope <- list(
    type = "E", module = "m", message = "x",
    future_field = 1,
    cause = "not a node",
    context = list(type = "C", module = "m", message = "c"),
    exceptions = list(list(type = "M", module = "m", message = "member"), 1, "x")
  )
  record <- envelope_to_pino(envelope)
  expect_named(record, c("type", "module", "message", "context", "errors"))
  expect_length(record$errors, 1L)
})

test_that("the projection has a depth bound of its own", {
  node <- list(type = "E", module = "m", message = "leaf")
  for (i in 1:40) node <- list(type = "E", module = "m", message = "x", cause = node)
  record <- envelope_to_pino(node)
  depth <- 0L
  while (!is.null(record$cause)) {
    record <- record$cause
    depth <- depth + 1L
  }
  expect_identical(depth, 33L)
  expect_identical(record, list(truncated = TRUE))
})

test_that("the JSON form is strict and marked as UTF-8", {
  name <- paste0("Zo", intToUtf8(235L))
  cnd <- validation_error("name", name)
  json <- condition_to_pino_json(cnd)
  expect_identical(Encoding(json), "UTF-8")
  expect_identical(jsonlite::parse_json(json)$attributes$value, name)
  expect_match(condition_to_pino_json(cnd, pretty = TRUE), "\n  \"type\"", fixed = TRUE)
})

test_that("the Pino functions check their arguments", {
  expect_error(envelope_to_pino("[1, 2]"), "must be an envelope")
  expect_error(envelope_to_pino(1), "must be an envelope")
  expect_error(envelope_to_pino("{not json"), class = "dataexcept_envelope_error")
  expect_error(envelope_to_pino(list(type = "E"), stack = 1), "`stack` must be a single string")
  expect_error(condition_to_pino(simpleError("x"), include_stack = NA), "TRUE or FALSE")
  expect_error(condition_to_pino("x"), "condition object")
})

test_that("the schema ships with the package", {
  schema <- pino_schema()
  expect_identical(
    schema$`$id`,
    "https://diogoribeiro7.github.io/DataExcept/schema/pino-1.0.0.json"
  )
  expect_setequal(
    names(schema$`$defs`),
    c(
      "node", "truncationMarker", "cycleRecord", "errorRecord",
      "errorType", "errorModule", "errorMessage"
    )
  )
})
