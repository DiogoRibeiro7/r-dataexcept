# Working with Python

The envelope exists so that a failure raised in one language can be read,
triaged and handled in the other. The Python DataExcept package writes
envelopes with `exception_to_json()`; this package reads them with
`envelope_to_condition()` and writes its own with `condition_to_json()`.

## From Python to R

A Python job records each failure as one line of JSON:

```python
from dataexcept import (
    FailureMetadata, MissingColumnError, ServiceTimeoutError, ValidationError,
    exception_to_json,
)

failures = [
    MissingColumnError("customer_id", dataframe="orders"),
    ServiceTimeoutError("payments", timeout_seconds=30.0).with_failure_metadata(
        FailureMetadata(failure_kind="transient", retryable=True, retry_after_seconds=5.0)
    ),
    ValidationError("age", -1),
]

with open("failures.jsonl", "w") as log:
    for exc in failures:
        log.write(exception_to_json(exc) + "\n")
```

An R job reads the log back into conditions and handles them with ordinary R
handlers, by class and by failure metadata:

```r
library(dataexcept)

failures <- lapply(readLines("failures.jsonl"), envelope_to_condition)

for (failure in failures) {
  tryCatch(
    stop(failure),
    dataexcept_data_frame_error = function(e) {
      message("fix the data: ", conditionMessage(e))
    },
    dataexcept_error = function(e) {
      if (isTRUE(is_retryable(e))) {
        message("retry in ", condition_failure(e)$retry_after_seconds, "s: ", conditionMessage(e))
      } else {
        message("give up: ", conditionMessage(e))
      }
    }
  )
}
#> fix the data: [MissingColumnError] Missing required column 'customer_id' in DataFrame 'orders'
#> retry in 5s: Operation timed out after 30.0s on service 'payments'.
#> give up: Validation failed for field 'age': -1
```

Three things carried across:

- **Classes.** The Python `MissingColumnError` is an R
  `dataexcept_missing_column_error`, so the data frame handler caught it.
  `ServiceTimeoutError` has no R class, but it comes from a DataExcept module,
  so it is still a `dataexcept_error`.
- **Failure metadata.** The retry delay the Python side attached is read by
  `condition_failure()`.
- **Fields.** Attributes become fields: the first failure's `e$column` is
  `"customer_id"`.

For a summary rather than handling, `condition_type()` gives each failure's
type:

```r
vapply(failures, condition_type, character(1))
#> [1] "MissingColumnError"  "ServiceTimeoutError" "ValidationError"
```

## From R to Python

`condition_to_json()` writes one line per failure the same way:

```r
cat(condition_to_json(missing_column_error("customer_id", dataframe = "orders")), "\n",
    file = "failures.jsonl", append = TRUE)
```

The Python package produces envelopes and publishes the schema; it has no
reader of its own, so a Python consumer works with the parsed dictionary. The
fields it keys on are the ones both languages share:

```python
import json

with open("failures.jsonl") as log:
    for line in log:
        envelope = json.loads(line)
        failure = envelope.get("failure")
        if envelope["type"] == "MissingColumnError":
            print("fix the data:", envelope["attributes"]["column"])
        elif failure and failure["retryable"] is True:
            print("retry:", envelope["message"])
```

## What is shared, and what is not

| | Shared across languages | Differs |
| --- | --- | --- |
| `type` | Leaf types have the same names: `MissingColumnError`, `ConvergenceError`, `ApiError`, and so on. `dataexcept_classes()` marks each type R shares with Python. | R has two base types of its own, `DataFrameError` and `FileError`, where Python has `PandasError` and `CustomIOError`. Python's `ValidationError` is a `JobError`; R's is a direct child of `DataExceptError`. Python defines more types than R; a type R does not define is read back as a plain `dataexcept_error`. |
| `module` | Starts with `dataexcept` for DataExcept types in both languages. | R writes `"dataexcept"`; Python writes its module path, such as `"dataexcept.pandas_exceptions"`. |
| `message` | The same wording, tested for every shared type against messages the Python package produced. | Some Python classes prefix the message with `[TypeName]`; R does not, since `type` already says it. R writes a whole number without `.0`, and a vector value as R code. |
| `failure` | Same fields, values and class defaults. | -- |
| `attributes` | The same field names and values for shared types. | Python includes a `message` attribute on some classes, and keeps the underlying exception in `original` or `cause`; R keeps the message in `message` only, and the underlying condition in the `cause` record only. |

Consumers should key on `type` and `failure`, and should ignore fields they do
not recognise; the schema allows a newer producer to add them.
