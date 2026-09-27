# Development

## Setup

```bash
git clone https://github.com/DiogoRibeiro7/r-dataexcept
cd r-dataexcept
```

```r
# install.packages(c("devtools", "roxygen2", "testthat", "rlang"))
devtools::install_deps(dependencies = TRUE)
devtools::load_all()
```

## Tests

```r
devtools::test()
```

The suite covers the constructors, failure metadata, writing and reading
envelopes, validation, redaction and the classed warnings. Some tests read
fixtures generated from the Python package (see below). The test for
recognising warnings in another language switches the session to German and
is skipped where R's German message translations are unavailable, for example
in the C locale.

Before a pull request, run the full check:

```bash
R CMD build .
R CMD check --as-cran dataexcept_*.tar.gz
```

## Documentation

Help pages are written as roxygen comments in `R/` and generated with:

```r
roxygen2::roxygenise()
```

This site is built with MkDocs Material from `docs/`. The API reference and
the releases page are generated from the help pages and `NEWS.md`, so run the
generator after changing either:

```bash
Rscript tools/build-docs.R
pip install -r docs/requirements.txt
mkdocs serve             # preview at http://127.0.0.1:8000
mkdocs build --strict    # what CI runs
```

CI regenerates the reference and fails if the committed pages are out of date,
then builds the site with `--strict`, so a broken link or a stale page fails
the build.

## Fixtures from the Python package

The schema and the reference envelopes in `inst/schema/`, and the redaction
parity and validation cases in `tests/testthat/fixtures/`, come from the
Python package. To refresh them from a local checkout:

```bash
pip install jsonschema
python tools/generate-test-fixtures.py /path/to/DataExcept
```

A weekly CI job does the same against DataExcept's `main` branch and fails if
the result differs from what is committed, which is the signal that the
Python side has changed.

## Continuous integration

| Workflow | Runs |
| --- | --- |
| `R-CMD-check.yml` | `R CMD check` on macOS, Windows and Ubuntu, R devel to 4.1. |
| `envelope-contract.yml` | Writes envelopes from R and validates them with Python's `jsonschema`; weekly, checks for drift from the Python package. |
| `docs.yml` | Regenerates the reference, builds the site with `--strict`, and deploys it to GitHub Pages from `main`. |

## Adding a condition type

1. Add the type to the registry in `R/classes.R`. If it exists in Python, use
   the Python type name and default failure metadata.
2. Add a constructor in `R/errors.R` that validates its arguments and calls
   `make_condition()`.
3. Add it to the reference groups in `tools/build-docs.R` if it gets a new help
   topic.
4. Add tests, then regenerate the documentation.

## Adding a warning rule

1. Find the exact message template: it is the `msgid` in R's catalogue for the
   domain the warning comes from (`R`, `R-base`, `R-stats`, `stats` ...).
2. Add a rule to `warning_rules()` in `R/classed-warnings.R`, with a type
   registered in `R/classes.R`.
3. Add a test that triggers the real warning. A rule without one is not
   accepted: the template must be proven against what R actually signals.
