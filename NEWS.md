# dataexcept (development version)

# dataexcept 0.1.0

First release.

## Classed errors

- Constructors for data frame, data and modelling, file, database, network and
  API failures, each storing its arguments as fields: `validation_error()`,
  `missing_column_error()`, `dtype_mismatch_error()`, `merge_key_error()`,
  `data_loading_error()`, `missing_data_error()`, `model_training_error()`,
  `convergence_error()`, `prediction_error()`, `file_read_error()`,
  `file_write_error()`, `database_connection_error()`,
  `query_execution_error()`, `host_unreachable_error()`,
  `connection_timeout_error()` and `api_error()`.
- `new_dataexcept_error()` defines your own. `dataexcept_classes()` lists the
  hierarchy.
- Leaf type names are shared with the Python DataExcept package.

## Failure metadata

- `failure_metadata()`, `with_failure_metadata()`, `condition_failure()` and
  `is_retryable()`. Validation failures default to permanent and not retryable;
  everything else defaults to unknown, as in the Python package.

## The envelope

- `condition_to_envelope()` and `condition_to_json()` write any condition,
  with its chain of causes, as a DataExcept envelope (schema 1.0.0). Text is
  always valid UTF-8: bytes that are not are replaced, at construction and on
  export.
- `envelope_to_condition()` reads an envelope from either language back into
  an R condition, mapping DataExcept types onto the R classes. A type from a
  DataExcept module that R has no class for, such as Python's
  `ServiceTimeoutError`, is still a `dataexcept_error`, so a
  `dataexcept_error` handler catches it and `is_retryable()` reads its failure
  record.
- `condition_type()` returns the envelope type of any condition, including one
  read from an envelope.
- `validate_envelope()` and `is_envelope()` check a payload against the
  schema's rules. `envelope_schema()` returns the schema.
- Reading untrusted envelopes is bounded by `max_depth` (default 32): a deeper
  chain of records is rejected before it is walked, and JSON nested deeper than
  an envelope could need is rejected before it is parsed, with a
  `dataexcept_envelope_error`.
- All eight of the Python package's reference fixtures round-trip exactly.

## Redaction

- `redact_url()` and `redact_urls_in_text()` port the Python package's rules and
  match its output exactly on the parity cases in the test suite. Conditions are
  redacted at construction and envelopes on export.

## Classed warnings

- `with_classed_warnings()` and `classify_warning()` re-signal fifteen base R
  and stats warning templates -- non-convergence, separation, boundary fits,
  rank-deficient prediction, the chi-squared approximation, zero variance,
  coercion, recycling, `NaN` production and non-numeric arguments -- as classed
  warnings, recognised in any session language. `classed_warning_rules()`
  lists them.

## Documentation and project

- A documentation site, built with MkDocs Material and deployed to GitHub
  Pages, with the API reference generated from the help pages:
  <https://diogoribeiro7.github.io/r-dataexcept/>.
- Contributing, security and conduct policies, issue and pull-request
  templates, and CI for `R CMD check` (R 4.1 to devel on three platforms),
  lint, style, spelling, coverage, the envelope contract and the documentation
  site. Releases are cut by pushing a version tag.
