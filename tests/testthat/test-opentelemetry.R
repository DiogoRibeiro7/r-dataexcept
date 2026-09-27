# A span-like recorder with otel's record_exception() contract.
recorder <- function(recording = TRUE) {
  env <- new.env()
  env$is_recording <- function() recording
  env$record_exception <- function(error_condition, attributes = NULL, ...) {
    env$condition <- error_condition
    env$attributes <- attributes
    invisible(env)
  }
  env$set_status <- function(status_code, description = NULL) {
    env$status <- list(code = status_code, description = description)
    invisible(env)
  }
  env
}

test_that("standard exception attributes come from the redacted envelope", {
  err <- validation_error("https://user:secret@example.com/private?token=hidden", -1)
  attributes <- condition_to_otel_attributes(err, include_stacktrace = FALSE)
  expect_identical(attributes$exception.type, "dataexcept.ValidationError")
  expect_false(grepl("secret|hidden|private", attributes$exception.message))
  expect_identical(attributes$exception.message, condition_to_envelope(err)$message)
})

test_that("exception.type names the module where it is known", {
  type <- function(cnd) condition_to_otel_attributes(cnd)$exception.type
  expect_identical(type(simpleError("x")), "base.simpleError")
  expect_identical(type(errorCondition("x", class = "myapp_error")), "myapp_error")
  skip_if_not_installed("rlang")
  expect_identical(type(tryCatch(rlang::abort("x"), error = identity)), "rlang.rlang_error")
})

test_that("failure metadata is flat and typed", {
  attributes <- condition_to_otel_attributes(validation_error("age", -1))
  expect_identical(attributes$dataexcept.failure.kind, "permanent")
  expect_false(attributes$dataexcept.failure.retryable)
  expect_false("dataexcept.failure.retry_after_seconds" %in% names(attributes))

  err <- with_failure_metadata(
    api_error("https://h"),
    failure_metadata("transient", TRUE, 2L)
  )
  attributes <- condition_to_otel_attributes(err)
  expect_true(attributes$dataexcept.failure.retryable)
  expect_identical(attributes$dataexcept.failure.retry_after_seconds, 2)

  attributes <- condition_to_otel_attributes(api_error("https://h"))
  expect_identical(attributes$dataexcept.failure.kind, "unknown")
  optional <- c("dataexcept.failure.retryable", "dataexcept.failure.retry_after_seconds")
  expect_false(any(optional %in% names(attributes)))

  third_party <- names(condition_to_otel_attributes(simpleError("x")))
  expect_false(any(startsWith(third_party, "dataexcept.")))
})

test_that("operation attributes leave out the trace identifiers", {
  context <- operation_context(
    system = "worker", operation = "settle", job_id = "job-1",
    trace_id = "4bf92f3577b34da6a3ce929d0e0e4736", span_id = "00f067aa0ba902b7"
  )
  attributes <- condition_to_otel_attributes(simpleError("x"), operation_context = context)
  operation <- attributes[startsWith(names(attributes), "dataexcept.operation.")]
  expect_identical(operation, list(
    dataexcept.operation.system = "worker",
    dataexcept.operation.operation = "settle",
    dataexcept.operation.job_id = "job-1"
  ))
})

test_that("the stack trace is the redacted call or backtrace, when there is one", {
  expect_false("exception.stacktrace" %in% names(condition_to_otel_attributes(simpleError("x"))))

  f <- function() {
    stop(simpleError("x", call = quote(download.file("https://u:pw@h/secret/file"))))
  }
  err <- tryCatch(f(), error = identity)
  attributes <- condition_to_otel_attributes(err)
  expect_identical(attributes$exception.stacktrace, "download.file(\"https://***:***@h/***\")")
  without <- condition_to_otel_attributes(err, include_stacktrace = FALSE)
  expect_false("exception.stacktrace" %in% names(without))

  skip_if_not_installed("rlang")
  err <- tryCatch(rlang::abort("boom at https://u:pw@h/secret"), error = identity)
  trace <- condition_to_otel_attributes(err)$exception.stacktrace
  expect_match(trace, "rlang::abort", fixed = TRUE)
  expect_false(grepl("pw|secret", trace))
})

test_that("the optional envelope is compact, key-sorted JSON with its schema id", {
  err <- validation_error("age", -1, parent = simpleError("root"))
  attributes <- condition_to_otel_attributes(err,
    include_stacktrace = FALSE, include_envelope = TRUE
  )
  expect_identical(attributes$dataexcept.envelope.schema, envelope_schema_id())
  json <- attributes$dataexcept.envelope
  expect_false(grepl("\n", json, fixed = TRUE))
  expect_true(is_envelope(json))
  back <- jsonlite::parse_json(json, simplifyVector = FALSE)
  expect_identical(names(back), sort(names(back)))
  expect_identical(names(back$failure), sort(names(back$failure)))
  expect_equal(back, sort_json_keys(condition_to_envelope(err)))
})

test_that("every attribute is a single string, logical or number", {
  context <- operation_context(system = "s", job_id = "j")
  err <- with_failure_metadata(
    api_error("https://h"),
    failure_metadata("transient", TRUE, 1.5)
  )
  attributes <- condition_to_otel_attributes(err,
    operation_context = context, include_envelope = TRUE
  )
  for (name in names(attributes)) {
    value <- attributes[[name]]
    expect_length(value, 1L)
    expect_true(is.character(value) || is.logical(value) || is.numeric(value), info = name)
  }
})

test_that("attribute conversion is strict", {
  expect_error(condition_to_otel_attributes("boom"), "condition object")
  expect_error(
    condition_to_otel_attributes(simpleError("x"), operation_context = list()),
    "operation_context"
  )
  x <- simpleError("x")
  expect_error(condition_to_otel_attributes(x, include_envelope = NA), "TRUE or FALSE")
  expect_error(condition_to_otel_attributes(x, include_stacktrace = "yes"), "TRUE or FALSE")
})

test_that("attributes match the Python package's for the same failure and context", {
  for (case in parity_cases()) {
    cnd <- envelope_to_condition(case$event$exception)
    attributes <- condition_to_otel_attributes(cnd,
      operation_context = case_context(case),
      include_stacktrace = FALSE,
      include_envelope = TRUE
    )
    expected <- case$otel
    expect_setequal(names(attributes), names(expected))
    for (name in setdiff(names(expected), "dataexcept.envelope")) {
      expect_equal(attributes[[name]], expected[[name]], info = paste(case$name, name))
    }
    # The same document, compared parsed: Python writes 30.0 where R writes 30.
    expect_equal(
      jsonlite::parse_json(attributes$dataexcept.envelope, simplifyVector = FALSE),
      jsonlite::parse_json(expected$dataexcept.envelope, simplifyVector = FALSE),
      info = case$name
    )
  }
})

test_that("recording passes the condition and its attributes to the span", {
  span <- recorder()
  err <- validation_error("age", -1)
  expect_true(record_otel_exception(err, span = span, include_stacktrace = FALSE))
  expect_identical(span$condition, err)
  expect_identical(span$attributes, condition_to_otel_attributes(err, include_stacktrace = FALSE))

  context <- operation_context(job_id = "job-9")
  record_otel_exception(err, span = span, operation_context = context, include_envelope = TRUE)
  expect_identical(span$attributes$dataexcept.operation.job_id, "job-9")
  expect_true("dataexcept.envelope" %in% names(span$attributes))
})

test_that("recording sets an error status with the redacted message", {
  span <- recorder()
  err <- simpleError("GET https://user:pw@h/private failed")
  record_otel_exception(err, span = span)
  expect_identical(span$status, list(
    code = "error",
    description = "GET https://***:***@h/*** failed"
  ))

  span <- recorder()
  record_otel_exception(err, span = span, set_status = FALSE)
  expect_null(span$status)
  expect_identical(span$condition, err)
})

test_that("recording returns its result invisibly", {
  expect_invisible(record_otel_exception(simpleError("x"), span = recorder()))
})

test_that("recording skips a span that is not recording", {
  span <- recorder(recording = FALSE)
  expect_false(record_otel_exception(simpleError("x"), span = span))
  expect_null(span$condition)
})

test_that("recording accepts a span without is_recording()", {
  seen <- NULL
  span <- list(record_exception = function(error_condition, attributes = NULL, ...) {
    seen <<- attributes
  })
  expect_true(record_otel_exception(simpleError("x"), span = span))
  expect_identical(seen$exception.type, "base.simpleError")
})

test_that("recording is fail-open", {
  failing <- list(record_exception = function(...) stop("telemetry backend unavailable"))
  expect_false(record_otel_exception(simpleError("x"), span = failing))
  expect_false(record_otel_exception(simpleError("x"), span = list()))
  expect_false(record_otel_exception(simpleError("x"), span = 42))

  span <- recorder()
  expect_false(record_otel_exception(simpleError("x"), span = span, operation_context = "bad"))
  expect_null(span$condition)
  expect_false(record_otel_exception("not a condition", span = span))
})

test_that("recording through the SDK's merge replaces the unredacted fields", {
  # otelsdk builds its own exception attributes from the printed condition and
  # the call, then overlays the attributes it is given with modifyList().
  err <- simpleError(
    "GET https://user:pw@h/private failed",
    call = quote(get("https://user:pw@h/private"))
  )
  sdk_defaults <- list(
    exception.message = paste(utils::capture.output(err), collapse = "\n"),
    exception.stacktrace = format(conditionCall(err)),
    exception.type = class(err)
  )
  expect_match(sdk_defaults$exception.message, "user:pw", fixed = TRUE)
  merged <- utils::modifyList(sdk_defaults, condition_to_otel_attributes(err))
  expect_false(any(grepl("user:pw|private", unlist(merged))))
  expect_identical(merged$exception.type, "base.simpleError")
})

test_that("with no span, the active otel span is used", {
  skip_if_not_installed("otel")
  # Without an SDK, otel's active span is a no-op span that is not recording.
  expect_false(otel::get_active_span()$is_recording())
  expect_false(record_otel_exception(simpleError("x")))
})

test_that("with no span and no otel, nothing is recorded", {
  local_mocked_bindings(active_otel_span = function() NULL)
  expect_false(record_otel_exception(simpleError("x")))
})

# A span-context-like object with otel's methods.
span_context <- function(valid = TRUE,
                         trace_id = "4bf92f3577b34da6a3ce929d0e0e4736",
                         span_id = "00f067aa0ba902b7") {
  list(
    is_valid = function() valid,
    get_trace_id = function() trace_id,
    get_span_id = function() span_id
  )
}

test_that("a valid span context fills the trace identifiers", {
  context <- operation_context(system = "batch", operation = "settle")
  filled <- operation_context_from_otel(context, span_context = span_context())
  expect_s3_class(filled, "dataexcept_operation_context")
  expect_identical(filled$trace_id, "4bf92f3577b34da6a3ce929d0e0e4736")
  expect_identical(filled$span_id, "00f067aa0ba902b7")
  expect_identical(filled$system, "batch")

  fresh <- operation_context_from_otel(span_context = span_context())
  expect_named(fresh, c("trace_id", "span_id"))
})

test_that("an invalid span context adds nothing", {
  context <- operation_context(system = "batch")
  invalid <- span_context(valid = FALSE)
  expect_identical(operation_context_from_otel(context, span_context = invalid), context)
  expect_length(operation_context_from_otel(span_context = invalid), 0L)
})

test_that("identifiers that agree are kept and conflicting ones are an error", {
  agreeing <- operation_context(trace_id = "4bf92f3577b34da6a3ce929d0e0e4736")
  expect_identical(
    operation_context_from_otel(agreeing, span_context = span_context())$trace_id,
    "4bf92f3577b34da6a3ce929d0e0e4736"
  )
  active <- span_context()
  expect_error(
    operation_context_from_otel(operation_context(trace_id = "other"), span_context = active),
    "trace_id \\(other\\) conflicts"
  )
  expect_error(
    operation_context_from_otel(operation_context(span_id = "other"), span_context = active),
    "span_id \\(other\\) conflicts"
  )
  expect_error(operation_context_from_otel(list()), "operation_context")
})

test_that("with no span context, otel's active one is read", {
  skip_if_not_installed("otel")
  context <- operation_context(system = "batch")
  # Tracing is off without an SDK, so the active span context is invalid.
  expect_identical(operation_context_from_otel(context), context)
})
