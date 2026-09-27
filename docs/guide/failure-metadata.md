# Failure metadata

Whether a failure is worth retrying is the first question a scheduler, a worker
loop or an orchestration layer asks, and a bare error message cannot answer it.
Every dataexcept error carries three machine-readable fields that can:

| Field | Values | Meaning |
| --- | --- | --- |
| `kind` | `"transient"`, `"permanent"`, `"unknown"` | Whether the underlying condition is known to be temporary, permanent for the same operation and payload, or unclassified. |
| `retryable` | `TRUE`, `FALSE`, `NULL` | Whether retrying the same operation can succeed. `NULL` means no classification is warranted, which is deliberately distinct from `FALSE`. |
| `retry_after_seconds` | a non-negative number, or `NULL` | How long to wait, when the backend said. |

The metadata describes the failure. It does not prescribe a retry policy,
which stays with the calling code.

## Conservative defaults

A class gets a stronger default than `"unknown"` only where the package can
defend it without knowing the backend:

- `validation_error()` is **permanent and not retryable**: the same unchanged
  payload will fail the same rule again.
- Everything else, including network, timeout, database-connection and API
  failures, is **unknown**. Only the backend's answer can say whether a retry
  helps.

These are the Python package's defaults, so an R producer and a Python producer
classify the same failure the same way.

```r
condition_failure(validation_error("age", -1))
#> <failure_metadata: kind = permanent, retryable = FALSE, retry_after_seconds = NULL>

is_retryable(host_unreachable_error("api.example.com"))
#> [1] NA
```

## Attaching the backend's answer

When the code that catches a failure knows more -- an HTTP 503 with a
`Retry-After` header, a database error code for a deadlock -- it attaches that
knowledge:

```r
call_api <- function(url) {
  response <- list(status = 503L, retry_after = 30)   # stand-in for an HTTP call
  if (response$status >= 500L) {
    err <- api_error(url, status_code = response$status)
    stop(with_failure_metadata(err, failure_metadata(
      "transient",
      retryable = TRUE,
      retry_after_seconds = response$retry_after
    )))
  }
  response
}
```

`with_failure_metadata()` returns the condition, so it can be applied inline
before `stop()`.

## Reading it back

`condition_failure()` returns the metadata, or `NULL` for a condition dataexcept
did not classify. `is_retryable()` answers the common question as `TRUE`,
`FALSE` or `NA`:

```r
retry <- function(f, attempts = 3) {
  for (i in seq_len(attempts)) {
    result <- tryCatch(f(), dataexcept_error = identity)
    if (!inherits(result, "dataexcept_error")) return(result)
    if (!isTRUE(is_retryable(result))) stop(result)
    delay <- condition_failure(result)$retry_after_seconds
    Sys.sleep(if (is.null(delay)) 1 else delay)
  }
  stop(result)
}
```

Only a definite `TRUE` retries here. `NA` means the failure is unclassified,
and retrying unclassified failures would also retry the permanent ones.

## In the envelope

The metadata is written as the envelope's `failure` record. A condition
dataexcept did not classify, such as a base R `simpleError`, has no `failure`
record at all, and the absence is information: it means unclassified, not "not
retryable".

```json
"failure": {
  "kind": "transient",
  "retryable": true,
  "retry_after_seconds": 30
}
```

A failure record read from an envelope comes back as metadata on the R
condition, so `is_retryable()` works on failures that crossed from Python too.
