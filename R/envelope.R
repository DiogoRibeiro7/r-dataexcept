#' Write a condition as a DataExcept envelope
#'
#' `condition_to_envelope()` renders a condition, and the chain of conditions
#' behind it, as a DataExcept envelope: the language-neutral failure record the
#' Python DataExcept package defines in its published JSON Schema
#' ([envelope_schema()]). `condition_to_json()` encodes it as strict JSON.
#'
#' Any condition can be written, not only dataexcept ones:
#'
#' * `type` is the dataexcept type, or else the condition's most specific R
#'   class (`simpleError`, `rlang_error`, ...).
#' * `module` is `"dataexcept"` for dataexcept conditions, `"base"` for base
#'   R's own condition classes, the package for a class named with its
#'   package prefix (`rlang_error` belongs to rlang), and `"unknown"` where the
#'   package cannot be established.
#' * `message` is the condition message.
#' * `failure` appears on dataexcept errors only. A condition dataexcept did
#'   not classify has no `failure` field, and that absence is information: it
#'   means unclassified, not "not retryable".
#' * `attributes` holds the condition's fields, in a JSON-safe form. The
#'   message, call, parent and backtrace are not attributes, nor is any field
#'   whose name begins with `.` or `_`.
#' * `cause` is the condition in the `parent` field -- the field dataexcept and
#'   rlang both use for a chained cause -- rendered the same way.
#'
#' Text is redacted on the way out: every URL in the message, in attribute
#' values and in attribute names loses its credentials and its path.
#'
#' A vector of length one is written as a scalar. Wrap a field in [I()] when it
#' is a list by meaning, so that it is written as an array even with a single
#' element -- the convention jsonlite uses. The constructors do this for the
#' fields the Python package always writes as lists, such as the `expected`
#' types of [dtype_mismatch_error()].
#'
#' Values that JSON cannot represent degrade to a description of themselves
#' rather than disappearing: a data frame becomes `"<data.frame: 150 rows x 5
#' columns>"`, a function `"<function>"`, a vector longer than 100 elements a
#' description of its type and length, and `NaN` or `Inf` the strings `"nan"`
#' or `"inf"`, as the Python serializer writes them. `NA` becomes `null`.
#'
#' @param cnd A condition object.
#' @param include_attributes Include the `attributes` field?
#' @param max_depth How many levels of chained conditions to render. A cause
#'   beyond this depth is replaced by the truncation marker
#'   `{"truncated": true}`.
#' @param pretty Indent the JSON for reading?
#' @return `condition_to_envelope()` returns the envelope as a list (JSON
#'   objects as named lists, arrays as unnamed lists, `null` as `NULL`).
#'   `condition_to_json()` returns a single string.
#' @seealso [envelope_to_condition()] for the reverse direction.
#' @export
#' @examples
#' cnd <- tryCatch(
#'   stop(missing_column_error("customer_id", dataframe = "orders")),
#'   error = identity
#' )
#' cat(condition_to_json(cnd, pretty = TRUE))
#'
#' # A chain: the base R error becomes the cause.
#' cnd <- tryCatch(
#'   tryCatch(
#'     read.csv(tempfile()),
#'     warning = function(w) stop(file_read_error("orders.csv", parent = w))
#'   ),
#'   error = identity
#' )
#' str(condition_to_envelope(cnd), max.level = 2)
condition_to_envelope <- function(cnd, include_attributes = TRUE, max_depth = 8L) {
  check_condition(cnd, "cnd", allow_null = FALSE)
  valid_flag <- is.logical(include_attributes) && length(include_attributes) == 1L &&
    !is.na(include_attributes)
  if (!valid_flag) {
    stop("`include_attributes` must be TRUE or FALSE.", call. = FALSE)
  }
  check_count(max_depth, "max_depth")
  envelope_record(cnd,
    include_attributes = include_attributes,
    max_depth = as.integer(max_depth),
    depth = 0L
  )
}

#' @rdname condition_to_envelope
#' @export
condition_to_json <- function(cnd, include_attributes = TRUE, max_depth = 8L,
                              pretty = FALSE) {
  envelope <- condition_to_envelope(cnd,
    include_attributes = include_attributes,
    max_depth = max_depth
  )
  json <- write_json(envelope, pretty = isTRUE(pretty))
  # Every piece was converted to UTF-8 on the way in; say so, so that a
  # consumer in a non-UTF-8 locale does not reinterpret the bytes.
  Encoding(json) <- "UTF-8"
  json
}

#' @rdname condition_to_envelope
#' @name condition_type
#' @usage condition_type(cnd)
#' @return `condition_type()` returns the `type` a condition is written with:
#'   the dataexcept type when there is one -- including the type of a
#'   condition read from an envelope -- and otherwise the condition's most
#'   specific R class.
#' @export condition_type
NULL

# Fields that are part of the condition's machinery rather than its content,
# including rlang's.
non_attribute_fields <- c(
  "message", "call", "parent", "trace", "rlang", "use_cli_format",
  "body", "footer", "header"
)

condition_attributes <- function(cnd) {
  state <- cnd$.dataexcept
  if (isTRUE(state$remote)) {
    return(json_safe(state$attributes))
  }
  fields <- unclass(cnd)
  keep <- names(fields)
  private <- startsWith(keep, ".") | startsWith(keep, "_")
  keep <- keep[nzchar(keep) & !keep %in% non_attribute_fields & !private]
  if (length(keep) == 0L) {
    return(NULL)
  }
  out <- lapply(fields[keep], json_safe)
  names(out) <- export_text(keep)
  out
}

record_identity <- function(cnd) {
  list(
    type = export_text(condition_type(cnd)),
    module = export_text(condition_module(cnd)),
    message = export_text(condition_text(cnd))
  )
}

envelope_record <- function(cnd, include_attributes, max_depth, depth) {
  state <- cnd$.dataexcept
  if (depth > max_depth || isTRUE(state$truncated)) {
    return(list(truncated = TRUE))
  }
  if (isTRUE(state$cycle)) {
    return(c(record_identity(cnd), list(cycle = TRUE)))
  }

  record <- record_identity(cnd)

  classified <- inherits(cnd, "dataexcept_error") && !isTRUE(state$remote)
  if (classified || (isTRUE(state$remote) && !is.null(state$failure))) {
    record$failure <- failure_record(state$failure)
  }

  if (include_attributes) {
    attributes <- condition_attributes(cnd)
    if (length(attributes) > 0L) {
      record$attributes <- attributes
    }
  }

  child <- function(x) {
    envelope_record(x,
      include_attributes = include_attributes,
      max_depth = max_depth,
      depth = depth + 1L
    )
  }

  members <- state$exceptions
  is_group <- is.list(members) && length(members) > 0L &&
    all(vapply(members, inherits, logical(1), "condition"))
  if (is_group) {
    record$exceptions <- unname(lapply(members, child))
  }
  if (inherits(cnd$parent, "condition")) {
    record$cause <- child(cnd$parent)
  }
  if (inherits(state$context, "condition")) {
    record$context <- child(state$context)
  }
  record
}
