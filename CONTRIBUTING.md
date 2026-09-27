# Contributing to dataexcept

Thanks for taking the time to contribute. This document covers how to get a
development environment running and what the project expects from a pull
request.

## Getting set up

dataexcept supports R 4.1 and later.

```bash
git clone https://github.com/DiogoRibeiro7/r-dataexcept.git
cd r-dataexcept
```

```r
install.packages(c("devtools", "roxygen2", "testthat", "rlang", "lintr", "styler", "spelling", "covr"))
devtools::install_deps(dependencies = TRUE)
devtools::load_all()
```

## Before you open a pull request

Run the same checks CI runs:

| Command | Tool | What it enforces |
| --- | --- | --- |
| `devtools::test()` | testthat | The test suite |
| `lintr::lint_package()` | lintr | The rules in `.lintr`: tidyverse style, 100-column limit |
| `styler::style_pkg(dry = "fail")` | styler | Tidyverse formatting |
| `spelling::spell_check_package()` | spelling | British English; accepted words live in `inst/WORDLIST` |
| `covr::package_coverage()` | covr | Coverage, which CI requires to stay at or above 95% |
| `R CMD check --as-cran` | R | Everything CRAN checks |

`styler::style_pkg()` applies the formatting for you. Run the full check from
a built tarball:

```bash
R CMD build .
R CMD check --as-cran dataexcept_*.tar.gz
```

## What a change needs

- **Tests.** Every behaviour change comes with a test that would have failed
  before it. Tests assert behaviour, not only the class of the result.
- **Documentation.** Help pages are roxygen comments in `R/`. After changing
  them, regenerate the help pages and the site's reference:

  ```r
  roxygen2::roxygenise()
  ```

  ```bash
  Rscript tools/build-docs.R
  ```

  CI fails if the committed pages are out of date.
- **`NEWS.md`.** Add a line under `# dataexcept (development version)` for
  anything a user would notice.

## Adding a condition type

1. Add the type to the registry in `R/classes.R`. If the type exists in the
   Python package, use the Python type name and its default failure metadata:
   leaf types must mean the same thing in both languages.
2. Add a constructor in `R/errors.R` that validates its arguments and calls
   `make_condition()`. Wrap fields that are lists by meaning in `I()`, so a
   single element is still written as an array.
3. Give it a help topic, and add the topic to the reference groups in
   `tools/build-docs.R` and to `nav` in `mkdocs.yml`.
4. Test the message, the fields, the class chain and the envelope.

## Adding a warning rule

1. Find the exact message template: the `msgid` in R's message catalogue for
   the domain the warning comes from (`R`, `R-base`, `R-stats`, `stats`, ...).
2. Add a rule to `warning_rules()` in `R/classed-warnings.R`, with a type
   registered in `R/classes.R`.
3. Add a test that triggers the real warning. A rule without one is not
   accepted: the template must be proven against what R actually signals.

## The envelope contract

The envelope schema belongs to the [Python DataExcept
package](https://github.com/DiogoRibeiro7/DataExcept). The schema and
reference fixtures in `inst/schema/`, and the parity cases in
`tests/testthat/fixtures/`, are generated from it. **Never edit them by hand.**
Regenerate them from a checkout of the Python package:

```bash
pip install jsonschema
python tools/generate-test-fixtures.py /path/to/DataExcept
```

A change to what the envelope means belongs in the Python package first.

## Documentation site

The site is MkDocs Material, built from `docs/` and published to GitHub Pages
from `main`:

```bash
pip install -r docs/requirements.txt
mkdocs serve            # live reload at http://127.0.0.1:8000
mkdocs build --strict   # same as CI
```

## Commit messages

The project follows [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(errors): add schema_evolution_error()
fix(envelope): write a length-one I() field as an array
docs: document reading envelopes from Python
chore(deps): bump actions/checkout from 4 to 5
```

## Releasing

Maintainers only. Releases are driven by tags, and `tools/release.R` does the
editing, so the steps are the same in bash, zsh and PowerShell.

1. On a branch from an up-to-date `main`, set every version field for the
   release:

   ```bash
   Rscript tools/release.R prepare 0.3.0
   ```

   This sets `DESCRIPTION`, `CITATION.cff` (version and release date), the
   `NEWS.md` heading and the pinned install lines, regenerates the help pages
   and the site's reference, and checks the result. It refuses to release an
   empty development section.
2. Commit, open a pull request, and merge it once CI is green.
3. Tag the merge commit and push the tag:

   ```bash
   git checkout main
   git pull
   Rscript tools/release.R check v0.3.0
   git tag v0.3.0
   git push origin v0.3.0
   ```

   `check` is the test the `release` workflow applies to the tag. If it fails
   locally, the workflow would have failed too.

Pushing the tag runs the `release` workflow. It checks the tag, runs
`R CMD check --as-cran`, and creates a GitHub release with the source tarball
attached and that version's `NEWS.md` section as its notes.

4. On a new branch, begin the next development cycle, and merge it through a
   pull request:

   ```bash
   Rscript tools/release.R dev
   ```

   This sets `DESCRIPTION` to `x.y.z.9000` and adds the development heading to
   `NEWS.md`.

If a tag was pushed too early, delete it before tagging again:
`git tag -d v0.3.0` and `git push --delete origin v0.3.0`.

## Reporting bugs and asking questions

Open an [issue](https://github.com/DiogoRibeiro7/r-dataexcept/issues). For
security problems, follow [SECURITY.md](SECURITY.md) instead: please do not
open a public issue.

## Code of conduct

This project is released with a [Contributor Code of Conduct](CODE_OF_CONDUCT.md).
By participating in it you agree to abide by its terms.
