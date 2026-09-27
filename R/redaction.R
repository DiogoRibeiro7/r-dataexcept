# A port of dataexcept/redaction.py. The rules are the Python package's, so the
# two languages remove the same credentials from the same text: what is kept,
# what is replaced, and the placeholder are identical. Where Python re-encodes
# a query string it has redacted, this port does the same, so a redacted URL
# reads the same whichever language wrote the envelope.

redaction_placeholder <- "***"

# Parameter-name tokens that mark a value as a secret. A name is split into
# tokens on separators and camelCase boundaries, and matched token by token,
# so "accessToken" and "X-Amz-Signature" match while "monkey" and "keyword" do
# not. See the Python module for why "code", "state", "nonce" and "client_id"
# are deliberately absent.
sensitive_param_tokens <- c(
  "apikey", "auth", "authorization", "bearer", "credential", "credentials",
  "hmac", "jwt", "key", "keys", "passphrase", "passwd", "password", "pwd",
  "sas", "secret", "secrets", "session", "sig", "signature", "token", "tokens"
)

name_tokens <- function(name) {
  chunks <- regmatches(name, gregexpr("[A-Za-z0-9]+", name))[[1L]]
  if (length(chunks) == 0L) {
    return(character())
  }
  # Insert a space at each lower/digit -> upper boundary, then split. (A
  # zero-width split pattern cannot be used: strsplit() consumes a character
  # on a zero-length match.)
  split <- strsplit(gsub("([a-z0-9])([A-Z])", "\\1 \\2", chunks), " ", fixed = TRUE)
  tolower(unlist(split, use.names = FALSE))
}

is_sensitive_name <- function(name) {
  any(name_tokens(name) %in% sensitive_param_tokens)
}

# Python's urllib.parse.unquote_plus and quote_plus(safe = "*").
unquote_plus <- function(x) {
  x <- gsub("+", " ", x, fixed = TRUE)
  out <- tryCatch(utils::URLdecode(x), error = function(e) x)
  Encoding(out) <- "UTF-8"
  out
}

quote_plus <- function(x) {
  bytes <- charToRaw(enc2utf8(x))
  if (length(bytes) == 0L) {
    return("")
  }
  safe <- charToRaw("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-~*")
  pieces <- vapply(bytes, function(b) {
    if (b %in% safe) {
      rawToChar(b)
    } else if (b == as.raw(0x20)) {
      "+"
    } else {
      paste0("%", toupper(as.character(b)))
    }
  }, character(1))
  paste(pieces, collapse = "")
}

# parse_qsl(keep_blank_values = TRUE) followed by urlencode(safe = "*"),
# applied only when some parameter name is sensitive.
redact_params <- function(query) {
  if (!nzchar(query)) {
    return(list(text = query, redacted = FALSE))
  }
  pieces <- strsplit(query, "&", fixed = TRUE)[[1L]]
  pieces <- pieces[nzchar(pieces)]
  if (length(pieces) == 0L) {
    return(list(text = query, redacted = FALSE))
  }
  has_value <- grepl("=", pieces, fixed = TRUE)
  keys <- ifelse(has_value, sub("=.*$", "", pieces), pieces)
  values <- ifelse(has_value, sub("^[^=]*=", "", pieces), "")
  keys <- vapply(keys, unquote_plus, character(1), USE.NAMES = FALSE)
  values <- vapply(values, unquote_plus, character(1), USE.NAMES = FALSE)
  sensitive <- vapply(keys, is_sensitive_name, logical(1), USE.NAMES = FALSE)
  if (!any(sensitive)) {
    return(list(text = query, redacted = FALSE))
  }
  values[sensitive] <- redaction_placeholder
  encoded <- paste0(
    vapply(keys, quote_plus, character(1), USE.NAMES = FALSE),
    "=",
    vapply(values, quote_plus, character(1), USE.NAMES = FALSE)
  )
  list(text = paste(encoded, collapse = "&"), redacted = TRUE)
}

# urllib.parse.urlsplit, for the parts redaction needs.
split_url <- function(url) {
  scheme_match <- regmatches(url, regexec("^([A-Za-z][A-Za-z0-9+.-]*):(.*)$", url))[[1L]]
  if (length(scheme_match) == 0L) {
    return(NULL)
  }
  scheme <- tolower(scheme_match[2L])
  rest <- scheme_match[3L]
  netloc <- ""
  if (startsWith(rest, "//")) {
    rest <- substring(rest, 3L)
    end <- regexpr("[/?#]", rest)
    if (end == -1L) {
      netloc <- rest
      rest <- ""
    } else {
      netloc <- substr(rest, 1L, end - 1L)
      rest <- substring(rest, end)
    }
  }
  fragment <- ""
  hash <- regexpr("#", rest, fixed = TRUE)
  if (hash != -1L) {
    fragment <- substring(rest, hash + 1L)
    rest <- substr(rest, 1L, hash - 1L)
  }
  query <- ""
  mark <- regexpr("?", rest, fixed = TRUE)
  if (mark != -1L) {
    query <- substring(rest, mark + 1L)
    rest <- substr(rest, 1L, mark - 1L)
  }
  list(scheme = scheme, netloc = netloc, path = rest, query = query, fragment = fragment)
}

#' Remove credentials from URLs
#'
#' `redact_url()` strips credentials from a single URL; `redact_urls_in_text()`
#' finds every URL in free text and redacts each one. Scheme, host and port are
#' always kept -- they are what makes an error actionable -- while userinfo and
#' credential-bearing query and fragment parameters are replaced by `***`.
#' Parameter names are matched token by token (`accessToken`, `api_key`,
#' `X-Amz-Signature`), not by substring, so ordinary parameters such as
#' `keyword` survive.
#'
#' These are the rules of the Python DataExcept package, so a URL redacted in
#' either language reads the same. dataexcept applies them automatically to the
#' message and character fields of every condition it creates, and again, with
#' `keep_path = FALSE`, to everything it writes into an envelope.
#'
#' What redaction cannot do: a bare secret that is not part of a URL cannot be
#' recognised in free text, and is not removed.
#'
#' @param url A single URL. Anything that is not a URL with a host is returned
#'   unchanged.
#' @param text A single string that may contain URLs.
#' @param keep_path Keep the URL path? Use `FALSE` where the path itself is the
#'   secret, as in the incoming-webhook URLs of Slack and similar services.
#' @return The redacted string. A URL that carries no credential is returned
#'   exactly as given.
#' @export
#' @examples
#' redact_url("postgresql://analyst:s3cret@db.internal:5432/sales")
#' redact_url("https://api.example.com/v1/orders?page=2&api_key=abc123")
#' redact_url("https://hooks.example.com/services/T000/B000/XXXX", keep_path = FALSE)
#'
#' redact_urls_in_text("GET https://user:pw@example.com/data failed: timeout")
redact_url <- function(url, keep_path = TRUE) {
  if (!is_string(url) || !nzchar(url)) {
    return(url)
  }
  parts <- split_url(url)
  if (is.null(parts) || !nzchar(parts$netloc)) {
    return(url)
  }

  redacted <- FALSE
  netloc <- parts$netloc
  if (grepl("@", netloc, fixed = TRUE)) {
    host <- sub("^.*@", "", netloc)
    netloc <- paste0(redaction_placeholder, ":", redaction_placeholder, "@", host)
    redacted <- TRUE
  }

  query <- redact_params(parts$query)
  redacted <- redacted || query$redacted

  fragment <- parts$fragment
  if (grepl("=", fragment, fixed = TRUE)) {
    fragment_result <- redact_params(fragment)
    fragment <- fragment_result$text
    redacted <- redacted || fragment_result$redacted
  }

  path <- parts$path
  if (!keep_path && nzchar(gsub("^/+|/+$", "", path))) {
    path <- paste0("/", redaction_placeholder)
    redacted <- TRUE
  }

  if (!redacted) {
    return(url)
  }
  out <- paste0(parts$scheme, "://", netloc, path)
  if (nzchar(query$text)) {
    out <- paste0(out, "?", query$text)
  }
  if (nzchar(fragment)) {
    out <- paste0(out, "#", fragment)
  }
  out
}

# A URL starts at a scheme and runs to whitespace or a delimiter that never
# belongs to a URL in prose. A full stop, colon, exclamation or question mark
# can sit inside a URL but also ends the sentence it is in, so the last
# character must not be one of them.
url_in_text_pattern <- paste0(
  "(*UCP)[a-zA-Z][a-zA-Z0-9+.\\-]*://",
  "[^\\s'\"<>,;)\\]}]*",
  "[^\\s'\"<>,;)\\]}.:!?]"
)

#' @rdname redact_url
#' @export
redact_urls_in_text <- function(text, keep_path = TRUE) {
  if (!is_string(text) || !grepl("://", text, fixed = TRUE)) {
    return(text)
  }
  text <- enc2utf8(text)
  matches <- gregexpr(url_in_text_pattern, text, perl = TRUE)
  if (matches[[1L]][1L] == -1L) {
    return(text)
  }
  regmatches(text, matches) <- list(vapply(
    regmatches(text, matches)[[1L]],
    redact_url,
    character(1),
    keep_path = keep_path,
    USE.NAMES = FALSE
  ))
  text
}
