# Groups and wrapping

Two patterns come up in almost every pipeline: a check that finds several
problems and should report all of them, and a call into other code whose
errors should become your own. `condition_group()` and `collect_errors()`
handle the first; `wrap_errors()` handles the second.

## Reporting several failures at once

A validation step that stops at the first problem makes the user fix one thing
at a time. `collect_errors()` runs each of its arguments in turn, catches any
error one of them signals, and carries on with the next:

```r
orders <- data.frame(id = 1:3, amount = c("10", "20", "30"))

check_orders <- function(df) {
  collect_errors(
    customer_id = if (!"customer_id" %in% names(df)) {
      stop(missing_column_error("customer_id", dataframe = "orders"))
    },
    amount = if (!is.numeric(df$amount)) {
      stop(dtype_mismatch_error("amount", "numeric", class(df$amount)[1]))
    },
    rows = if (nrow(df) == 0L) stop("orders is empty")
  )
}

errors <- check_orders(orders)
names(errors)
#> [1] "customer_id" "amount"
```

The result is a list of the errors caught, named after the arguments that
signalled them, and empty when every check passed. Warnings and messages pass
through untouched.

`condition_group()` turns the list into one error. Its message counts the
failures, and printing it lists each one:

```r
if (length(errors) > 0) stop(condition_group(errors, "orders failed validation"))
#> Error: orders failed validation (2 failures)
#> * Missing required column 'customer_id' in data frame 'orders'
#> * Column 'amount' has type character; expected numeric
```

A group is caught by `dataexcept_condition_group`, and by `dataexcept_error`
like every other dataexcept error. `group_members()` returns what it holds:

```r
tryCatch(
  stop(condition_group(errors, "orders failed validation")),
  dataexcept_condition_group = function(e) length(group_members(e))
)
#> [1] 2
```

Up to ten members are listed in the message; the rest are counted. Members can
be any condition -- a base R `simpleError` as well as a dataexcept error -- and
their messages are redacted in the listing, as every dataexcept message is.

### The group's failure metadata

A group is retryable only if its members agree that it is. When every member
has the same failure kind and the same `retryable` answer, the group takes
them; when some give a retry delay, the group takes the longest. Otherwise --
a mix of transient and permanent failures, or a member dataexcept never
classified -- the group is `unknown`:

```r
permanent <- condition_group(list(validation_error("age", -1), validation_error("income", NA)))
is_retryable(permanent)
#> [1] FALSE

mixed <- condition_group(list(validation_error("age", -1), simpleError("boom")))
is_retryable(mixed)
#> [1] NA
```

Pass `failure` to decide for yourself.

## Groups in the envelope

A group is written as the envelope's exception group: the `exceptions` array,
with every member rendered in full, causes included. It is the same structure
Python's `ExceptionGroup` produces, so a consumer that reads one reads the
other.

```r
cat(condition_to_json(condition_group(errors, "orders failed validation"), pretty = TRUE))
```

```json
{
  "type": "ConditionGroup",
  "module": "dataexcept",
  "message": "orders failed validation (2 failures)",
  "failure": {
    "kind": "unknown",
    "retryable": null,
    "retry_after_seconds": null
  },
  "exceptions": [
    {
      "type": "MissingColumnError",
      "module": "dataexcept",
      "message": "Missing required column 'customer_id' in data frame 'orders'",
      "failure": { "kind": "unknown", "retryable": null, "retry_after_seconds": null },
      "attributes": { "column": "customer_id", "dataframe": "orders" }
    },
    {
      "type": "DtypeMismatchError",
      "module": "dataexcept",
      "message": "Column 'amount' has type character; expected numeric",
      "failure": { "kind": "unknown", "retryable": null, "retry_after_seconds": null },
      "attributes": { "column": "amount", "expected": ["numeric"], "found": "character" }
    }
  ]
}
```

Each member is one level deeper than the group, so `max_depth` limits nested
groups the way it limits chains of causes.

Reading works the same way in reverse. Any record with an `exceptions` array
becomes a condition of class `dataexcept_condition_group`, a Python
`ExceptionGroup` included:

```r
# An envelope the Python package wrote for an ExceptionGroup of a ValueError
# ("bad row") and an OSError ("disk unavailable").
cnd <- envelope_to_condition(python_json)
class(cnd)
#> [1] "dataexcept_condition_group"  "dataexcept_remote_condition"
#> [3] "error"                       "condition"
conditionMessage(cnd)
#> [1] "parallel failures (2 sub-exceptions)\n* bad row\n* disk unavailable"
```

## Wrapping errors from other code

When your function calls code that fails in its own terms -- a base R error, a
warning from `read.csv()`, an error from a database driver -- the caller
usually wants your failure, with theirs as the cause. The handler for that is
short but repetitive:

```r
tryCatch(
  read.csv(path),
  error = function(e) stop(file_read_error(path, parent = e))
)
```

`wrap_errors()` writes it for you. It evaluates the expression and, if it
signals an error, signals the one `constructor` builds instead, with the
original as its `parent`:

```r
read_orders <- function(path) {
  wrap_errors(read.csv(path), file_read_error, path = path, on = c("error", "warning"))
}

err <- tryCatch(read_orders("missing.csv"), error = identity)
conditionMessage(err)
#> [1] "Failed to read file 'missing.csv': cannot open file 'missing.csv': No such file or directory"
class(err$parent)
#> [1] "simpleWarning" "warning"       "condition"
```

`read.csv()` warns before it fails, so the example wraps warnings too.
With the default `on = "error"`, warnings pass through untouched. `on` takes
any condition classes, including a family: `on = "dataexcept_data_frame_error"`
wraps data frame failures and lets every other error through unchanged.
Interrupts are never wrapped.

The constructor is called with the arguments you give plus `parent`, so any
dataexcept constructor works, and so does your own. `failure` sets the new
error's failure metadata, for when you know more about recovery than the
constructor's default does:

```r
fetch_rates <- function() stop("connection reset by peer")

err <- tryCatch(
  wrap_errors(fetch_rates(), api_error,
    endpoint = "https://api.example.com/v1/rates",
    failure = failure_metadata("transient", retryable = TRUE, retry_after_seconds = 30)
  ),
  error = identity
)
is_retryable(err)
#> [1] TRUE
```

Because the original condition is always the cause, it stays in the envelope,
in rlang's "Caused by" output, and in the events and span attributes of the
[observability](observability.md) functions.
