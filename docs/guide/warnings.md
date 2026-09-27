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
template is always accepted as well. No message is parsed, and no locale is
forced.

## What is recognised

| Class | Type | Warnings |
| --- | --- | --- |
| `dataexcept_convergence_warning` | `ConvergenceWarning` | `glm.fit: algorithm did not converge`; the null-deviance fit not converging |
| `dataexcept_separation_warning` | `SeparationWarning` | `glm.fit: fitted probabilities numerically 0 or 1 occurred` |
| `dataexcept_boundary_fit_warning` | `BoundaryFitWarning` | `glm.fit: algorithm stopped at boundary value`; `glm.fit: fitted rates numerically 0 occurred`; `step size truncated: out of bounds` |
| `dataexcept_rank_deficient_prediction_warning` | `RankDeficientPredictionWarning` | `predict.lm()` on a rank-deficient fit, in both the pre- and post-R 4.3 wording |
| `dataexcept_approximation_warning` | `ApproximationWarning` | `Chi-squared approximation may be incorrect` |
| `dataexcept_zero_variance_warning` | `ZeroVarianceWarning` | `the standard deviation is zero`, from `cor()` |
| `dataexcept_coercion_warning` | `CoercionWarning` | `NAs introduced by coercion`, including to the integer range |
| `dataexcept_recycling_warning` | `RecyclingWarning` | `longer object length is not a multiple of shorter object length` |
| `dataexcept_nan_produced_warning` | `NaNProducedWarning` | `NaNs produced` |
| `dataexcept_non_numeric_argument_warning` | `NonNumericArgumentWarning` | `argument is not numeric or logical: returning NA`, from `mean()` |

`classed_warning_rules()` returns the exact templates. All inherit from
`dataexcept_warning`.

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
