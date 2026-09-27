test_that("an operation context keeps the given fields in a fixed order", {
  context <- operation_context(
    span_id = "span-13", system = "payments", job_id = "job-7",
    component = "worker", operation = "settle_invoice", request_id = "req-42",
    correlation_id = "corr-9", trace_id = "trace-11"
  )
  expect_s3_class(context, "dataexcept_operation_context")
  expect_named(context, c(
    "system", "component", "operation", "request_id", "job_id",
    "correlation_id", "trace_id", "span_id"
  ))
  expect_identical(
    operation_index_fields(context),
    list(system = "payments", component = "worker", operation = "settle_invoice")
  )
  expect_length(operation_context(), 0L)
  expect_identical(
    operation_index_fields(operation_context(job_id = "j")),
    setNames(list(), character())
  )
})

test_that("an operation context redacts URLs, including their paths", {
  context <- operation_context(
    system = "https://user:secret@example.com/private?token=hidden"
  )
  expect_identical(context$system, "https://***:***@example.com/***?token=***")
})

test_that("an operation context rejects empty and non-string values", {
  expect_error(operation_context(operation = "   "), "`operation` must not be empty")
  expect_error(
    operation_context(request_id = 42),
    "`request_id` must be a single string or NULL"
  )
  expect_error(operation_context(system = c("a", "b")), "single string")
  expect_error(operation_context(system = NA_character_), "single string")
  expect_error(operation_index_fields(list(system = "x")), "operation_context")
  expect_error(operation_index_fields(NULL), "operation_context")
})

test_that("an operation context prints its fields", {
  expect_output(
    print(operation_context(system = "batch", job_id = "j-1")),
    "system  batch"
  )
  expect_output(print(operation_context()), "<operation_context: empty>")
})

test_that("an event pairs the envelope with the operation context", {
  context <- operation_context(
    system = "api", operation = "create_customer", request_id = "req-42"
  )
  event <- condition_to_event(validation_error("age", -1), operation_context = context)
  expect_named(event, c("event", "exception", "operation"))
  expect_identical(event$event, "exception")
  expect_identical(event$exception, condition_to_envelope(validation_error("age", -1)))
  expect_identical(
    event$operation,
    list(system = "api", operation = "create_customer", request_id = "req-42")
  )
})

test_that("an event invents no operation context", {
  expect_named(condition_to_event(simpleError("x")), c("event", "exception"))
  expect_named(
    condition_to_event(simpleError("x"), operation_context = operation_context()),
    c("event", "exception")
  )
})

test_that("an event validates its context and passes options to the envelope", {
  expect_error(
    condition_to_event(simpleError("x"), operation_context = list(operation = "bad")),
    "operation_context"
  )
  expect_error(condition_to_event("boom"), "condition object")
  event <- condition_to_event(validation_error("a", 1), include_attributes = FALSE)
  expect_false("attributes" %in% names(event$exception))
  deep <- validation_error("a", 1, parent = validation_error("b", 2))
  expect_identical(
    condition_to_event(deep, max_depth = 0L)$exception$cause,
    list(truncated = TRUE)
  )
})

test_that("event JSON is strict, one line, and valid", {
  context <- operation_context(system = "batch", job_id = "job-1")
  json <- condition_to_event_json(missing_column_error("id"), operation_context = context)
  expect_false(grepl("\n", json, fixed = TRUE))
  back <- jsonlite::parse_json(json, simplifyVector = FALSE)
  expect_identical(back$operation, list(system = "batch", job_id = "job-1"))
  expect_true(is_envelope(back$exception))
  pretty <- condition_to_event_json(simpleError("x"), pretty = TRUE)
  expect_match(pretty, "\n  \"event\": ", fixed = TRUE)
})

test_that("events match the Python package's for the same failure and context", {
  cases <- parity_cases()
  expect_gte(length(cases), 5L)
  for (case in cases) {
    cnd <- envelope_to_condition(case$event$exception)
    event <- condition_to_event(cnd, operation_context = case_context(case))
    expect_equal(event, case$event, info = case$name)
  }
})
