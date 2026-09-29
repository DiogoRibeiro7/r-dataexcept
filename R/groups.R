#' Report several failures as one
#'
#' `condition_group()` combines several conditions into one error, so that a
#' check which finds many problems can report all of them instead of stopping
#' at the first. It is written to an envelope as an exception group -- the
#' `exceptions` array the schema defines, which Python's `ExceptionGroup` also
#' produces -- with every member rendered in full, chains included.
#'
#' `collect_errors()` is the way to gather the members: it evaluates each of
#' its arguments in turn, catches any error one of them signals, and carries on
#' with the next. `group_members()` returns the members of a group, whether it
#' was built here or read from an envelope.
#'
#' A group is caught by a `dataexcept_condition_group` handler, and by
#' `dataexcept_error` like every other dataexcept error. A group read from an
#' envelope -- including a Python `ExceptionGroup` -- has the
#' `dataexcept_condition_group` class too.
#'
#' The group's failure metadata, unless given, is its members' when they all
#' agree, and unclassified otherwise: a batch of permanent validation failures
#' is permanent, but a mix of transient and permanent failures has no single
#' answer to whether a retry would help. When the members agree and some give a
#' retry delay, the longest one is used.
#'
#' @param conditions A non-empty list of conditions.
#' @param message A short description of what failed, or `NULL`. The count of
#'   failures is appended: `"orders failed validation (3 failures)"`.
#' @param ... Named fields to store on the group, as in
#'   [new_dataexcept_error()].
#' @param class Additional R classes, most specific first.
#' @param parent The condition that caused the whole group, or `NULL`.
#' @param call The call to report, or `NULL`.
#' @param failure Failure metadata from [failure_metadata()], or `NULL` to
#'   derive it from the members.
#' @return `condition_group()` returns a condition of class
#'   `dataexcept_condition_group`. `collect_errors()` returns a list of the
#'   errors caught, named after the arguments that signalled them when those
#'   are named, and empty when there were none. `group_members()` returns a
#'   list of conditions, empty for a condition that is not a group.
#' @export
#' @examples
#' orders <- data.frame(id = 1:3, amount = c("10", "20", "30"))
#'
#' require_column <- function(df, column) {
#'   if (!column %in% names(df)) stop(missing_column_error(column, dataframe = "orders"))
#' }
#' require_numeric <- function(df, column) {
#'   if (!is.numeric(df[[column]])) {
#'     stop(dtype_mismatch_error(column, "numeric", class(df[[column]])[1]))
#'   }
#' }
#'
#' errors <- collect_errors(
#'   require_column(orders, "customer_id"),
#'   require_column(orders, "amount"),
#'   require_numeric(orders, "amount")
#' )
#' length(errors)
#'
#' err <- tryCatch(
#'   if (length(errors) > 0) stop(condition_group(errors, "orders failed validation")),
#'   dataexcept_condition_group = identity
#' )
#' conditionMessage(err)
#' vapply(group_members(err), function(e) class(e)[1], character(1))
#' cat(condition_to_json(err, pretty = TRUE))
condition_group <- function(conditions,
                            message = NULL,
                            ...,
                            class = character(),
                            parent = NULL,
                            call = NULL,
                            failure = NULL) {
  if (!is.list(conditions) || length(conditions) == 0L || is.object(conditions)) {
    stop("`conditions` must be a non-empty list of conditions.", call. = FALSE)
  }
  if (!all(vapply(conditions, inherits, logical(1), "condition"))) {
    stop("Every element of `conditions` must be a condition.", call. = FALSE)
  }
  check_string(message, "message", allow_null = TRUE)
  count <- length(conditions)
  counted <- sprintf("%d failure%s", count, if (count == 1L) "" else "s")
  message <- if (is.null(message)) counted else sprintf("%s (%s)", message, counted)

  cnd <- make_condition("ConditionGroup", message,
    fields = list(...),
    class = class,
    parent = parent,
    call = call,
    failure = failure %||% group_failure(conditions)
  )
  cnd$.dataexcept$exceptions <- unname(conditions)
  cnd
}

group_failure <- function(conditions) {
  metadata <- lapply(conditions, function(cnd) {
    tryCatch(condition_failure(cnd), error = function(e) NULL)
  })
  if (any(vapply(metadata, is.null, logical(1)))) {
    return(failure_metadata())
  }
  kinds <- unique(vapply(metadata, `[[`, character(1), "kind"))
  retryable <- unique(lapply(metadata, `[[`, "retryable"))
  if (length(kinds) != 1L || length(retryable) != 1L) {
    return(failure_metadata())
  }
  delays <- unlist(lapply(metadata, `[[`, "retry_after_seconds"))
  failure_metadata(
    kinds,
    retryable = retryable[[1L]],
    retry_after_seconds = if (length(delays) > 0L) max(delays) else NULL
  )
}

#' @rdname condition_group
#' @param cnd A condition.
#' @export
group_members <- function(cnd) {
  check_condition(cnd, "cnd", allow_null = FALSE)
  members <- cnd$.dataexcept$exceptions
  if (is.list(members)) members else list()
}

#' @rdname condition_group
#' @export
collect_errors <- function(...) {
  count <- ...length()
  # Names come from the call, not from list(...), which would evaluate every
  # argument at once.
  labels <- names(match.call(expand.dots = FALSE)$...) %||% rep("", count)
  errors <- list()
  for (i in seq_len(count)) {
    # ...elt() forces one argument, in the environment it was written in --
    # the caller's, or its caller's when the arguments were passed on as `...`.
    caught <- tryCatch(
      {
        ...elt(i)
        NULL
      },
      error = identity
    )
    if (!is.null(caught)) {
      errors[[length(errors) + 1L]] <- caught
      names(errors)[length(errors)] <- labels[[i]]
    }
  }
  if (length(errors) > 0L && all(!nzchar(names(errors)))) {
    names(errors) <- NULL
  }
  errors
}

max_listed_members <- 10L

#' @export
conditionMessage.dataexcept_condition_group <- function(c) {
  members <- group_members(c)
  if (length(members) == 0L) {
    return(c$message)
  }
  shown <- utils::head(members, max_listed_members)
  # One line per member, redacted as the group's own message was: a member
  # can be any condition, including one whose message carries a credential.
  lines <- vapply(shown, function(member) {
    redact_urls_in_text(sub("\n.*$", "", condition_text(member)))
  }, character(1))
  more <- length(members) - length(shown)
  paste0(
    c$message,
    paste0("\n* ", lines, collapse = ""),
    if (more > 0L) sprintf("\n* ... and %d more", more) else ""
  )
}

#' Turn errors from an expression into a dataexcept error
#'
#' `wrap_errors()` evaluates `expr`, and if it signals an error, signals the
#' error `constructor` builds instead, with the original as its cause. It is
#' the R counterpart of the Python package's `wrap()` and `wrapping()`, and
#' replaces the handler that is otherwise written out by hand:
#'
#' ```r
#' tryCatch(
#'   read.csv(path),
#'   error = function(e) stop(file_read_error(path, parent = e))
#' )
#' ```
#'
#' The original condition is always recorded as the cause, so it stays in the
#' envelope and in rlang's "Caused by" output. Conditions other than those in
#' `on` pass through untouched, as do interrupts.
#'
#' @param expr The expression to evaluate.
#' @param constructor A function returning a condition, called with `...` and
#'   `parent`, the condition that was caught: any dataexcept constructor, or
#'   your own.
#' @param ... Arguments for `constructor`.
#' @param on The classes of condition to wrap. The default wraps errors only;
#'   `c("error", "warning")` also turns a warning into the wrapped error, which
#'   suits functions such as [read.csv()] that warn before they fail.
#' @param failure Failure metadata for the new error, from
#'   [failure_metadata()], or `NULL` for the constructor's default.
#' @return The value of `expr`, when nothing is wrapped.
#' @export
#' @examples
#' path <- tempfile(fileext = ".csv")
#'
#' err <- tryCatch(
#'   wrap_errors(read.csv(path), file_read_error, path = path, on = c("error", "warning")),
#'   dataexcept_file_error = identity
#' )
#' conditionMessage(err)
#' class(err$parent)
#'
#' # A transient failure, as far as the caller knows.
#' fetch <- function() stop("connection reset by peer")
#' err <- tryCatch(
#'   wrap_errors(fetch(), api_error,
#'     endpoint = "https://api.example.com/v1/rates",
#'     failure = failure_metadata("transient", retryable = TRUE)
#'   ),
#'   dataexcept_error = identity
#' )
#' is_retryable(err)
wrap_errors <- function(expr, constructor, ..., on = "error", failure = NULL) {
  if (!is.function(constructor)) {
    stop("`constructor` must be a function.", call. = FALSE)
  }
  check_strings(on, "on")
  if (length(on) == 0L) {
    stop("`on` must name at least one condition class.", call. = FALSE)
  }
  if (!is.null(failure) && !inherits(failure, "dataexcept_failure_metadata")) {
    stop("`failure` must be created by failure_metadata() or be NULL.", call. = FALSE)
  }
  arguments <- list(...)
  withCallingHandlers(
    expr,
    condition = function(cnd) {
      if (!inherits(cnd, on) || inherits(cnd, "interrupt")) {
        return(invisible())
      }
      # quote = TRUE: an argument such as `call = sys.call()` is a call object,
      # to be stored, not evaluated again.
      wrapped <- do.call(constructor, c(arguments, list(parent = cnd)), quote = TRUE)
      if (!inherits(wrapped, "condition")) {
        stop("`constructor` must return a condition.", call. = FALSE)
      }
      if (!is.null(failure)) {
        wrapped <- with_failure_metadata(wrapped, failure)
      }
      stop(wrapped)
    }
  )
}
