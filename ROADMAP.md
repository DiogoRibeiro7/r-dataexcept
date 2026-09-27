# dataexcept roadmap

The Python package owns the envelope contract; this package follows it. The
order below is by what makes the R side useful to a mixed pipeline soonest.

## 0.2.0

- [ ] **Operation context.** Attach system, component, operation and job
  identifiers to a failure, as the Python `OperationContext` does, so an R job
  and a Python job report failures under the same identifiers.
- [ ] **OpenTelemetry.** Map a condition onto span attributes and record it as
  an exception event through the r-lib `otel` API, as an optional dependency.
- [ ] **More warning rules**, driven by use. Candidates: `nls` and `optim`
  convergence diagnostics (which arrive as return codes, not warnings), `lme4`
  singular fits, and `survival` convergence warnings. Each rule needs a test
  that triggers the real warning.
- [ ] A vignette on mixed R/Python pipelines: writing envelopes from R,
  reading Python's, and handling both with the same code.

## Before CRAN

- [ ] `R CMD check --as-cran` clean on every CI flavour and on win-builder.
- [x] A documentation site (MkDocs Material, deployed to GitHub Pages) with
  the reference generated from the help pages.
- [x] Contributing, security and conduct policies; lint, style, spelling and
  coverage checks; a tag-driven release workflow.
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
