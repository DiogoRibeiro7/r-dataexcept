#' Read a DataExcept envelope back into an R condition
#'
#' `envelope_to_condition()` turns an envelope -- written by this package or
#' by the Python DataExcept package, or by any producer that follows the
#' published schema -- into an R condition that can be inspected, handled or
#' re-signalled.
#'
#' The condition always has class `dataexcept_remote_condition`, plus `error`
#' (or `warning`, for a warning written by this package) and `condition`. When
#' the envelope names a dataexcept type, the condition also gets that type's R
#' classes, whichever language wrote it: a Python `MissingColumnError` becomes
#' a `dataexcept_missing_column_error`, so an R handler written for local
#' failures catches remote ones too. A type from a DataExcept module that R has
#' no class for, such as Python's `ServiceTimeoutError`, is still a
#' `dataexcept_error`, since every DataExcept exception derives from
#' `DataExceptError`; [condition_type()] gives its type.
#'
#' The envelope's attributes become fields (`cnd$column`), except any that
#' would collide with `message`, `call` or `parent`. Its `cause` becomes
#' `parent`, so the chain can be walked and printed as usual.
#'
#' Written back with [condition_to_envelope()], a condition read here
#' reproduces the envelope it came from, including its attributes, failure
#' record, context, group members and cycle and truncation markers.
#'
#' @param x An envelope: a JSON string, or a list as returned by
#'   [condition_to_envelope()] or `jsonlite::parse_json()`.
#' @return A condition object.
#' @seealso [validate_envelope()], which this function applies first.
#' @export
#' @examples
#' json <- '{
#'   "type": "MissingColumnError",
#'   "module": "dataexcept.pandas_exceptions",
#'   "message": "Missing required column \'customer_id\'",
#'   "failure": {"kind": "unknown", "retryable": null, "retry_after_seconds": null},
#'   "attributes": {"column": "customer_id", "dataframe": null}
#' }'
#' cnd <- envelope_to_condition(json)
#' class(cnd)
#' cnd$column
#'
#' tryCatch(stop(cnd), dataexcept_data_frame_error = function(e) "caught")
envelope_to_condition <- function(x) {
  node <- parse_envelope(x)
  problems <- envelope_problems(node, "$")
  if (length(problems) > 0L) {
    stop(envelope_error(problems))
  }
  node_to_condition(node)
}

#' Check that a payload is a valid envelope
#'
#' `validate_envelope()` checks a payload against the rules of the envelope
#' schema ([envelope_schema()]): each node is exactly one of an exception
#' record, a cycle record or a truncation marker; identity fields are strings;
#' a failure record carries all three of its fields with valid values; and the
#' two markers carry nothing beyond their own fields. Fields the schema does
#' not know are accepted, because a newer producer may add them.
#'
#' The check is structural and needs no JSON Schema validator. It is the
#' check `envelope_to_condition()` applies before reading.
#'
#' @inheritParams envelope_to_condition
#' @return `validate_envelope()` returns `x` invisibly when it is valid and
#'   signals a `dataexcept_envelope_error` listing every problem otherwise.
#'   `is_envelope()` returns `TRUE` or `FALSE`.
#' @export
#' @examples
#' is_envelope('{"type": "ValueError", "module": "builtins", "message": "bad row"}')
#' is_envelope('{"type": "ValueError", "message": "bad row"}')
#'
#' try(validate_envelope('{"truncated": true, "type": "ValueError"}'))
validate_envelope <- function(x) {
  node <- parse_envelope(x)
  problems <- envelope_problems(node, "$")
  if (length(problems) > 0L) {
    stop(envelope_error(problems))
  }
  invisible(x)
}

#' @rdname validate_envelope
#' @export
is_envelope <- function(x) {
  tryCatch(
    {
      node <- parse_envelope(x)
      length(envelope_problems(node, "$")) == 0L
    },
    dataexcept_envelope_error = function(e) FALSE
  )
}

envelope_error <- function(problems, parent = NULL) {
  shown <- utils::head(problems, 10L)
  more <- length(problems) - length(shown)
  message <- paste0(
    "Invalid envelope:\n",
    paste0("* ", shown, collapse = "\n"),
    if (more > 0L) sprintf("\n* ... and %d more", more) else ""
  )
  make_condition("EnvelopeError", message,
    fields = list(problems = problems),
    parent = parent
  )
}

parse_envelope <- function(x) {
  if (is.character(x)) {
    if (length(x) != 1L || is.na(x)) {
      stop(envelope_error("the JSON text must be a single string"))
    }
    return(tryCatch(
      jsonlite::parse_json(x, simplifyVector = FALSE),
      error = function(e) stop(envelope_error("the text is not valid JSON", parent = e))
    ))
  }
  if (is.list(x)) {
    return(x)
  }
  stop(envelope_error("an envelope must be a JSON string or a list"))
}

is_json_object <- function(x) {
  is.list(x) && !is.null(names(x)) && !is.object(x)
}

is_json_array <- function(x) {
  is.list(x) && is.null(names(x)) && !is.object(x)
}

is_json_string <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x)
}

is_json_bool <- function(x) {
  is.logical(x) && length(x) == 1L && !is.na(x)
}

identity_problems <- function(node, path) {
  problems <- character()
  for (field in c("type", "module", "message")) {
    if (!field %in% names(node)) {
      problems <- c(problems, sprintf("%s: `%s` is required", path, field))
    } else if (!is_json_string(node[[field]])) {
      problems <- c(problems, sprintf("%s.%s: must be a string", path, field))
    }
  }
  problems
}

failure_problems <- function(failure, path) {
  if (!is_json_object(failure)) {
    return(sprintf("%s: must be an object", path))
  }
  problems <- character()
  missing <- setdiff(c("kind", "retryable", "retry_after_seconds"), names(failure))
  if (length(missing) > 0L) {
    problems <- c(problems, sprintf(
      "%s: `%s` is required", path, missing
    ))
  }
  if ("kind" %in% names(failure) &&
    !(is_json_string(failure$kind) && failure$kind %in% failure_kinds)) {
    problems <- c(problems, sprintf(
      "%s.kind: must be \"transient\", \"permanent\" or \"unknown\"", path
    ))
  }
  if ("retryable" %in% names(failure) && !is.null(failure$retryable) &&
    !is_json_bool(failure$retryable)) {
    problems <- c(problems, sprintf("%s.retryable: must be true, false or null", path))
  }
  seconds <- failure$retry_after_seconds
  if ("retry_after_seconds" %in% names(failure) && !is.null(seconds) &&
    !(is.numeric(seconds) && length(seconds) == 1L && !is.na(seconds) &&
      is.finite(seconds) && seconds >= 0)) {
    problems <- c(problems, sprintf(
      "%s.retry_after_seconds: must be a non-negative number or null", path
    ))
  }
  problems
}

envelope_problems <- function(node, path) {
  if (!is_json_object(node)) {
    return(sprintf("%s: must be a JSON object", path))
  }
  keys <- names(node)

  if ("truncated" %in% keys) {
    problems <- character()
    if (!isTRUE(node$truncated)) {
      problems <- c(problems, sprintf("%s.truncated: must be true", path))
    }
    extra <- setdiff(keys, "truncated")
    if (length(extra) > 0L) {
      problems <- c(problems, sprintf(
        "%s: a truncation marker carries no other field, found %s",
        path, format_keys(extra)
      ))
    }
    return(problems)
  }

  if ("cycle" %in% keys) {
    problems <- identity_problems(node, path)
    if (!isTRUE(node$cycle)) {
      problems <- c(problems, sprintf("%s.cycle: must be true", path))
    }
    extra <- setdiff(keys, c("type", "module", "message", "cycle"))
    if (length(extra) > 0L) {
      problems <- c(problems, sprintf(
        "%s: a cycle record carries only type, module and message, found %s",
        path, format_keys(extra)
      ))
    }
    return(problems)
  }

  problems <- identity_problems(node, path)
  if ("failure" %in% keys) {
    problems <- c(problems, failure_problems(node$failure, paste0(path, ".failure")))
  }
  if ("attributes" %in% keys && !is_json_object(node$attributes)) {
    problems <- c(problems, sprintf("%s.attributes: must be an object", path))
  }
  for (field in c("cause", "context")) {
    if (field %in% keys) {
      problems <- c(problems, envelope_problems(node[[field]], paste0(path, ".", field)))
    }
  }
  if ("exceptions" %in% keys) {
    members <- node$exceptions
    if (!is_json_array(members)) {
      problems <- c(problems, sprintf("%s.exceptions: must be an array", path))
    } else {
      for (i in seq_along(members)) {
        problems <- c(problems, envelope_problems(
          members[[i]], sprintf("%s.exceptions[%d]", path, i - 1L)
        ))
      }
    }
  }
  problems
}

is_dataexcept_module <- function(module) {
  identical(module, "dataexcept") || startsWith(module, "dataexcept.")
}

remote_kind <- function(type, entry) {
  if (!is.null(entry)) {
    return(entry$kind)
  }
  if (type %in% c("simpleWarning", "warning")) {
    return("warning")
  }
  if (type %in% c("simpleMessage", "message")) {
    return("message")
  }
  "error"
}

node_to_condition <- function(node) {
  if ("truncated" %in% names(node)) {
    return(structure(
      list(
        message = "<truncated>",
        call = NULL,
        .dataexcept = list(remote = TRUE, truncated = TRUE)
      ),
      class = c("dataexcept_truncated", "dataexcept_remote_condition", "condition")
    ))
  }

  state <- list(type = node$type, module = node$module, remote = TRUE)

  if ("cycle" %in% names(node)) {
    state$cycle <- TRUE
    return(structure(
      list(message = node$message, call = NULL, .dataexcept = state),
      class = c("dataexcept_cycle", "dataexcept_remote_condition", "condition")
    ))
  }

  from_dataexcept <- is_dataexcept_module(node$module)
  entry <- if (from_dataexcept) registry_entry(node$type) else NULL
  classes <- if (!is.null(entry)) {
    type_classes(node$type)
  } else if (from_dataexcept) {
    # A DataExcept type R has no class for -- a Python ServiceTimeoutError,
    # say. Every DataExcept exception derives from DataExceptError, so it is
    # still a dataexcept error, and a dataexcept_error handler catches it.
    "dataexcept_error"
  } else {
    character()
  }

  attributes <- node$attributes
  fields <- list()
  if (is_json_object(attributes) && length(attributes) > 0L) {
    usable <- names(attributes)
    usable <- usable[nzchar(usable) & !usable %in% reserved_fields & !startsWith(usable, ".")]
    fields <- attributes[usable]
  }

  state["attributes"] <- list(attributes)
  state["failure"] <- list(
    if (is.null(node$failure)) NULL else failure_from_record(node$failure)
  )
  state["context"] <- list(
    if (is.null(node$context)) NULL else node_to_condition(node$context)
  )
  state["exceptions"] <- list(
    if (is.null(node$exceptions)) NULL else lapply(node$exceptions, node_to_condition)
  )
  parent <- if (is.null(node$cause)) NULL else node_to_condition(node$cause)

  structure(
    c(
      list(message = node$message, call = NULL),
      fields,
      list(parent = parent, .dataexcept = state)
    ),
    class = unique(c(
      classes, "dataexcept_remote_condition",
      remote_kind(node$type, entry), "condition"
    ))
  )
}
