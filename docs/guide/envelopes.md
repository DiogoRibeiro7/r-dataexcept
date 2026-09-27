# Envelopes

An envelope is the language-neutral record of a failure, defined by the JSON
Schema the Python DataExcept package publishes (`envelope-1.0.0.json`, draft
2020-12). A copy ships with this package: `envelope_schema()` returns it, and
`system.file("schema", "envelope-1.0.0.json", package = "dataexcept")` gives
its path for an external validator.

## Writing

`condition_to_json()` writes any condition, with the chain of conditions behind
it. `condition_to_envelope()` returns the same structure as an R list.

```r
root <- simpleError("connection reset by peer")
err <- query_execution_error("SELECT * FROM orders", parent = root)

cat(condition_to_json(err, pretty = TRUE))
```

```json
{
  "type": "QueryExecutionError",
  "module": "dataexcept",
  "message": "Query failed: SELECT * FROM orders (connection reset by peer)",
  "failure": {
    "kind": "unknown",
    "retryable": null,
    "retry_after_seconds": null
  },
  "attributes": {
    "query": "SELECT * FROM orders"
  },
  "cause": {
    "type": "simpleError",
    "module": "base",
    "message": "connection reset by peer"
  }
}
```

### What goes where

| Field | Written from |
| --- | --- |
| `type` | The dataexcept type, or else the condition's most specific R class (`simpleError`, `rlang_error`, `myapp_error`). |
| `module` | `"dataexcept"` for dataexcept conditions; `"base"` for base R's own condition classes; the package for a class named with its package prefix (`rlang_error` belongs to rlang); otherwise `"unknown"`. |
| `message` | The condition message. For an rlang condition, its own message without the appended parent messages, since those become `cause` records. |
| `failure` | Failure metadata, on dataexcept errors only. Absent on anything dataexcept did not classify. |
| `attributes` | The condition's fields, JSON-safe. Not the message, call, parent or backtrace, and no field whose name starts with `.` or `_`. |
| `cause` | The condition in `parent`, written the same way, to `max_depth` levels. |

### Values JSON cannot hold

Attributes are written in a strict JSON-safe form. Nothing is dropped; a value
that cannot be represented becomes a description of itself:

| R value | Written as |
| --- | --- |
| `NA` | `null` |
| `NaN`, `Inf`, `-Inf` | `"nan"`, `"inf"`, `"-inf"`, as the Python serializer writes them |
| length-one vector | a scalar |
| longer vector (up to 100 elements) | an array; a named vector becomes an object |
| longer than 100 elements | `"<integer vector of length 1000>"` |
| data frame, matrix | `"<data.frame: 150 rows x 5 columns>"`, `"<matrix: 2 x 2 integer>"` |
| function, environment | `"<function>"`, `"<environment>"` |
| `Date`, `POSIXct` | ISO 8601 strings, times in UTC |
| factor | its labels |
| a condition | its message |

A field that is a list by meaning should stay an array even when it has one
element. Wrap it in `I()`, as jsonlite does; the constructors do this for the
fields Python always writes as lists, such as the `expected` types of
`dtype_mismatch_error()`.

Numbers are written to the shortest precision that reads back as the same
double, so `0.1 + 0.2` is written as `0.30000000000000004`, not `0.3`.

### Depth and size

`max_depth` (default 8) limits how many chained causes are rendered. A cause
beyond it is replaced by the truncation marker, `{"truncated": true}`, so a
reader can tell a cut-off chain from a complete one.

`include_attributes = FALSE` omits the attributes, for logs that should carry
identity and classification only.

### Redaction on the way out

Every URL in the message, in attribute values and in attribute names loses its
credentials and its path before it is written. See [Redaction](redaction.md).

## Reading

`envelope_to_condition()` accepts JSON text or a parsed list, validates it, and
returns an R condition:

- It always has class `dataexcept_remote_condition`, plus `error` (or
  `warning`, for a warning written by this package) and `condition`.
- When the envelope names a dataexcept type, from either language, it also gets
  that type's R classes. A Python `ValidationError` becomes a
  `dataexcept_validation_error`, and local handlers catch it.
- Attributes become fields (`cnd$field`), except any that would collide with
  `message`, `call` or `parent`.
- `cause` becomes `parent`; the failure record becomes failure metadata.

```r
json <- '{"type": "ValidationError", "module": "dataexcept.exceptions.validation",
          "message": "Validation failed for field \'age\': -1",
          "failure": {"kind": "permanent", "retryable": false, "retry_after_seconds": null},
          "attributes": {"field": "age", "value": -1}}'

cnd <- envelope_to_condition(json)
cnd$value
#> [1] -1
is_retryable(cnd)
#> [1] FALSE
```

Written back with `condition_to_json()`, a condition read this way reproduces
the envelope it came from, including context, exception-group members, and the
cycle and truncation markers a Python producer can emit. The test suite checks
this against every reference fixture the Python package publishes.

## Validating

`validate_envelope()` checks a payload against the schema's rules without a
JSON Schema validator: each node is exactly one of an exception record, a cycle
record or a truncation marker; identity fields are strings; a failure record
has all three of its fields with valid values; the two markers carry nothing
else. Fields the schema does not know are accepted, because a newer producer
may add them.

```r
is_envelope('{"type": "ValueError", "module": "builtins", "message": "bad row"}')
#> [1] TRUE

validate_envelope('{"truncated": true, "type": "ValueError"}')
#> Error: Invalid envelope:
#> * $: a truncation marker carries no other field, found ['type']
```

A payload that fails is reported as a `dataexcept_envelope_error`, which lists
every problem in its `problems` field and is classified as permanent: reading
the same bytes again cannot succeed.

## Untrusted input

Envelopes often come from another process, so reading them is bounded. A
chain of causes, contexts or group members nested more than `max_depth`
levels deep (default 32) is rejected before it is walked, and JSON text nested
deeper than a valid envelope could need is rejected before it is parsed:

```r
deep <- paste0(
  strrep('{"type": "E", "module": "m", "message": "x", "cause": ', 5000),
  '{"truncated": true}',
  strrep("}", 5000)
)
is_envelope(deep)
#> [1] FALSE
```

Envelopes written with either package's default depth of 8 are far inside the
limit. Nothing in an envelope is evaluated, and its `type` and `module` never
become R classes except through dataexcept's own registry. See the project's
[security policy](https://github.com/DiogoRibeiro7/r-dataexcept/blob/main/SECURITY.md)
for what redaction does and does not cover.
