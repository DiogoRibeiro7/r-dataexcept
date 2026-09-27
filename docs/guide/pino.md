# Logging for Pino

A failure in an R job often ends up in front of a Node.js service: read off a
queue, returned over HTTP, or tailed from a shared log stream. If that service
logs with [Pino](https://getpino.io), it expects an error under its `err` key
with `type`, `message` and, optionally, `stack` -- the fields Pino's own error
serializer writes, and the ones pino-pretty, transports and error trackers
read.

`condition_to_pino()` writes a condition in that shape: the **Pino profile**
the Python DataExcept package publishes as `pino-1.0.0.json`. It is a
projection of the [envelope](envelopes.md), not a replacement for it, so R,
Python and Node agree on one failure record and Pino gets it in the shape it
already knows.

```r
cnd <- tryCatch(
  stop(condition_group(list(
    missing_column_error("customer_id", dataframe = "orders"),
    validation_error("amount", -5)
  ), "orders failed validation")),
  error = identity
)

cat(condition_to_pino_json(cnd, pretty = TRUE))
```

```json
{
  "type": "ConditionGroup",
  "module": "dataexcept",
  "message": "orders failed validation (2 failures)",
  "failure": { "kind": "unknown", "retryable": null, "retry_after_seconds": null },
  "errors": [
    {
      "type": "MissingColumnError",
      "module": "dataexcept",
      "message": "Missing required column 'customer_id' in data frame 'orders'",
      "attributes": { "column": "customer_id", "dataframe": "orders" },
      "failure": { "kind": "unknown", "retryable": null, "retry_after_seconds": null }
    },
    {
      "type": "ValidationError",
      "module": "dataexcept",
      "message": "Validation failed for field 'amount': -5",
      "attributes": { "field": "amount", "value": -5 },
      "failure": { "kind": "permanent", "retryable": false, "retry_after_seconds": null }
    }
  ]
}
```

## What the projection changes

Three things, and nothing else:

| Envelope | Pino profile | Why |
| --- | --- | --- |
| `exceptions` | `errors` | What JavaScript's `AggregateError` calls the same thing. |
| -- | `stack` | Written only when a real stack exists. Never made up. |
| `attributes` | `attributes` | Kept nested, not spread onto the error, so an attribute called `type` or `stack` cannot overwrite the fields a consumer reads. |

`type`, `module`, `message`, `failure`, `cause`, `context` and the cycle and
truncation markers come through unchanged, with the envelope's redaction
already applied.

## A Pino log line from R

Pino writes one JSON object per line, with the error under `err`. An R job
writing to the same stream can do the same:

```r
line <- sprintf(
  '{"level":50,"time":%.0f,"msg":"ingest failed","err":%s}',
  as.numeric(Sys.time()) * 1000,
  condition_to_pino_json(cnd)
)
writeLines(line, log_connection)
```

Level 50 is Pino's `error`. A Node service that tails the stream, or
pino-pretty reading it, sees an ordinary Pino error.

## The stack

Pino consumers treat `stack` as ground truth, which is why it is never
guessed. In R, the real stack is an rlang backtrace: the one
`rlang::abort()` records, or the one `rlang::global_entrace()` adds to base R
errors. `include_stack = TRUE` writes it, redacted like every other exported
string:

```r
inner <- function() rlang::abort("rates API returned 503")
fetch <- function() inner()
cnd <- tryCatch(fetch(), error = identity)

cat(condition_to_pino(cnd, include_stack = TRUE)$stack)
#>     x
#>  1. +-base::tryCatch(fetch(), error = identity)
#>  ...
#>  5. \-global fetch()
#>  6.   \-global inner()
#>  7.     \-rlang::abort("rates API returned 503")
```

A condition without a backtrace gets no `stack`. The call a base R error
records is not a stack, and is not written as one.

## An envelope already in hand

`envelope_to_pino()` projects an envelope directly: one read from a queue as
JSON, or a list from `condition_to_envelope()`. Pass `stack` when a stack
arrived with it:

```r
envelope_to_pino(json_from_queue, stack = received_stack)
```

## Tested against Python

Every reference envelope fixture the Python package publishes has its Pino
projection published beside it, and both ship with this package under
`schema/fixtures/` and `schema/fixtures/pino/`. The test suite requires
`envelope_to_pino()` to reproduce each projection exactly, from the JSON text
and from the parsed list, and `condition_to_pino()` to reproduce it from the
condition read back from the envelope. `pino_schema()` returns the profile's
JSON Schema.
