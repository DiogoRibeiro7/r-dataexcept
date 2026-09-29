# dataexcept roadmap

The Python package owns the envelope contract; this package follows it. The
order below is by what makes the R side useful to a mixed pipeline soonest.

## 0.2.0

- [x] **Operation context.** `operation_context()` and failure events, as the
  Python `OperationContext` and `exception_to_observability_event()` do.
- [x] **OpenTelemetry.** `condition_to_otel_attributes()`,
  `record_otel_exception()` and `operation_context_from_otel()`, through the
  r-lib `otel` API as an optional dependency.
- [x] **More warning rules**, driven by use: moved to 0.3.0.
- [x] A guide to mixed R/Python pipelines: writing envelopes from R, reading
  Python's, and handling both with the same code (the "Working with Python"
  page of the documentation site).

## 0.3.0

- [x] **Groups and wrapping.** `condition_group()` and `collect_errors()`
  report several failures as one, written as the envelope's exception group;
  `wrap_errors()` is the counterpart of Python's `wrap()`.
- [x] **More condition types.** Twenty-nine of the Python package's types,
  with its fields, messages and failure defaults, tested against the Python
  classes themselves.
- [x] **More warning rules.** Templates with values and plural forms;
  `kmeans()`, `medpolish()`, `arima()`, rank tests with ties, survival and
  lme4. (`nls` and `optim` report convergence as return codes, not warnings,
  and stay out of scope.)
- [x] **Pino.** `condition_to_pino()` and `envelope_to_pino()`, tested
  against the Python package's projection of every reference envelope.

## Before CRAN

- [x] `R CMD check --as-cran` clean on every CI flavour.
- [ ] win-builder (R-devel on Windows).
- [x] A documentation site (MkDocs Material, deployed to GitHub Pages) with
  the reference generated from the help pages.
- [x] Contributing, security and conduct policies; lint, style, spelling and
  coverage checks; a release workflow that publishes on merge.
- [ ] A Zenodo DOI for the first tagged release.
- [ ] Adopt it in heteroTests or attest first. Both carry their own error
  helpers, and replacing those is the test of whether the vocabulary fits.

## Open questions

- Should an R-written envelope say which language produced it? Today `module`
  is `"dataexcept"` for R and a Python module path such as
  `"dataexcept.pandas_exceptions"` for Python. That is enough to tell them
  apart, but only by convention; the schema has no field for it.
- The envelope has no field for a backtrace, by design. Should R keep rlang's
  backtrace alongside the envelope, for logs that stay inside R?
