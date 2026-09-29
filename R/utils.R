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
    what <- "a finite, non-negative number"
    if (allow_null) what <- paste(what, "or NULL")
    stop(sprintf("`%s` must be %s.", arg, what), call. = FALSE)
  }
  invisible(x)
}

# A single real number. NaN and the infinities are allowed -- a metric that
# could not be computed is NaN, and that is often the failure being reported --
# but NA, which says nothing, is not.
check_number <- function(x, arg) {
  if (!is.numeric(x) || length(x) != 1L || (is.na(x) && !is.nan(x))) {
    stop(sprintf("`%s` must be a single number.", arg), call. = FALSE)
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
# message, in the spirit of Python's repr(): a string is quoted as Python
# quotes it, and a number is written by format_number(). URLs are redacted
# before the text is shortened, since shortening can cut a URL where its
# credentials no longer look like credentials.
format_value <- function(x, width = 60L) {
  number <- is.numeric(x) && length(x) == 1L && !is.object(x) && (!is.na(x) || is.nan(x))
  text <- if (is_string(x)) {
    python_quote(x)
  } else if (number) {
    format_number(x)
  } else {
    tryCatch(
      paste(deparse(x, width.cutoff = 500L, nlines = 1L), collapse = " "),
      error = function(e) sprintf("<%s>", class(x)[1L])
    )
  }
  text <- redact_urls_in_text(text)
  if (nchar(text) > width) {
    text <- paste0(substr(text, 1L, width - 3L), "...")
  }
  text
}

# A number in a message, written as the Python package writes it: whole
# numbers without an exponent, other numbers in the fewest digits that read
# back as the same number (Python's repr), and "nan", "inf" and "-inf" for the
# values that are not finite. `float = TRUE` writes a whole number as Python
# writes a float, with ".0"; `digits` gives a fixed number of decimal places
# instead, as Python's `{value:.3f}` does.
format_number <- function(x, digits = NULL, float = FALSE) {
  x <- as.double(x)
  if (is.nan(x)) {
    return("nan")
  }
  if (is.infinite(x)) {
    return(if (x > 0) "inf" else "-inf")
  }
  if (!is.null(digits)) {
    return(sprintf("%.*f", as.integer(digits), x))
  }
  if (x == trunc(x) && abs(x) < 1e16) {
    text <- sprintf("%.0f", x)
    return(if (float) paste0(text, ".0") else text)
  }
  shortest_number(x)
}

# A string quoted as Python's repr() quotes it: in single quotes, or in double
# quotes when it contains a single quote and no double quote. Unlike
# encodeString(), the result does not depend on the session's locale.
python_quote <- function(x) {
  quote <- if (grepl("'", x, fixed = TRUE) && !grepl("\"", x, fixed = TRUE)) "\"" else "'"
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  if (quote == "'") {
    x <- gsub("'", "\\'", x, fixed = TRUE)
  }
  for (pair in list(c("\n", "\\n"), c("\r", "\\r"), c("\t", "\\t"))) {
    x <- gsub(pair[[1L]], pair[[2L]], x, fixed = TRUE)
  }
  paste0(quote, x, quote)
}

# A message, or the default when it is NULL or empty: `message or default`, as
# the Python classes that fall back on an empty message write it.
message_or <- function(message, default) {
  if (is.null(message) || !nzchar(message)) default else message
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

# An rlang backtrace as plain text, or NULL when it cannot be formatted. Colour
# is switched off: cli would otherwise add terminal escape codes in a session
# that supports colour, and they have no place in JSON.
format_backtrace <- function(trace) {
  old <- options(cli.num_colors = 1L)
  on.exit(options(old), add = TRUE)
  text <- tryCatch(paste(format(trace), collapse = "\n"), error = function(e) NULL)
  if (is.null(text) || !nzchar(text)) {
    return(NULL)
  }
  text
}

# The message of a condition, with the trailing newline that message()
# conditions carry removed. An rlang condition's conditionMessage() appends
# the messages of its whole parent chain; the envelope renders the chain as
# `cause` records, so only the condition's own message is taken. Likewise a
# dataexcept condition's stored message is taken rather than a method's
# rendering of it: a group's conditionMessage() lists its members, which the
# envelope records as members.
condition_text <- function(cnd) {
  text <- NULL
  if (is.list(cnd$.dataexcept) && is_string(cnd$message)) {
    text <- cnd$message
  }
  from_rlang <- inherits(cnd, c("rlang_error", "rlang_warning", "rlang_message"))
  if (is.null(text) && from_rlang && requireNamespace("rlang", quietly = TRUE)) {
    text <- tryCatch(rlang::cnd_message(cnd, inherit = FALSE), error = function(e) NULL)
  }
  if (is.null(text)) {
    text <- tryCatch(conditionMessage(cnd), error = function(e) NULL)
  }
  if (!is_string(text)) {
    text <- if (is.character(text)) paste(text, collapse = "\n") else ""
  }
  sub("\n$", "", valid_utf8(text))
}

# Text as valid UTF-8. A message can carry bytes that are not valid in any
# encoding -- read from a file, or passed up from C -- and string functions
# refuse such input, so each invalid byte is replaced before anything else
# touches the text.
valid_utf8 <- function(text) {
  text <- enc2utf8(as.character(text))
  bad <- !validUTF8(text)
  if (any(bad)) {
    text[bad] <- iconv(text[bad], "UTF-8", "UTF-8", sub = "?")
  }
  text
}
