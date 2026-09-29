# Getting started

## Installation

dataexcept is installed from GitHub, either the latest release or the
development version:

```r
# install.packages("pak")
pak::pak("DiogoRibeiro7/r-dataexcept@v0.3.0")
pak::pak("DiogoRibeiro7/r-dataexcept")
```

Each release is also on the
[releases page](https://github.com/DiogoRibeiro7/r-dataexcept/releases) as a
source tarball, for `install.packages(path, repos = NULL)`.

It needs R 4.1 or later and imports only jsonlite. rlang is optional: when it is
installed, rlang errors serialise with their own message and their parent chain.

## Signal a classed error

Each constructor returns a condition without signalling it. Signal it with
`stop()`, as you would a condition from `errorCondition()`:

```r
library(dataexcept)

load_orders <- function(df) {
  if (!"customer_id" %in% names(df)) {
    stop(missing_column_error("customer_id", dataframe = "orders"))
  }
  df
}

load_orders(data.frame(id = 1:3))
#> Error: Missing required column 'customer_id' in data frame 'orders'
```

## Handle it by class

The constructor's arguments are fields of the condition, and its classes are
what `tryCatch()` matches. A handler for a parent class catches the whole
family:

```r
result <- tryCatch(
  load_orders(data.frame(id = 1:3)),
  dataexcept_data_frame_error = function(e) {
    message("Missing column: ", e$column)
    NULL
  }
)
#> Missing column: customer_id
```

`dataexcept_error` catches every error the package defines.
[`dataexcept_classes()`](reference/dataexcept_classes.md) lists them all.

## Ask whether a retry can help

Every dataexcept error carries failure metadata. The default is `"unknown"`;
code that knows the backend's answer attaches it:

```r
err <- api_error("https://api.example.com/v1/orders", status_code = 503L)
err <- with_failure_metadata(
  err,
  failure_metadata("transient", retryable = TRUE, retry_after_seconds = 30)
)

is_retryable(err)
#> [1] TRUE
```

## Write it for a log

`condition_to_json()` writes any condition, dataexcept or not, as a
DataExcept envelope:

```r
cat(condition_to_json(err))
#> {"type":"ApiError","module":"dataexcept","message":"API call failed: https://api.example.com/*** (status 503)",
#>  "failure":{"kind":"transient","retryable":true,"retry_after_seconds":30},
#>  "attributes":{"endpoint":"https://api.example.com/***","status_code":503}}
```

(Output wrapped for reading.) URL paths are removed on export, as the Python
package does, because a path can itself be a secret.

## Read one written by Python

```r
json <- '{"type": "MissingColumnError", "module": "dataexcept.pandas_exceptions",
          "message": "[MissingColumnError] Missing required column \'customer_id\'",
          "failure": {"kind": "unknown", "retryable": null, "retry_after_seconds": null},
          "attributes": {"column": "customer_id", "dataframe": "orders"}}'

cnd <- envelope_to_condition(json)
tryCatch(stop(cnd), dataexcept_data_frame_error = function(e) e$dataframe)
#> [1] "orders"
```

## Next steps

- [Classed errors](guide/errors.md): the hierarchy, custom errors, causes and calls.
- [Envelopes](guide/envelopes.md): exactly what is written, and how reading works.
- [Classed warnings](guide/warnings.md): handling base R's warnings by class.
- [API reference](reference/index.md): every function.
