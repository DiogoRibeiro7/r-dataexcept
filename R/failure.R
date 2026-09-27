failure_kinds <- c("unknown", "transient", "permanent")

#' Describe whether a failure can be recovered from
#'
#' Failure metadata is the machine-readable part of a dataexcept error:
#' whether the underlying condition is known to be transient, permanent for the
#' same operation and payload, or unclassified, and whether retrying the same
#' operation can succeed. It describes the failure; it does not prescribe a
#' retry policy, which stays with the calling code.
#'
#' Every dataexcept error carries metadata. The class default is deliberately
#' conservative (`"unknown"`, retryable `NULL`), and a class receives a
#' stronger default only where it can be defended without knowing the backend:
#' a [validation_error()] is permanent and not retryable for the same unchanged
#' payload. Code that does know the backend's answer attaches it with
#' `with_failure_metadata()`.
#'
#' @param kind One of `"unknown"`, `"transient"` or `"permanent"`.
#' @param retryable `TRUE`, `FALSE`, or `NULL` when no classification is
#'   warranted. `NULL` is deliberately distinct from `FALSE`.
#' @param retry_after_seconds How long to wait before retrying, when the
#'   backend said: a finite, non-negative number, or `NULL`.
#'
#' @return `failure_metadata()` returns an object of class
#'   `dataexcept_failure_metadata`: a list with elements `kind`, `retryable`
#'   and `retry_after_seconds`.
#' @seealso [condition_failure()] to read the metadata back from a condition.
#' @export
#' @examples
#' failure_metadata("transient", retryable = TRUE, retry_after_seconds = 2)
#'
#' err <- api_error("https://api.example.com/v1/orders", status_code = 503L)
#' err <- with_failure_metadata(err, failure_metadata("transient", TRUE, 30))
#' is_retryable(err)
failure_metadata <- function(kind = "unknown",
                             retryable = NULL,
                             retry_after_seconds = NULL) {
  if (!is_string(kind) || !kind %in% failure_kinds) {
    stop("`kind` must be one of \"unknown\", \"transient\" or \"permanent\".",
      call. = FALSE
    )
  }
  if (!is.null(retryable) &&
    !(is.logical(retryable) && length(retryable) == 1L && !is.na(retryable))) {
    stop("`retryable` must be TRUE, FALSE or NULL.", call. = FALSE)
  }
  check_seconds(retry_after_seconds, "retry_after_seconds", allow_null = TRUE)
  if (!is.null(retry_after_seconds)) {
    retry_after_seconds <- as.double(retry_after_seconds)
  }
  structure(
    list(
      kind = kind,
      retryable = retryable,
      retry_after_seconds = retry_after_seconds
    ),
    class = "dataexcept_failure_metadata"
  )
}

#' @export
format.dataexcept_failure_metadata <- function(x, ...) {
  retryable <- if (is.null(x$retryable)) "NULL" else format(x$retryable)
  after <- if (is.null(x$retry_after_seconds)) "NULL" else format(x$retry_after_seconds)
  sprintf(
    "<failure_metadata: kind = %s, retryable = %s, retry_after_seconds = %s>",
    x$kind, retryable, after
  )
}

#' @export
print.dataexcept_failure_metadata <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  invisible(x)
}

#' @rdname failure_metadata
#' @param cnd A condition object.
#' @param metadata A `dataexcept_failure_metadata` object from
#'   `failure_metadata()`.
#' @return `with_failure_metadata()` returns `cnd` with the metadata attached.
#' @export
with_failure_metadata <- function(cnd, metadata) {
  if (!inherits(cnd, "dataexcept_error")) {
    stop("`cnd` must be a dataexcept error.", call. = FALSE)
  }
  if (!inherits(metadata, "dataexcept_failure_metadata")) {
    stop("`metadata` must be created by failure_metadata().", call. = FALSE)
  }
  cnd$.dataexcept$failure <- metadata
  cnd
}

#' Read the failure metadata of a condition
#'
#' `condition_failure()` returns the recovery metadata carried by a dataexcept
#' error, or by a condition read back from an envelope that had a `failure`
#' record. Conditions dataexcept did not classify -- a base R `simpleError`, an
#' rlang error, or a third-party exception in an envelope -- return `NULL`.
#'
#' `is_retryable()` is the common question: `TRUE` or `FALSE` when the failure
#' is classified, `NA` when it is not.
#'
#' @param cnd A condition object.
#' @return `condition_failure()` returns a `dataexcept_failure_metadata`
#'   object or `NULL`. `is_retryable()` returns `TRUE`, `FALSE` or `NA`.
#' @export
#' @examples
#' condition_failure(validation_error("age", -1))
#' is_retryable(validation_error("age", -1))
#' is_retryable(simpleError("boom"))
condition_failure <- function(cnd) {
  check_condition(cnd, "cnd", allow_null = FALSE)
  metadata <- cnd$.dataexcept$failure
  if (inherits(metadata, "dataexcept_failure_metadata")) {
    return(metadata)
  }
  NULL
}

#' @rdname condition_failure
#' @export
is_retryable <- function(cnd) {
  metadata <- condition_failure(cnd)
  if (is.null(metadata) || is.null(metadata$retryable)) {
    return(NA)
  }
  metadata$retryable
}

# Build metadata from an envelope's failure record, falling back to the
# unknown classification when the record is malformed -- the same fallback the
# Python serializer applies to a hostile override.
failure_from_record <- function(record) {
  tryCatch(
    failure_metadata(
      kind = record$kind,
      retryable = record$retryable,
      retry_after_seconds = record$retry_after_seconds
    ),
    error = function(e) failure_metadata()
  )
}

failure_record <- function(metadata) {
  if (!inherits(metadata, "dataexcept_failure_metadata")) {
    metadata <- failure_metadata()
  }
  metadata <- failure_from_record(unclass(metadata))
  list(
    kind = metadata$kind,
    retryable = metadata$retryable,
    retry_after_seconds = metadata$retry_after_seconds
  )
}
