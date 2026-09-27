# Classed errors

A dataexcept error is an ordinary R condition. Its fields are list elements, so
a handler reads them directly (`cnd$column`). Its classes are what `tryCatch()`
and `withCallingHandlers()` match. Its cause sits in `parent`, the field rlang
also uses, so rlang prints the chain as "Caused by error".

Constructors return the condition; you decide how to signal it.

```r
cnd <- missing_column_error("customer_id", dataframe = "orders")

class(cnd)
#> [1] "dataexcept_missing_column_error" "dataexcept_data_frame_error"
#> [3] "dataexcept_error"                "error"
#> [5] "condition"

stop(cnd)
#> Error: Missing required column 'customer_id' in data frame 'orders'
```

## The hierarchy

Every class starts with `dataexcept_`, followed by the snake_case form of its
envelope type. Handlers can catch a single failure or a whole family.

| Family (catch this class) | Constructors | Envelope types |
| --- | --- | --- |
| `dataexcept_validation_error` | `validation_error()` | `ValidationError` |
| `dataexcept_data_frame_error` | `missing_column_error()`, `dtype_mismatch_error()`, `merge_key_error()` | `MissingColumnError`, `DtypeMismatchError`, `MergeKeyError` |
| `dataexcept_data_science_error` | `data_loading_error()`, `missing_data_error()`, `model_training_error()`, `convergence_error()`, `prediction_error()` | `DataLoadingError`, `MissingDataError`, `ModelTrainingError`, `ConvergenceError`, `PredictionError` |
| `dataexcept_file_error` | `file_read_error()`, `file_write_error()` | `FileReadError`, `FileWriteError` |
| `dataexcept_database_error` | `database_connection_error()`, `query_execution_error()` | `DatabaseConnectionError`, `QueryExecutionError` |
| `dataexcept_network_error` | `host_unreachable_error()`, `connection_timeout_error()` | `HostUnreachableError`, `ConnectionTimeoutError` |
| `dataexcept_pipeline_error` | `api_error()` | `ApiError` |

`convergence_error()` also inherits from `dataexcept_model_training_error`, so a
handler for training failures catches non-convergence too. `dataexcept_error`
catches everything.

```r
fit_or_fail <- function(formula, data, maxit = 25) {
  fit <- suppressWarnings(glm(formula,
    family = binomial, data = data,
    control = glm.control(maxit = maxit)
  ))
  if (!fit$converged) {
    stop(convergence_error("glm", iterations = fit$iter))
  }
  fit
}

separated <- data.frame(y = c(0, 0, 1, 1), x = 1:4)
tryCatch(
  fit_or_fail(y ~ x, separated, maxit = 5),
  dataexcept_model_training_error = function(e) e$iterations
)
#> [1] 5
```

`dataexcept_classes()` returns the full table, with each type's parent, its
default failure classification, and whether the same type exists in Python.

## Fields

Constructors validate their arguments and store them unchanged:

```r
err <- dtype_mismatch_error("amount", expected = c("numeric", "integer"), found = "character")
err$expected
#> [1] "numeric" "integer"
```

A wrong argument type is a programming mistake, not an operational failure, so
it raises a plain error outside the hierarchy:

```r
missing_column_error(1)
#> Error: `column` must be a single string.
```

## Causes

Pass the underlying condition as `parent`. Where the Python class appends the
cause's message, the R constructor does too:

```r
read_orders <- function(path) {
  tryCatch(
    read.csv(path),
    error = function(e) stop(file_read_error(path, parent = e)),
    warning = function(w) stop(file_read_error(path, parent = w))
  )
}

err <- tryCatch(read_orders("missing.csv"), error = identity)
conditionMessage(err)
#> [1] "Failed to read file 'missing.csv': cannot open file 'missing.csv': No such file or directory"
class(err$parent)
#> [1] "simpleWarning" "warning"       "condition"
```

The envelope writes the parent as the record's `cause`, so the chain survives
serialisation.

## The call

Constructors default to `call = NULL`, so the error prints without a call. To
report the call of the function that signals the error, pass `sys.call()`:

```r
check_age <- function(age) {
  if (age < 0) stop(validation_error("age", age, call = sys.call()))
  age
}
check_age(-1)
#> Error in check_age(-1) : Validation failed for field 'age': -1
```

## Your own errors

`new_dataexcept_error()` is the constructor every error above is built with.
Give it an envelope type, an R class, fields and, if you know it, the failure
classification:

```r
quota_error <- function(used, limit) {
  new_dataexcept_error(
    sprintf("Quota exceeded: %d of %d requests used", used, limit),
    used = used,
    limit = limit,
    type = "QuotaExceededError",
    class = "myapp_quota_exceeded_error",
    failure = failure_metadata("transient", retryable = TRUE)
  )
}

err <- quota_error(1000L, 1000L)
inherits(err, "dataexcept_error")
#> [1] TRUE
is_retryable(err)
#> [1] TRUE
```

A registered `type` supplies its classes behind yours, so
`new_dataexcept_error("...", type = "ValidationError", class = "myapp_error")`
is also caught as a `dataexcept_validation_error`.

## Working with rlang

dataexcept conditions can be signalled with `rlang::abort()` as well as
`stop()`, and rlang conditions can be written to an envelope like any other.
rlang's own fields (the backtrace, its internal state) are left out of the
envelope's attributes, and its parent chain becomes the chain of `cause`
records.
