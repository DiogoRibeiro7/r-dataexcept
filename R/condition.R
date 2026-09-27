#' Create a dataexcept error
#'
#' `new_dataexcept_error()` is the constructor every dataexcept error is built
#' with, and the way to define your own. It returns a condition object without
#' signalling it; signal it with [stop()] (or `rlang::abort()`), exactly as you
#' would a condition from [errorCondition()].
#'
#' A dataexcept error is an ordinary R condition. Its fields are list
#' elements, so a handler reads them directly (`cnd$column`); its classes are
#' what `tryCatch()` matches; and its cause is stored in `parent`, the field
#' rlang uses, so rlang prints the chain as "Caused by error".
#'
#' Credentials never reach a dataexcept condition. URLs in the message and in
#' character fields are redacted at construction: userinfo and credential
#' query parameters are removed, while scheme, host and port stay, because
#' they are what makes an error actionable.
#'
#' @param message The condition message, a single string.
#' @param ... Named fields to store on the condition.
#' @param type The envelope type. A registered type (see
#'   [dataexcept_classes()]) supplies the R classes and the default failure
#'   metadata. An unregistered type is allowed for your own errors: pass the R
#'   class in `class`.
#' @param class Additional R classes, most specific first. They are placed in
#'   front of the classes of `type`.
#' @param parent The condition that caused this one, or `NULL`.
#' @param call The call to report, or `NULL`. Pass `sys.call()` from inside
#'   your function to report its call.
#' @param failure Failure metadata from [failure_metadata()]; defaults to the
#'   default of `type`.
#'
#' @return A condition object of class `c(class, <classes of type>, "error",
#'   "condition")`.
#' @seealso The constructors for specific failures, such as
#'   [missing_column_error()] and [validation_error()].
#' @export
#' @examples
#' # Your own error, still caught as a dataexcept error and serialisable to
#' # the envelope.
#' quota_error <- function(used, limit) {
#'   new_dataexcept_error(
#'     sprintf("Quota exceeded: %d of %d requests used", used, limit),
#'     used = used,
#'     limit = limit,
#'     type = "QuotaExceededError",
#'     class = "myapp_quota_exceeded_error",
#'     failure = failure_metadata("transient", retryable = TRUE)
#'   )
#' }
#'
#' tryCatch(
#'   stop(quota_error(1000L, 1000L)),
#'   dataexcept_error = function(e) condition_to_json(e)
#' )
new_dataexcept_error <- function(message,
                                 ...,
                                 type = "DataExceptError",
                                 class = character(),
                                 parent = NULL,
                                 call = NULL,
                                 failure = NULL) {
  make_condition(
    type = type,
    message = message,
    fields = list(...),
    class = class,
    parent = parent,
    call = call,
    failure = failure
  )
}

reserved_fields <- c("message", "call", "parent", ".dataexcept")

make_condition <- function(type,
                           message,
                           fields = list(),
                           class = character(),
                           parent = NULL,
                           call = NULL,
                           failure = NULL,
                           keep_path = TRUE) {
  check_string(type, "type")
  check_string(message, "message")
  check_strings(class, "class")
  check_condition(parent, "parent")
  if (!is.null(failure) && !inherits(failure, "dataexcept_failure_metadata")) {
    stop("`failure` must be created by failure_metadata() or be NULL.", call. = FALSE)
  }
  if (length(fields) > 0L) {
    field_names <- names(fields)
    if (is.null(field_names) || any(!nzchar(field_names)) || anyDuplicated(field_names)) {
      stop("Every field must have a unique, non-empty name.", call. = FALSE)
    }
    clash <- intersect(field_names, reserved_fields)
    if (length(clash) > 0L) {
      stop(
        sprintf("Field names %s are reserved.", format_keys(clash)),
        call. = FALSE
      )
    }
  }

  entry <- registry_entry(type)
  if (is.null(entry)) {
    if (length(class) == 0L) {
      stop("An unregistered `type` needs at least one R class in `class`.", call. = FALSE)
    }
    type_class <- c("dataexcept_error")
    base_kind <- "error"
    default_failure <- failure_metadata()
  } else {
    type_class <- type_classes(type)
    base_kind <- entry$kind
    default_failure <- entry$failure
  }

  fields <- lapply(fields, redact_field, keep_path = keep_path)
  state <- list(
    type = type,
    module = "dataexcept",
    failure = if (base_kind == "error") failure %||% default_failure else NULL
  )

  structure(
    c(
      list(
        message = redact_urls_in_text(message, keep_path = keep_path),
        call = call
      ),
      fields,
      list(parent = parent, .dataexcept = state)
    ),
    class = unique(c(class, type_class, base_kind, "condition"))
  )
}

redact_field <- function(value, keep_path = TRUE) {
  if (is.character(value) && !is.object(value) && any(grepl("://", value, fixed = TRUE))) {
    out <- vapply(value, redact_urls_in_text, character(1),
      keep_path = keep_path, USE.NAMES = FALSE
    )
    attributes(out) <- attributes(value)
    return(out)
  }
  value
}

# The envelope type of any condition: the dataexcept type when there is one,
# otherwise the most specific R class, which is what an R handler matches on.
condition_type <- function(cnd) {
  type <- cnd$.dataexcept$type
  if (is_string(type)) {
    return(type)
  }
  class(cnd)[1L]
}

base_condition_classes <- c(
  "simpleError", "simpleWarning", "simpleMessage", "simpleCondition",
  "error", "warning", "message", "condition", "interrupt",
  "packageNotFoundError", "packageStartupMessage", "getParseError",
  "deprecatedWarning", "defunctError"
)

# The module that defines a condition's class: the R package, where it can be
# established. Base R's own condition classes belong to "base"; classes named
# with a package prefix, as rlang_error and vctrs_error_* are, belong to that
# package when it is loaded. Anything else is "unknown" rather than guessed.
condition_module <- function(cnd) {
  module <- cnd$.dataexcept$module
  if (is_string(module)) {
    return(module)
  }
  first <- class(cnd)[1L]
  if (first %in% base_condition_classes) {
    return("base")
  }
  prefix <- sub("_.*$", "", first)
  if (nzchar(prefix) && prefix != first && prefix %in% loadedNamespaces()) {
    return(prefix)
  }
  "unknown"
}
