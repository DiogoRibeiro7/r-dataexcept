# Classed warnings

Base R and stats report many of the problems statisticians actually meet as
plain `simpleWarning` objects that carry nothing but a message. A handler can
only recognise them by their text:

```r
withCallingHandlers(
  glm(y ~ x, family = binomial, data = d),
  warning = function(w) {
    if (grepl("fitted probabilities numerically 0 or 1", conditionMessage(w))) ...
  }
)
```

That check silently stops working in a German session, where the same warning
reads *glm.fit: Angepasste Wahrscheinlichkeiten mit numerischem Wert 0 oder 1
aufgetreten*.

## Handling them by class

`with_classed_warnings()` evaluates an expression and re-signals the warnings
it recognises as classed warnings:

```r
separated <- data.frame(y = c(0, 0, 1, 1), x = 1:4)

fit <- withCallingHandlers(
  with_classed_warnings(glm(y ~ x, family = binomial, data = separated)),
  dataexcept_separation_warning = function(w) {
    message("Perfect separation: ", conditionMessage(w))
    invokeRestart("muffleWarning")
  }
)
#> Perfect separation: glm.fit: fitted probabilities numerically 0 or 1 occurred
```

Each classed warning keeps the original message and call, stores the original
warning in `parent`, and records the rule that matched in `rule`. Warnings no
rule matches, messages and errors pass through untouched. `suppressWarnings()`
still silences everything.

## How recognition works

A warning is compared with its message template translated through R's own
message catalogue, in the domain the warning comes from:

```r
gettext("glm.fit: fitted probabilities numerically 0 or 1 occurred", domain = "R-stats")
```

That is the catalogue R used to write the warning in the first place, so the
comparison holds in every language R ships translations for. The English
template is always accepted as well, and no locale is forced.

Some warnings carry values: the number of iterations `kmeans()` ran, the code
`optim()` returned inside `arima()`, the gradient lme4 measured. Their
templates are format strings, such as `"did not converge in %d iterations"`.
The translated format string becomes a pattern, with one slot per placeholder,
and the values it captures are stored on the classed warning:

```r
set.seed(1)
points <- matrix(rnorm(200), ncol = 2)

w <- tryCatch(
  with_classed_warnings(kmeans(points, 3, iter.max = 1)),
  dataexcept_convergence_warning = identity
)
w$rule
#> [1] "kmeans_not_converged"
w$iterations
#> [1] 1
```

A message with singular and plural forms is matched against every form the
language has, as `ngettext()` would choose them, and a translation that
reorders the values (`%2$s`) is read in its own order. The values are also
written to the envelope, as attributes.

## What is recognised

| Class | Type | Warnings |
| --- | --- | --- |
| `dataexcept_convergence_warning` | `ConvergenceWarning` | `glm.fit: algorithm did not converge`; the null-deviance fit not converging; `kmeans()` and `medpolish()` stopping at `iter.max` (`iterations`); `arima()` when `optim()` returns a non-zero code (`code`); survival's `Ran out of iterations and did not converge`; lme4's convergence checks -- the gradient (`max_grad`, `tol`, `component`), the Hessian, identifiability, and the optimizer's own code (`code`, `optimizer`) |
| `dataexcept_separation_warning` | `SeparationWarning` | `glm.fit: fitted probabilities numerically 0 or 1 occurred`; survival's `Loglik converged before variable ...; coefficient may be infinite` (`variables`) and `one or more coefficients may be infinite` |
| `dataexcept_boundary_fit_warning` | `BoundaryFitWarning` | `glm.fit: algorithm stopped at boundary value`; `glm.fit: fitted rates numerically 0 occurred`; `step size truncated: out of bounds`; lme4's singular fit, when lme4 is set to warn about it rather than send a message |
| `dataexcept_rank_deficient_prediction_warning` | `RankDeficientPredictionWarning` | `predict.lm()` on a rank-deficient fit, in both the pre- and post-R 4.3 wording |
| `dataexcept_approximation_warning` | `ApproximationWarning` | `Chi-squared approximation may be incorrect`; rank tests that cannot compute an exact p-value or interval because of ties or zeroes (`cor.test()`, `wilcox.test()`, `ansari.test()`, `ks.test()`), in the wording of each R version |
| `dataexcept_zero_variance_warning` | `ZeroVarianceWarning` | `the standard deviation is zero`, from `cor()` |
| `dataexcept_coercion_warning` | `CoercionWarning` | `NAs introduced by coercion`, including to the integer range |
| `dataexcept_recycling_warning` | `RecyclingWarning` | `longer object length is not a multiple of shorter object length` |
| `dataexcept_nan_produced_warning` | `NaNProducedWarning` | `NaNs produced` |
| `dataexcept_non_numeric_argument_warning` | `NonNumericArgumentWarning` | `argument is not numeric or logical: returning NA`, from `mean()` |

Names in brackets are the values stored on the warning. `classed_warning_rules()`
returns the exact templates and the values each one carries. All inherit from
`dataexcept_warning`.

lme4 adds a pointer to its help pages to some of its warnings, and joins
several checks into one warning; its rules match a warning that begins with
the template. lme4's singular-fit notice is a message unless
`lmerControl(check.conv.singular = .makeCC(action = "warning", tol = 1e-4))`
asks for a warning, and only a warning is classed.

## Failing closed

Some warnings mean the result should not be used. Escalate them to errors in a
calling handler, keeping the warning as the cause:

```r
fit <- withCallingHandlers(
  with_classed_warnings(glm(y ~ x,
    family = binomial, data = separated,
    control = glm.control(maxit = 5)
  )),
  dataexcept_convergence_warning = function(w) {
    stop(convergence_error("glm", iterations = 5L, parent = w))
  }
)
#> Error: Model 'glm' failed to converge after 5 iterations
```

Written to an envelope, that error has the `ConvergenceWarning` as its cause,
and the original `simpleWarning` beneath it.

## One warning at a time

`classify_warning()` does the recognition for a single warning object, and
returns `NULL` when no rule matches. It is the building block for your own
handlers:

```r
classify_warning(simpleWarning("NAs introduced by coercion"))
#> <dataexcept_coercion_warning: NAs introduced by coercion>
```
