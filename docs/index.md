---
hide:
  - navigation
  - toc
---

<div class="dx-hero" markdown="1">

<p class="dx-kicker">R package · companion to DataExcept for Python</p>

# Failures that say what went wrong, in R and Python alike

dataexcept gives R data and modelling code classed errors with structured
fields and recovery metadata, writes any R condition in the failure format the
Python DataExcept package publishes, and reads that format back into
conditions ordinary R handlers catch.

[Get started](getting-started.md){ .md-button .md-button--primary }
[Read the guide](guide/errors.md){ .md-button }

</div>

<div class="dx-cards" markdown="1">

<div markdown="1">

### Classed errors with fields

A missing column, a type mismatch, a model that did not converge, an API that
returned 503: each is a condition with its own class and the values that
explain it, and each says whether a retry can help.

</div>

<div markdown="1">

### One format with Python

`condition_to_json()` writes the envelope defined by DataExcept's JSON Schema.
`envelope_to_condition()` reads one written by Python, and a Python
`MissingColumnError` is caught by the same R handler as a local one.

</div>

<div markdown="1">

### Warnings in any language

Base R reports non-convergence, separation and coercion as plain warnings.
`with_classed_warnings()` gives them classes, recognising each through R's own
translated message catalogue, so it works in a German session too.

</div>

</div>

## What it looks like

```r
library(dataexcept)

check_amount <- function(df) {
  if (!is.numeric(df$amount)) {
    stop(dtype_mismatch_error("amount", "numeric", class(df$amount)[1]))
  }
  invisible(df)
}

orders <- data.frame(id = 1:3, amount = c("10", "20", "30"))
err <- tryCatch(check_amount(orders), dataexcept_data_frame_error = identity)

err$found
#> [1] "character"
cat(condition_to_json(err, pretty = TRUE))
```

```json
{
  "type": "DtypeMismatchError",
  "module": "dataexcept",
  "message": "Column 'amount' has type character; expected numeric",
  "failure": {
    "kind": "unknown",
    "retryable": null,
    "retry_after_seconds": null
  },
  "attributes": {
    "column": "amount",
    "expected": ["numeric"],
    "found": "character"
  }
}
```

## Why it exists

R already has classed conditions: `errorCondition()` and `rlang::abort()` both
create errors with a class and fields. What R does not have is a shared
vocabulary for the failures data code meets, a way to say whether a failure is
worth retrying, or a failure format that a Python service reading the same
logs understands. dataexcept adds those three things and nothing else. It
imports only jsonlite, works alongside rlang, and redacts credentials in URLs
before they reach a condition or a log.

The envelope contract belongs to the Python package: its published schema and
reference fixtures ship with this one, and the test suite reads every fixture
into R and writes it back unchanged. See [Architecture](architecture.md) for
how R conditions map onto it.
