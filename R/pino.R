#' Write a condition in the shape Pino logs errors
#'
#' A Node.js service that logs with [Pino](https://getpino.io) expects an
#' error under its `err` key with `type`, `message` and, optionally, `stack`
#' -- the fields Pino itself writes for an error, and the ones pino-pretty,
#' transports and error trackers read. `condition_to_pino()` writes a
#' condition in that shape: the Pino profile the Python DataExcept package
#' publishes (`pino-1.0.0.json`, see [pino_schema()]). `envelope_to_pino()`
#' does the same for an envelope already in hand, such as one read from a
#' queue.
#'
#' The profile is a projection of the envelope, not a replacement for it, and
#' it differs from the envelope in three places only:
#'
#' * an exception group's `exceptions` are `errors`, the name JavaScript's
#'   `AggregateError` uses;
#' * `stack` is written only when there is a real stack to write, and never
#'   made up;
#' * `attributes` stay nested, so that an attribute called `type` or `stack`
#'   cannot overwrite the fields a consumer reads.
#'
#' Everything else -- `type`, `module`, `message`, `failure`, the causes,
#' contexts and members, the cycle and truncation markers, and the redaction
#' already applied to the envelope -- is carried through unchanged.
#'
#' In R, the real stack is an rlang backtrace: the one `rlang::abort()`
#' records, or that `rlang::global_entrace()` adds to base R errors. With
#' `include_stack = TRUE` it is written, redacted like every other exported
#' string, and without one `stack` is left out. A call is not a stack, and is
#' not written as one.
#'
#' @inheritParams condition_to_envelope
#' @param include_stack Write the condition's rlang backtrace, when it has
#'   one, as `stack`?
#' @param envelope An envelope: a list from [condition_to_envelope()] or
#'   `jsonlite::parse_json()`, or a JSON string.
#' @param stack A stack received with the envelope, as a single string, or
#'   `NULL`. It is redacted.
#' @return `condition_to_pino()` and `envelope_to_pino()` return the error as a
#'   list (JSON objects as named lists, arrays as unnamed lists, `null` as
#'   `NULL`). `condition_to_pino_json()` returns a single string of JSON.
#' @seealso [condition_to_envelope()] for the envelope itself, which stays the
#'   canonical record.
#' @export
#' @examples
#' cnd <- tryCatch(
#'   stop(condition_group(list(
#'     missing_column_error("customer_id", dataframe = "orders"),
#'     validation_error("amount", -5)
#'   ), "orders failed validation")),
#'   error = identity
#' )
#' cat(condition_to_pino_json(cnd, pretty = TRUE))
#'
#' # A Pino log line, for a log stream a Node.js service reads.
#' line <- sprintf(
#'   '{"level":50,"time":%.0f,"msg":"ingest failed","err":%s}',
#'   as.numeric(Sys.time()) * 1000,
#'   condition_to_pino_json(cnd)
#' )
#'
#' # An envelope received as JSON.
#' json <- condition_to_json(api_error("https://api.example.com/v1", status_code = 503L))
#' str(envelope_to_pino(json))
condition_to_pino <- function(cnd, include_attributes = TRUE, max_depth = 8L,
                              include_stack = FALSE) {
  if (!is_flag(include_stack)) {
    stop("`include_stack` must be TRUE or FALSE.", call. = FALSE)
  }
  envelope <- condition_to_envelope(cnd,
    include_attributes = include_attributes,
    max_depth = max_depth
  )
  envelope_to_pino(envelope, stack = if (include_stack) rlang_stack(cnd) else NULL)
}

#' @rdname condition_to_pino
#' @export
condition_to_pino_json <- function(cnd, include_attributes = TRUE, max_depth = 8L,
                                   include_stack = FALSE, pretty = FALSE) {
  record <- condition_to_pino(cnd,
    include_attributes = include_attributes,
    max_depth = max_depth,
    include_stack = include_stack
  )
  json <- write_json(record, pretty = isTRUE(pretty))
  Encoding(json) <- "UTF-8"
  json
}

#' @rdname condition_to_pino
#' @export
envelope_to_pino <- function(envelope, stack = NULL) {
  check_string(stack, "stack", allow_null = TRUE)
  if (is.character(envelope)) {
    envelope <- parse_envelope(envelope, pino_max_depth)
  }
  if (!is_json_object(envelope)) {
    stop("`envelope` must be an envelope: a JSON object, as a string or a named list.",
      call. = FALSE
    )
  }
  record <- pino_node(envelope, depth = 0L)
  if (is.null(stack)) {
    return(record)
  }
  with_pino_stack(record, export_text(stack))
}

# Envelope fields carried through under the same name, in the order the
# Python projection writes them; then the nested nodes.
pino_carried <- c("type", "module", "message", "attributes", "failure", "cycle", "truncated")
pino_nested <- c("cause", "context")

# A depth bound of the projection's own, as in Python: an envelope that
# arrived from elsewhere may be deeper than any writer would make it.
pino_max_depth <- 32L

pino_node <- function(node, depth) {
  if (depth > pino_max_depth) {
    return(list(truncated = TRUE))
  }
  record <- node[intersect(pino_carried, names(node))]
  for (field in pino_nested) {
    if (is_json_object(node[[field]])) {
      record[[field]] <- pino_node(node[[field]], depth + 1L)
    }
  }
  members <- node[["exceptions"]]
  if (is_json_array(members)) {
    members <- Filter(is_json_object, members)
    record$errors <- unname(lapply(members, pino_node, depth = depth + 1L))
  }
  record
}

# The record with `stack` after `message`. A cycle record or a truncation
# marker stands in for an error rather than being one, so it gets no stack.
with_pino_stack <- function(record, stack) {
  if (!"message" %in% names(record) || any(c("cycle", "truncated") %in% names(record))) {
    return(record)
  }
  at <- match("message", names(record))
  c(record[seq_len(at)], list(stack = stack), record[-seq_len(at)])
}

# The condition's rlang backtrace as text, or NULL when it has none.
rlang_stack <- function(cnd) {
  if (!inherits(cnd$trace, "rlang_trace") || !requireNamespace("rlang", quietly = TRUE)) {
    return(NULL)
  }
  format_backtrace(cnd$trace)
}

is_flag <- function(x) {
  is.logical(x) && length(x) == 1L && !is.na(x)
}

#' The Pino profile JSON Schema
#'
#' The Pino profile is the shape [condition_to_pino()] writes: the DataExcept
#' envelope projected onto the error Pino logs. Its JSON Schema,
#' `pino-1.0.0.json`, is published by the Python DataExcept package and ships
#' with this one, together with the Python package's projection of each
#' reference envelope fixture, under `schema/fixtures/pino/`. The test suite
#' requires [envelope_to_pino()] to reproduce every one of them.
#'
#' @return The schema as a list.
#' @seealso [envelope_schema()] for the envelope's own schema.
#' @export
#' @examples
#' pino_schema()$`$id`
#' names(pino_schema()$`$defs`)
#'
#' # The file itself, for a JSON Schema validator:
#' system.file("schema", "pino-1.0.0.json", package = "dataexcept")
pino_schema <- function() {
  path <- system.file("schema", "pino-1.0.0.json", package = "dataexcept", mustWork = TRUE)
  jsonlite::read_json(path, simplifyVector = FALSE)
}
