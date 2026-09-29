# JSON handling. Envelopes are strict JSON: no NaN, no Infinity, and nothing
# that cannot be represented. Values are first mapped onto a small JSON model
# by json_safe() -- NULL, a length-one atomic, an unnamed list (array) or a
# named list (object) -- and that model is written by write_json(), which owns
# every formatting decision, including numbers written to the shortest
# precision that round-trips.

max_value_depth <- 8L
max_vector_length <- 100L

# Text leaving the package: URLs redacted with their paths, and valid UTF-8.
export_text <- function(text) {
  vapply(valid_utf8(text), redact_urls_in_text, character(1),
    keep_path = FALSE, USE.NAMES = FALSE
  )
}

describe_value <- function(x) {
  if (is.data.frame(x)) {
    return(sprintf("<data.frame: %d rows x %d columns>", nrow(x), ncol(x)))
  }
  if (!is.null(dim(x))) {
    return(sprintf(
      "<%s: %s %s>",
      if (length(dim(x)) == 2L) "matrix" else "array",
      paste(dim(x), collapse = " x "),
      typeof(x)
    ))
  }
  if (is.environment(x)) {
    return("<environment>")
  }
  if (is.function(x)) {
    return("<function>")
  }
  if (isS4(x)) {
    return(sprintf("<S4 object of class %s>", class(x)[1L]))
  }
  sprintf("<object of class %s>", class(x)[1L])
}

json_scalar <- function(x) {
  if (is.na(x) && !is.nan(x)) {
    return(NULL)
  }
  if (is.double(x)) {
    if (is.nan(x)) {
      return("nan")
    }
    if (is.infinite(x)) {
      return(if (x > 0) "inf" else "-inf")
    }
    return(x)
  }
  if (is.character(x)) {
    return(export_text(x))
  }
  x
}

json_atomic <- function(x, array = FALSE) {
  x <- unclass(x)
  attributes(x) <- attributes(x)[intersect(names(attributes(x)), "names")]
  if (length(x) == 1L && is.null(names(x)) && !array) {
    return(json_scalar(x))
  }
  if (length(x) > max_vector_length) {
    return(sprintf("<%s vector of length %d>", typeof(x), length(x)))
  }
  values <- lapply(seq_along(x), function(i) json_scalar(x[[i]]))
  keys <- names(x)
  if (!is.null(keys) && all(nzchar(keys)) && !anyDuplicated(keys)) {
    names(values) <- export_text(keys)
  }
  values
}

json_safe <- function(x, depth = 0L) {
  if (is.null(x)) {
    return(NULL)
  }
  if (inherits(x, "condition")) {
    return(export_text(condition_text(x)))
  }
  # I() marks a vector that is a list by meaning, so that a length-one
  # vector is still written as an array -- the jsonlite convention.
  as_array <- inherits(x, "AsIs")
  if (as_array) {
    remaining <- setdiff(oldClass(x), "AsIs")
    oldClass(x) <- if (length(remaining) > 0L) remaining else NULL
  }
  if (is.factor(x)) {
    x <- stats::setNames(as.character(x), names(x))
  }
  if (inherits(x, "Date")) {
    x <- stats::setNames(format(x, "%Y-%m-%d"), names(x))
  } else if (inherits(x, "POSIXt")) {
    x <- stats::setNames(format(as.POSIXct(x), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), names(x))
  }
  if (is.data.frame(x) || !is.null(dim(x))) {
    return(describe_value(x))
  }
  if (is.logical(x) || is.integer(x) || is.double(x) || is.character(x)) {
    if (is.object(x) && !is.character(x) && !is.numeric(x) && !is.logical(x)) {
      return(describe_value(x))
    }
    return(json_atomic(x, array = as_array))
  }
  if (is.list(x) && !is.object(x)) {
    if (depth >= max_value_depth) {
      return("<truncated>")
    }
    values <- lapply(x, json_safe, depth = depth + 1L)
    keys <- names(x)
    if (!is.null(keys) && all(nzchar(keys)) && !anyDuplicated(keys)) {
      names(values) <- export_text(keys)
      return(values)
    }
    # An empty named list is an object (handled above); anything partly
    # named becomes an array.
    return(unname(values))
  }
  describe_value(x)
}

json_escape <- function(x) {
  x <- enc2utf8(x)
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub("\"", "\\\"", x, fixed = TRUE)
  x <- gsub("\n", "\\n", x, fixed = TRUE)
  x <- gsub("\r", "\\r", x, fixed = TRUE)
  x <- gsub("\t", "\\t", x, fixed = TRUE)
  x <- gsub("\b", "\\b", x, fixed = TRUE)
  x <- gsub("\f", "\\f", x, fixed = TRUE)
  control <- gregexpr("[\001-\037]", x, perl = TRUE)
  if (control[[1L]][1L] != -1L) {
    regmatches(x, control) <- list(vapply(
      regmatches(x, control)[[1L]],
      function(ch) sprintf("\\u%04x", utf8ToInt(ch)),
      character(1)
    ))
  }
  paste0("\"", x, "\"")
}

# The shortest decimal form that reads back as the same double.
json_number <- function(x) {
  if (is.integer(x)) {
    return(as.character(x))
  }
  if (x == trunc(x) && abs(x) < 1e15) {
    return(formatC(x, format = "f", digits = 0L))
  }
  shortest_number(x)
}

# The shortest decimal text that reads back as `x`: what Python's repr() and
# JavaScript write for a double. The text is read back with the C library's
# strtod(), through jsonlite, and not with as.double(): R's own number parser
# is not correctly rounded where long double is no wider than double, as on
# Apple silicon, and there it rejects texts that are exact.
shortest_number <- function(x) {
  for (digits in 15:17) {
    text <- trimws(formatC(x, digits = digits, format = "g"))
    if (isTRUE(jsonlite::parse_json(text) == x)) {
      break
    }
  }
  text
}

write_json <- function(x, pretty = FALSE, indent = 0L) {
  if (is.null(x)) {
    return("null")
  }
  if (is.list(x)) {
    is_object <- !is.null(names(x))
    if (length(x) == 0L) {
      return(if (is_object) "{}" else "[]")
    }
    values <- vapply(x, write_json, character(1),
      pretty = pretty, indent = indent + 2L, USE.NAMES = FALSE
    )
    if (is_object) {
      values <- paste0(json_escape(names(x)), if (pretty) ": " else ":", values)
    }
    open <- if (is_object) "{" else "["
    close <- if (is_object) "}" else "]"
    if (!pretty) {
      return(paste0(open, paste(values, collapse = ","), close))
    }
    pad <- strrep(" ", indent + 2L)
    return(paste0(
      open, "\n",
      paste0(pad, values, collapse = ",\n"),
      "\n", strrep(" ", indent), close
    ))
  }
  if (length(x) != 1L) {
    stop("Internal error: write_json() received a vector of length != 1.", call. = FALSE) # nocov
  }
  if (is.na(x)) {
    return("null") # nocov: json_safe() has already turned NA into NULL
  }
  if (is.logical(x)) {
    return(if (x) "true" else "false")
  }
  if (is.numeric(x)) {
    return(json_number(x))
  }
  json_escape(as.character(x))
}

# Object keys sorted at every level, as Python's json.dumps(sort_keys = TRUE)
# writes them, so a document embedded in a span attribute is byte-stable
# whichever language produced it.
sort_json_keys <- function(x) {
  if (!is.list(x)) {
    return(x)
  }
  keys <- names(x)
  if (!is.null(keys)) {
    x <- x[order(keys, method = "radix")]
  }
  x[] <- lapply(x, sort_json_keys)
  x
}
