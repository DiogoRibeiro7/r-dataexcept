# dataexcept

<!-- badges: start -->
[![R-CMD-check](https://github.com/DiogoRibeiro7/r-dataexcept/actions/workflows/R-CMD-check.yml/badge.svg)](https://github.com/DiogoRibeiro7/r-dataexcept/actions/workflows/R-CMD-check.yml)
[![test-coverage](https://github.com/DiogoRibeiro7/r-dataexcept/actions/workflows/test-coverage.yml/badge.svg)](https://github.com/DiogoRibeiro7/r-dataexcept/actions/workflows/test-coverage.yml)
[![lint](https://github.com/DiogoRibeiro7/r-dataexcept/actions/workflows/lint.yml/badge.svg)](https://github.com/DiogoRibeiro7/r-dataexcept/actions/workflows/lint.yml)
[![envelope-contract](https://github.com/DiogoRibeiro7/r-dataexcept/actions/workflows/envelope-contract.yml/badge.svg)](https://github.com/DiogoRibeiro7/r-dataexcept/actions/workflows/envelope-contract.yml)
[![docs](https://github.com/DiogoRibeiro7/r-dataexcept/actions/workflows/docs.yml/badge.svg)](https://diogoribeiro7.github.io/r-dataexcept/)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R >= 4.1](https://img.shields.io/badge/R-%E2%89%A5%204.1-276DC3.svg)](https://www.r-project.org/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.md)
<!-- badges: end -->

Structured, classed failures for R data and modelling code, in a format shared
with the Python [DataExcept](https://github.com/DiogoRibeiro7/DataExcept)
package.

R already has classed conditions: `errorCondition()` and `rlang::abort()` both
create errors with a class and fields. What dataexcept adds is the part that
does not exist yet:

- **One failure format across R and Python.** Any R condition can be written
  as the *envelope* DataExcept publishes as a JSON Schema, and an envelope
  written by Python can be read back into an R condition that ordinary R
  handlers catch. A mixed R/Python pipeline logs one failure format.
- **Classes for base R's text-only warnings.** `glm.fit` non-convergence,
  perfect separation, `NAs introduced by coercion` and others arrive as plain
  `simpleWarning`s, recognisable only by their text, and that text is
  translated into the session language. dataexcept recognises them through
  R's own message catalogue, so the match works in any language.
- **A shared vocabulary of errors** with structured fields and recovery
  metadata: whether a failure is transient or permanent, and whether a retry
  can succeed.
- **Failure events and traces.** Operation context, JSON failure events for
  logs, and OpenTelemetry recording, all in the Python package's format.

Credentials in URLs are removed before they reach a condition or an envelope,
using the same rules as the Python package.

Documentation: <https://diogoribeiro7.github.io/r-dataexcept/>

## Installation

```r
# install.packages("pak")
pak::pak("DiogoRibeiro7/r-dataexcept@v0.2.0")   # the latest release
pak::pak("DiogoRibeiro7/r-dataexcept")          # the development version
```

dataexcept depends on base R (>= 4.1) and jsonlite.

## Classed errors with fields

Constructors return a condition; `stop()` signals it. Handlers catch by class,
including a whole family through its parent class, and read the fields
directly.

```r
library(dataexcept)

orders <- data.frame(id = 1:3, amount = c("10", "20", "30"))

check_amount <- function(df) {
  if (!"amount" %in% names(df)) {
    stop(missing_column_error("amount", dataframe = "orders"))
  }
  if (!is.numeric(df$amount)) {
    stop(dtype_mismatch_error("amount", "numeric", class(df$amount)[1]))
  }
  invisible(df)
}

err <- tryCatch(check_amount(orders), dataexcept_data_frame_error = identity)
conditionMessage(err)
#> [1] "Column 'amount' has type character; expected numeric"
err$found
#> [1] "character"
```

`dataexcept_classes()` lists every type: data frame errors (missing column,
type mismatch, merge keys), data and modelling errors (loading, missing data,
training, convergence, prediction), file, database, network and API errors.
`new_dataexcept_error()` defines your own.

## Failure metadata

Every dataexcept error says whether retrying can help. The default is
conservative -- `"unknown"`, with `retryable` `NULL`, which is deliberately not
`FALSE` -- and code that knows the backend's answer attaches it.

```r
err <- api_error("https://api.example.com/v1/orders?page=2&api_key=abc123",
                 status_code = 503L)
err <- with_failure_metadata(
  err,
  failure_metadata("transient", retryable = TRUE, retry_after_seconds = 30)
)

is_retryable(err)
#> [1] TRUE
conditionMessage(err)
#> [1] "API call failed: https://api.example.com/v1/orders?page=2&api_key=*** (status 503)"
```

## The envelope

`condition_to_json()` writes any condition -- a dataexcept error, a base R
`simpleError`, an rlang error -- with its chain of causes:

```r
cat(condition_to_json(err, pretty = TRUE))
```

```json
{
  "type": "ApiError",
  "module": "dataexcept",
  "message": "API call failed: https://api.example.com/***?page=2&api_key=*** (status 503)",
  "failure": {
    "kind": "transient",
    "retryable": true,
    "retry_after_seconds": 30
  },
  "attributes": {
    "endpoint": "https://api.example.com/***?page=2&api_key=***",
    "status_code": 503
  }
}
```

Envelopes are strict JSON and follow the published schema,
`envelope-1.0.0.json`, which ships with the package (`envelope_schema()`).
Text leaving R is redacted again, this time including URL paths.

`envelope_to_condition()` reads an envelope from either language. A Python
`MissingColumnError` becomes an R `dataexcept_missing_column_error`, so the
handler written for local failures catches it:

```r
json <- '{
  "type": "MissingColumnError",
  "module": "dataexcept.pandas_exceptions",
  "message": "[MissingColumnError] Missing required column customer_id",
  "failure": {"kind": "unknown", "retryable": null, "retry_after_seconds": null},
  "attributes": {"column": "customer_id", "dataframe": null}
}'

cnd <- envelope_to_condition(json)
tryCatch(stop(cnd), dataexcept_data_frame_error = function(e) e$column)
#> [1] "customer_id"
```

Written back, a condition read this way reproduces its envelope exactly, and
`validate_envelope()` checks a payload against the schema's rules without
needing a JSON Schema validator.

## Observability

An operation context records where a failure happened, separately from what
failed, with the fields and rules of the Python package's `OperationContext`.
`condition_to_event_json()` writes both as one line of JSON for a log:

```r
context <- operation_context(system = "batch", operation = "settle_invoices", job_id = "job-42")

tryCatch(
  settle_invoices(),
  dataexcept_error = function(e) {
    cat(condition_to_event_json(e, operation_context = context), "\n", file = stderr())
    stop(e)
  }
)
```

With the r-lib [otel](https://otel.r-lib.org/) package, `record_otel_exception()`
records a failure on the active span, with the attribute names the Python
package uses, and `operation_context_from_otel()` puts the span's trace and
span IDs into the context so logs and traces correlate. Recording through
dataexcept keeps credentials out of the trace: the otel SDK records an
exception by printing the condition, unredacted, and dataexcept's attributes
replace those fields.

## Classed warnings from base R

```r
separated <- data.frame(y = c(0, 0, 1, 1), x = 1:4)

fit <- withCallingHandlers(
  with_classed_warnings(glm(y ~ x, family = binomial, data = separated)),
  dataexcept_separation_warning = function(w) {
    message("Perfect separation in the logistic fit")
    invokeRestart("muffleWarning")
  }
)
#> Perfect separation in the logistic fit
```

The same code works in a German session, where the warning reads
*glm.fit: Angepasste Wahrscheinlichkeiten mit numerischem Wert 0 oder 1
aufgetreten*: each warning is compared with its template translated through the
catalogue R used to write it. `classed_warning_rules()` lists what is
recognised. A handler can also fail closed, turning non-convergence into a
`convergence_error()` with the warning as its cause.

## How the R and Python packages stay in step

- The schema and the reference fixtures in `inst/schema/` are the Python
  package's. The tests read every fixture into R and write it back unchanged.
- Redaction is tested against the Python implementation's own output on a set
  of awkward URLs, and must match it character for character.
- `validate_envelope()` is tested against the verdicts of a JSON Schema
  validator on valid and invalid payloads.
- In CI, every envelope R writes is validated against the schema by
  Python's `jsonschema`, and a weekly job regenerates the fixtures from
  DataExcept's main branch and fails if anything has moved.

Differences from the Python package are deliberate and few:

- R has two base classes of its own, `dataexcept_data_frame_error` and
  `dataexcept_file_error`, where Python has `PandasError` and `CustomIOError`.
  Leaf types have the same names in both languages.
- R messages do not carry the `[TypeName]` prefix some Python classes add;
  the envelope's `type` field already says it.
- R-written envelopes use `"dataexcept"` as the `module` of a dataexcept
  condition. Python uses its module path, such as
  `"dataexcept.pandas_exceptions"`. The reader accepts both.

## Related work

rlang provides classed errors, chained causes and backtraces, and dataexcept
works with it: an rlang error serialises like any other condition, with its
parent chain as the envelope's causes. dataexcept does not replace rlang; it
adds the cross-language format and the vocabulary.

## Contributing

Bug reports, condition types and warning rules are welcome. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the development setup and the checks a
pull request needs, and [SECURITY.md](SECURITY.md) for reporting a
vulnerability privately.

Please note that this project is released with a
[Contributor Code of Conduct](CODE_OF_CONDUCT.md). By participating in it you
agree to abide by its terms.

## Citation

```r
citation("dataexcept")
```

Citation metadata is also available in [CITATION.cff](CITATION.cff).

## License

MIT © Diogo Ribeiro
