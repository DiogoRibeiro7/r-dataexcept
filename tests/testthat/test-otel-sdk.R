# End to end against the real OpenTelemetry SDK, recording to memory.

skip_if_not_installed("otel")
skip_if_not_installed("otelsdk")

leaked_url <- "https://user:pw@api.example.com/private?token=t"

leaky_error <- function() {
  simpleError(
    paste("GET", leaked_url, "failed"),
    call = call("download", leaked_url)
  )
}

record_in_span <- function(expr) {
  otelsdk::with_otel_record(what = "traces", {
    span <- otel::start_local_active_span("dataexcept-test")
    value <- force(expr)
    span$end()
    value
  })
}

test_that("a condition is recorded on the active span with redacted attributes", {
  err <- leaky_error()
  recording <- record_in_span(record_otel_exception(err))
  expect_true(recording$value)

  events <- recording$traces[[1]]$events
  expect_length(events, 1L)
  expect_identical(events[[1]]$name, "exception")
  attributes <- unclass(events[[1]]$attributes)
  expect_identical(attributes$exception.type, "base.simpleError")
  expect_identical(
    attributes$exception.message,
    "GET https://***:***@api.example.com/***?token=*** failed"
  )
  expect_identical(
    attributes$exception.stacktrace,
    "download(\"https://***:***@api.example.com/***?token=***\")"
  )
  expect_false(any(grepl("user:pw", unlist(attributes), fixed = TRUE)))
})

test_that("the SDK alone would have recorded the credentials", {
  # The reason record_otel_exception() exists: without dataexcept's
  # attributes, the SDK prints the condition and deparses its call.
  recording <- record_in_span(otel::get_active_span()$record_exception(leaky_error()))
  attributes <- unclass(recording$traces[[1]]$events[[1]]$attributes)
  expect_match(attributes$exception.message, "user:pw", fixed = TRUE)
})

test_that("a failure recorded and re-signalled inside a span appears once, redacted", {
  settle <- function() {
    otel::start_local_active_span("settle")
    tryCatch(stop(leaky_error()), error = function(e) {
      record_otel_exception(e)
      stop(e)
    })
  }
  recording <- otelsdk::with_otel_record(what = "traces", try(settle(), silent = TRUE))
  span <- recording$traces[[1]]
  expect_identical(span$status, "error")
  expect_length(span$events, 1L)
  message <- unclass(span$events[[1]]$attributes)$exception.message
  expect_false(grepl("user:pw", message, fixed = TRUE))
  expect_false(grepl("user:pw", span$description, fixed = TRUE))
})

test_that("without dataexcept, an escaping error is recorded unredacted", {
  settle <- function() {
    otel::start_local_active_span("settle")
    stop(leaky_error())
  }
  recording <- otelsdk::with_otel_record(what = "traces", try(settle(), silent = TRUE))
  message <- unclass(recording$traces[[1]]$events[[1]]$attributes)$exception.message
  expect_match(message, "user:pw", fixed = TRUE)
})

test_that("a recovered failure can be recorded without failing the span", {
  settle <- function() {
    otel::start_local_active_span("settle")
    tryCatch(stop(leaky_error()), error = function(e) {
      record_otel_exception(e, set_status = FALSE)
      "fallback"
    })
  }
  recording <- otelsdk::with_otel_record(what = "traces", settle())
  expect_identical(recording$value, "fallback")
  span <- recording$traces[[1]]
  expect_identical(span$status, "ok")
  expect_length(span$events, 1L)
})

test_that("failure metadata and the operation context reach the span", {
  err <- with_failure_metadata(
    api_error("https://api.example.com/v1", status_code = 503L),
    failure_metadata("transient", retryable = TRUE, retry_after_seconds = 30)
  )
  recording <- record_in_span({
    context <- operation_context_from_otel(operation_context(system = "batch", job_id = "job-1"))
    record_otel_exception(err, operation_context = context)
    context
  })
  span <- recording$traces[[1]]
  attributes <- unclass(span$events[[1]]$attributes)
  expect_identical(attributes$dataexcept.failure.kind, "transient")
  expect_true(attributes$dataexcept.failure.retryable)
  expect_identical(attributes$dataexcept.failure.retry_after_seconds, 30)
  expect_identical(attributes$dataexcept.operation.job_id, "job-1")

  # The context read the same identifiers the span was recorded under.
  context <- recording$value
  expect_identical(context$trace_id, span$trace_id)
  expect_identical(context$span_id, span$span_id)
  expect_false("dataexcept.operation.trace_id" %in% names(attributes))
})
