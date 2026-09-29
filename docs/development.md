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

Before a pull request, run the checks CI runs:

| Command | What it enforces |
| --- | --- |
| `devtools::test()` | The test suite |
| `lintr::lint_package()` | The rules in `.lintr`: tidyverse style, 100-column limit |
| `styler::style_pkg(dry = "fail")` | Tidyverse formatting |
| `spelling::spell_check_package()` | British English; accepted words live in `inst/WORDLIST` |
| `covr::package_coverage()` | Coverage, which CI requires to stay at or above 95% |
| `R CMD check --as-cran` | Everything CRAN checks, run on a built tarball |

```bash
R CMD build .
R CMD check --as-cran dataexcept_*.tar.gz
```

[CONTRIBUTING.md](https://github.com/DiogoRibeiro7/r-dataexcept/blob/main/CONTRIBUTING.md)
covers the rest of what a pull request needs, and how releases are made.

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

The envelope and Pino schemas and the reference envelopes and their Pino
projections in `inst/schema/`, and the redaction, validation, observability
and constructor parity cases in `tests/testthat/fixtures/`, come from the
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
| `R-CMD-check.yml` | `R CMD check` on macOS, Windows and Ubuntu, R devel to 4.1. The R 4.1 job installs the hard dependencies and the test tools only: current lme4 needs a newer Matrix than R 4.1 ships with. |
| `test-coverage.yml` | Measures coverage with covr, writes a per-file table to the run summary, and fails below 95%. |
| `lint.yml` | lintr, styler and the spelling check; any finding fails the job. |
| `envelope-contract.yml` | Writes envelopes and their Pino projections from R and validates them with Python's `jsonschema`; weekly, checks for drift from the Python package. |
| `docs.yml` | Regenerates the reference, builds the site with `--strict`, and deploys it to GitHub Pages from `main`. |
| `prepare-release.yml` | Run by hand with a version: sets every version field on a release branch and opens the release pull request. |
| `release.yml` | When a release version (`x.y.z`, not yet released) reaches `main`: checks `DESCRIPTION`, `CITATION.cff` and `NEWS.md` agree, runs `R CMD check --as-cran`, tags the commit, publishes a GitHub release with the tarball and the version's `NEWS.md` section, and opens the pull request that begins the next development cycle. |

## Adding a condition type

1. Add the type to the registry in `R/classes.R`. If it exists in Python, use
   the Python type name and default failure metadata.
2. Add a constructor in the `R/errors*.R` file for its family that validates
   its arguments and calls `make_condition()`.
3. Add it to the reference groups in `tools/build-docs.R` if it gets a new help
   topic.
4. Add tests, then regenerate the documentation. For a type Python has, add
   cases to `CONSTRUCTOR_CASES` in `tools/generate-test-fixtures.py` and
   regenerate the fixtures, so the parity test compares R with the Python
   class.

## Adding a warning rule

1. Find the exact message template: it is the `msgid` in R's catalogue for the
   domain the warning comes from (`R`, `R-base`, `R-stats`, `stats` ...), or
   the format string a package passes to `gettextf()`, `sprintf()` or
   `ngettext()`.
2. Add a rule to `warning_rules()` in `R/classed-warnings.R`, with a type
   registered in `R/classes.R`. Name the value of each placeholder in
   `fields`, and give both forms of a plural message.
3. Add a test that triggers the real warning. A rule without one is not
   accepted: the template must be proven against what R actually signals.
