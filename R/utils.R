`%||%` <- function(x, y) if (is.null(x)) y else x

# Argument checks for the constructors. These raise plain errors, not
# dataexcept conditions: a wrong argument type is a programming mistake, not an
# operational failure, and is deliberately outside the hierarchy (as it is in
# the Python package, where constructors raise TypeError).

is_string <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x)
}

check_string <- function(x, arg, allow_null = FALSE) {
  if (allow_null && is.null(x)) {
    return(invisible(x))
  }
  if (!is_string(x)) {
    what <- if (allow_null) "a single string or NULL" else "a single string"
    stop(sprintf("`%s` must be %s.", arg, what), call. = FALSE)
  }
  invisible(x)
}

check_strings <- function(x, arg) {
  if (!is.character(x) || anyNA(x)) {
    stop(sprintf("`%s` must be a character vector without NA.", arg), call. = FALSE)
  }
  invisible(x)
}

check_count <- function(x, arg, allow_null = FALSE) {
  if (allow_null && is.null(x)) {
    return(invisible(x))
  }
  ok <- is.numeric(x) && length(x) == 1L && !is.na(x) && is.finite(x) &&
    x >= 0 && x == trunc(x)
  if (!ok) {
    what <- if (allow_null) "a non-negative whole number or NULL" else "a non-negative whole number"
    stop(sprintf("`%s` must be %s.", arg, what), call. = FALSE)
  }
  invisible(x)
}

check_seconds <- function(x, arg, allow_null = FALSE) {
  if (allow_null && is.null(x)) {
    return(invisible(x))
  }
  ok <- is.numeric(x) && length(x) == 1L && !is.na(x) && is.finite(x) && x >= 0
  if (!ok) {
    what <- if (allow_null) "a finite, non-negative number or NULL" else "a finite, non-negative number"
    stop(sprintf("`%s` must be %s.", arg, what), call. = FALSE)
  }
  invisible(x)
}

check_condition <- function(x, arg, allow_null = TRUE) {
  if (allow_null && is.null(x)) {
    return(invisible(x))
  }
  if (!inherits(x, "condition")) {
    stop(sprintf("`%s` must be a condition object or NULL.", arg), call. = FALSE)
  }
  invisible(x)
}

# A short, single-line rendering of an arbitrary value for use inside a
# message, in the spirit of Python's repr().
format_value <- function(x, width = 60L) {
  text <- tryCatch(
    paste(deparse(x, width.cutoff = 500L, nlines = 1L), collapse = " "),
    error = function(e) sprintf("<%s>", class(x)[1L])
  )
  if (nchar(text) > width) {
    text <- paste0(substr(text, 1L, width - 3L), "...")
  }
  text
}

quote_name <- function(x) {
  paste0("'", x, "'")
}

format_list <- function(x) {
  paste(x, collapse = ", ")
}

format_keys <- function(x) {
  paste0("[", paste(quote_name(x), collapse = ", "), "]")
}

# The message of a condition, with the trailing newline that message()
# conditions carry removed. An rlang condition's conditionMessage() appends
# the messages of its whole parent chain; the envelope renders the chain as
# `cause` records, so only the condition's own message is taken.
condition_text <- function(cnd) {
  text <- NULL
  if (inherits(cnd, c("rlang_error", "rlang_warning", "rlang_message")) &&
    requireNamespace("rlang", quietly = TRUE)) {
    text <- tryCatch(rlang::cnd_message(cnd, inherit = FALSE), error = function(e) NULL)
  }
  if (is.null(text)) {
    text <- tryCatch(conditionMessage(cnd), error = function(e) NULL)
  }
  if (!is_string(text)) {
    text <- if (is.character(text)) paste(text, collapse = "\n") else ""
  }
  sub("\n$", "", text)
}
