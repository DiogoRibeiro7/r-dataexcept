## What does this change?

<!-- A sentence or two. Link the issue it closes, e.g. "Closes #12". -->

## Why?

<!-- The problem being solved. If it fixes a bug, what was the failure? -->

## Checklist

- [ ] `devtools::test()` and `R CMD check --as-cran` pass
- [ ] `lintr::lint_package()` is clean and `styler::style_pkg()` changes nothing
- [ ] Tests cover the change
- [ ] Help pages regenerated (`roxygen2::roxygenise()`) and site reference regenerated (`Rscript tools/build-docs.R`)
- [ ] `NEWS.md` updated under the development version
- [ ] Files in `inst/schema/` and `tests/testthat/fixtures/` were regenerated from the Python package, not edited by hand
- [ ] Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)

## Notes for the reviewer

<!-- Anything worth flagging: trade-offs, follow-ups, things deliberately left out. -->
