operation_fields <- c(
  "system", "component", "operation",
  "request_id", "job_id", "correlation_id",
  "trace_id", "span_id"
)

index_fields <- c("system", "component", "operation")

#' Describe where an operation is running
#'
#' An operation context records where a failure happened, separately from what
#' failed. It is the R counterpart of the Python package's `OperationContext`,
#' with the same fields and the same rules, so a failure event from an R job
#' and one from a Python service can be filtered and correlated together.
#'
#' The fields fall into two groups:
#'
#' * `system`, `component` and `operation` are labels. They should stay
#'   low-cardinality -- a route template such as `"POST /users/{id}"`, a job
#'   name, a workflow step -- so they are safe to filter and group by.
#'   `operation_index_fields()` returns only these.
#' * `request_id`, `job_id`, `correlation_id`, `trace_id` and `span_id`
#'   identify one run. They are for correlating a specific execution and
#'   should not become metric dimensions or indexed tags.
#'
#' Every field is optional: a missing identifier stays missing rather than
#' being invented. URLs in any field lose their credentials and their path.
#'
#' @param system,component,operation Low-cardinality labels: the system, the
#'   component within it, and the operation being performed.
#' @param request_id,job_id,correlation_id Identifiers of this run.
#' @param trace_id,span_id Trace identifiers. To fill them from the active
#'   OpenTelemetry span, use [operation_context_from_otel()].
#' @param context An operation context.
#' @return `operation_context()` returns an object of class
#'   `dataexcept_operation_context`: a named list holding only the fields that
#'   were given, in the order above. `operation_index_fields()` returns the
#'   same with only the label fields.
#' @seealso [condition_to_event()], which pairs a context with a condition.
#' @export
#' @examples
#' context <- operation_context(
#'   system = "batch",
#'   component = "billing",
#'   operation = "settle_invoices",
#'   job_id = "job-42"
#' )
#' context
#' operation_index_fields(context)
operation_context <- function(system = NULL,
                              component = NULL,
                              operation = NULL,
                              request_id = NULL,
                              job_id = NULL,
                              correlation_id = NULL,
                              trace_id = NULL,
                              span_id = NULL) {
  values <- list(
    system = system, component = component, operation = operation,
    request_id = request_id, job_id = job_id, correlation_id = correlation_id,
    trace_id = trace_id, span_id = span_id
  )
  new_operation_context(values)
}

new_operation_context <- function(values) {
  out <- list()
  for (field in operation_fields) {
    value <- values[[field]]
    if (is.null(value)) {
      next
    }
    if (!is_string(value)) {
      stop(sprintf("`%s` must be a single string or NULL.", field), call. = FALSE)
    }
    if (!nzchar(trimws(value))) {
      stop(sprintf("`%s` must not be empty.", field), call. = FALSE)
    }
    out[[field]] <- redact_urls_in_text(value, keep_path = FALSE)
  }
  structure(out, class = "dataexcept_operation_context")
}

check_operation_context <- function(context) {
  if (!is.null(context) && !inherits(context, "dataexcept_operation_context")) {
    stop("`operation_context` must be created by operation_context() or be NULL.",
      call. = FALSE
    )
  }
  invisible(context)
}

#' @rdname operation_context
#' @export
operation_index_fields <- function(context) {
  check_operation_context(context)
  if (is.null(context)) {
    stop("`context` must be created by operation_context().", call. = FALSE)
  }
  unclass(context)[intersect(index_fields, names(context))]
}

#' @export
format.dataexcept_operation_context <- function(x, ...) {
  fields <- unclass(x)
  if (length(fields) == 0L) {
    return("<operation_context: empty>")
  }
  width <- max(nchar(names(fields)))
  c(
    "<operation_context>",
    sprintf("  %-*s  %s", width, names(fields), unlist(fields, use.names = FALSE))
  )
}

#' @export
print.dataexcept_operation_context <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
  invisible(x)
}

#' A failure event for logs and observability tools
#'
#' `condition_to_event()` pairs the envelope of a condition with the operation
#' context it happened in, in the event format the Python package's
#' `exception_to_observability_event()` produces:
#'
#' ```json
#' {"event": "exception", "exception": {...envelope...}, "operation": {...}}
#' ```
#'
#' The envelope stays exactly as [condition_to_envelope()] writes it, redacted
#' and with its chain of causes. The operation context sits under its own key
#' instead of being flattened into the failure, so a log pipeline can index the
#' label fields and keep the run identifiers for correlation. With no context,
#' or an empty one, there is no `operation` key: nothing is invented.
#'
#' `condition_to_event_json()` writes the event as one line of strict JSON,
#' ready for a JSON-lines log.
#'
#' @inheritParams condition_to_envelope
#' @param operation_context An operation context from [operation_context()],
#'   or `NULL`.
#' @return `condition_to_event()` returns the event as a list;
#'   `condition_to_event_json()` returns it as a single JSON string.
#' @export
#' @examples
#' context <- operation_context(
#'   system = "batch", operation = "load_orders", job_id = "job-42"
#' )
#' err <- tryCatch(
#'   stop(missing_column_error("customer_id", dataframe = "orders")),
#'   error = identity
#' )
#' cat(condition_to_event_json(err, operation_context = context, pretty = TRUE))
#'
#' # Log every failure of a job as one JSON line.
#' log_file <- tempfile(fileext = ".jsonl")
#' tryCatch(
#'   stop(validation_error("age", -1)),
#'   dataexcept_error = function(e) {
#'     cat(condition_to_event_json(e, operation_context = context), "\n",
#'       file = log_file, append = TRUE, sep = ""
#'     )
#'   }
#' )
#' readLines(log_file)
condition_to_event <- function(cnd,
                               operation_context = NULL,
                               include_attributes = TRUE,
                               max_depth = 8L) {
  check_operation_context(operation_context)
  event <- list(
    event = "exception",
    exception = condition_to_envelope(cnd,
      include_attributes = include_attributes,
      max_depth = max_depth
    )
  )
  if (length(operation_context) > 0L) {
    event$operation <- unclass(operation_context)
  }
  event
}

#' @rdname condition_to_event
#' @export
condition_to_event_json <- function(cnd,
                                    operation_context = NULL,
                                    include_attributes = TRUE,
                                    max_depth = 8L,
                                    pretty = FALSE) {
  event <- condition_to_event(cnd,
    operation_context = operation_context,
    include_attributes = include_attributes,
    max_depth = max_depth
  )
  json <- write_json(event, pretty = isTRUE(pretty))
  Encoding(json) <- "UTF-8"
  json
}
