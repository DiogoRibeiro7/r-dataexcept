#' OpenTelemetry attributes for a condition
#'
#' `condition_to_otel_attributes()` describes a condition as OpenTelemetry
#' exception attributes, with the names the Python package's
#' `exception_to_otel_attributes()` uses, so spans from R and Python report
#' failures the same way:
#'
#' * `exception.type`, `exception.message` and, when available,
#'   `exception.stacktrace`: the standard OpenTelemetry exception attributes.
#' * `dataexcept.failure.kind`, `dataexcept.failure.retryable` and
#'   `dataexcept.failure.retry_after_seconds`: the failure metadata, flat and
#'   typed, present only for what the condition's failure record carries.
#' * `dataexcept.operation.*`: the operation context's labels and run
#'   identifiers. `trace_id` and `span_id` are left out, because a span already
#'   carries them natively.
#' * With `include_envelope = TRUE`, `dataexcept.envelope` (the envelope as
#'   compact JSON with sorted keys) and `dataexcept.envelope.schema` (its schema
#'   id).
#'
#' `exception.type` is the envelope's module and type, such as
#' `"dataexcept.MissingColumnError"` or `"base.simpleError"`; for a failure read
#' from a Python envelope it is the Python class's qualified name. The message
#' is the envelope's, redacted. The stack trace is an rlang backtrace when the
#' condition has one, and otherwise the condition's call, which is the only
#' stack information a base R condition carries; either is redacted. A
#' condition with neither, such as one read from an envelope, has no stack
#' trace attribute.
#'
#' This is a pure conversion: invalid input is an error. [record_otel_exception()]
#' is the fail-open version for use while handling a failure.
#'
#' @inheritParams condition_to_event
#' @param include_stacktrace Include `exception.stacktrace` when the condition
#'   has one?
#' @param include_envelope Include the whole envelope as a JSON attribute?
#' @return A named list of attributes, each a single string, logical or number,
#'   ready for `span$record_exception()` or `span$add_event()`.
#' @seealso [record_otel_exception()] to record a condition on a span.
#' @export
#' @examples
#' context <- operation_context(system = "batch", operation = "settle_invoices")
#' err <- with_failure_metadata(
#'   api_error("https://user:pw@api.example.com/v1/invoices", status_code = 503L),
#'   failure_metadata("transient", retryable = TRUE, retry_after_seconds = 30)
#' )
#' str(condition_to_otel_attributes(err, operation_context = context))
condition_to_otel_attributes <- function(cnd,
                                         operation_context = NULL,
                                         include_attributes = TRUE,
                                         max_depth = 8L,
                                         include_stacktrace = TRUE,
                                         include_envelope = FALSE) {
  check_operation_context(operation_context)
  check_flag(include_stacktrace, "include_stacktrace")
  check_flag(include_envelope, "include_envelope")
  envelope <- condition_to_envelope(cnd,
    include_attributes = include_attributes,
    max_depth = max_depth
  )

  attributes <- list(
    exception.type = otel_exception_type(cnd),
    exception.message = envelope$message
  )
  if (include_stacktrace) {
    attributes[["exception.stacktrace"]] <- otel_stacktrace(cnd)
  }
  attributes <- c(
    attributes,
    otel_failure_attributes(envelope$failure),
    otel_operation_attributes(operation_context)
  )
  if (include_envelope) {
    attributes[["dataexcept.envelope.schema"]] <- envelope_schema_id()
    json <- write_json(sort_json_keys(envelope))
    Encoding(json) <- "UTF-8"
    attributes[["dataexcept.envelope"]] <- json
  }
  attributes
}

check_flag <- function(x, arg) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    stop(sprintf("`%s` must be TRUE or FALSE.", arg), call. = FALSE)
  }
  invisible(x)
}

otel_exception_type <- function(cnd) {
  module <- export_text(condition_module(cnd))
  type <- export_text(condition_type(cnd))
  if (identical(module, "unknown")) type else paste0(module, ".", type)
}

otel_stacktrace <- function(cnd) {
  text <- rlang_stack(cnd)
  if (is.null(text)) {
    call <- tryCatch(conditionCall(cnd), error = function(e) NULL)
    if (!is.null(call)) {
      text <- paste(deparse(call, width.cutoff = 500L), collapse = "\n")
    }
  }
  if (is.null(text) || !nzchar(text)) {
    return(NULL)
  }
  export_text(text)
}

otel_failure_attributes <- function(failure) {
  if (is.null(failure)) {
    return(list())
  }
  out <- list(dataexcept.failure.kind = failure$kind)
  if (!is.null(failure$retryable)) {
    out[["dataexcept.failure.retryable"]] <- failure$retryable
  }
  if (!is.null(failure$retry_after_seconds)) {
    out[["dataexcept.failure.retry_after_seconds"]] <- as.double(failure$retry_after_seconds)
  }
  out
}

otel_operation_attributes <- function(context) {
  fields <- unclass(context)[intersect(
    c("system", "component", "operation", "request_id", "job_id", "correlation_id"),
    names(context)
  )]
  if (length(fields) == 0L) {
    return(list())
  }
  names(fields) <- paste0("dataexcept.operation.", names(fields))
  fields
}

#' Record a condition on an OpenTelemetry span
#'
#' `record_otel_exception()` records a condition as an exception event on a
#' span, with the attributes of [condition_to_otel_attributes()]. With no
#' `span`, it records on the active span of the r-lib otel package, when otel
#' is installed and tracing is on.
#'
#' It is meant to be called while a failure is being handled, so it is
#' fail-open: if otel is not installed, no span is recording, the span has no
#' `record_exception()` method, or anything goes wrong converting or recording,
#' it returns `FALSE` and the failure being handled carries on unchanged. Use
#' [condition_to_otel_attributes()] directly when a mistake should be an error.
#'
#' Recording through dataexcept also keeps credentials out of the trace. The
#' otel SDK builds the exception message by printing the condition and falls
#' back to the condition's call for the stack trace, both unredacted; the
#' attributes recorded here replace those fields with redacted ones.
#'
#' With `set_status = TRUE`, the default, the span's status is also set to
#' `"error"`, with the redacted message as its description. That marks the
#' operation as failed, and it matters for redaction: when an error escapes a
#' span that otel ends automatically (one from `otel::start_local_active_span()`,
#' `otel::with_active_span()` or `otel::local_active_span()`), the SDK records
#' it itself, unredacted, unless the span's status is already set. Recording
#' the failure here first means it appears once, redacted. Pass
#' `set_status = FALSE` when the handler recovers from the failure and the
#' operation goes on to succeed.
#'
#' @inheritParams condition_to_otel_attributes
#' @param span The span to record on: any object whose `record_exception()`
#'   method takes the condition and an `attributes` list, as otel's spans do.
#'   `NULL` means otel's active span.
#' @param set_status Also set the span's status to `"error"`, when the span has
#'   a `set_status()` method?
#' @return `TRUE`, invisibly, when the exception was recorded, and `FALSE`
#'   otherwise.
#' @export
#' @examples
#' # A span-like recorder, standing in for an otel span.
#' recorded <- NULL
#' span <- list(record_exception = function(error_condition, attributes = NULL, ...) {
#'   recorded <<- attributes
#' })
#'
#' err <- validation_error("age", -1)
#' record_otel_exception(err, span = span)
#' str(recorded)
#'
#' # With no span, the active otel span is used. With tracing off there is
#' # nothing to record on, and the call does nothing.
#' record_otel_exception(err)
record_otel_exception <- function(cnd,
                                  span = NULL,
                                  operation_context = NULL,
                                  include_attributes = TRUE,
                                  max_depth = 8L,
                                  include_stacktrace = TRUE,
                                  include_envelope = FALSE,
                                  set_status = TRUE) {
  recorded <- tryCatch(
    {
      if (is.null(span)) {
        span <- active_otel_span()
      }
      if (is.null(span) || !span_is_recording(span)) {
        return(invisible(FALSE))
      }
      attributes <- condition_to_otel_attributes(cnd,
        operation_context = operation_context,
        include_attributes = include_attributes,
        max_depth = max_depth,
        include_stacktrace = include_stacktrace,
        include_envelope = include_envelope
      )
      span$record_exception(cnd, attributes = attributes)
      if (isTRUE(set_status) && is.function(span$set_status)) {
        span$set_status("error", description = attributes$exception.message)
      }
      TRUE
    },
    error = function(e) FALSE
  )
  invisible(recorded)
}

active_otel_span <- function() {
  if (!requireNamespace("otel", quietly = TRUE)) {
    return(NULL) # nocov: otel is installed wherever the tests run
  }
  otel::get_active_span()
}

# A span without an is_recording() method is assumed to record.
span_is_recording <- function(span) {
  is_recording <- span$is_recording
  if (!is.function(is_recording)) {
    return(TRUE)
  }
  isTRUE(is_recording())
}

#' Correlate an operation context with the active OpenTelemetry span
#'
#' `operation_context_from_otel()` fills the `trace_id` and `span_id` of an
#' operation context from the active span of the r-lib otel package, so that
#' failure events written to logs with [condition_to_event()] carry the same
#' identifiers as the trace.
#'
#' Nothing is invented. When otel is not installed, tracing is off, or there is
#' no valid active span, the context is returned unchanged. An identifier the
#' context already has must agree with the span's: a conflicting `trace_id` or
#' `span_id` is an error, because silently replacing provenance would make the
#' correlation less trustworthy than omitting it.
#'
#' @param context An operation context to extend, or `NULL` for a new one.
#' @param span_context The span context to read. `NULL` means otel's active
#'   span context.
#' @return An operation context.
#' @export
#' @examples
#' context <- operation_context(system = "batch", operation = "settle_invoices")
#'
#' # With tracing off there is no active span, so nothing is added.
#' operation_context_from_otel(context)
#'
#' # Inside a traced operation, the trace and span identifiers are filled in:
#' # otel::start_local_active_span("settle_invoices")
#' # operation_context_from_otel(context)
operation_context_from_otel <- function(context = NULL, span_context = NULL) {
  check_operation_context(context)
  if (is.null(context)) {
    context <- operation_context()
  }
  if (is.null(span_context)) {
    if (!requireNamespace("otel", quietly = TRUE)) {
      return(context) # nocov: otel is installed wherever the tests run
    }
    span_context <- otel::get_active_span_context()
  }
  if (!isTRUE(span_context$is_valid())) {
    return(context)
  }
  ids <- list(
    trace_id = span_context$get_trace_id(),
    span_id = span_context$get_span_id()
  )
  values <- unclass(context)
  for (field in names(ids)) {
    known <- values[[field]]
    if (!is.null(known) && !identical(known, ids[[field]])) {
      stop(sprintf(
        "The context's %s (%s) conflicts with the active span's (%s).",
        field, known, ids[[field]]
      ), call. = FALSE)
    }
    values[[field]] <- ids[[field]]
  }
  new_operation_context(values)
}
