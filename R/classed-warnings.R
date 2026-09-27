# Base R and stats signal many of the failures statisticians actually meet as
# plain simpleWarning objects: nothing but a message. A handler can only
# recognise them by their text, and that text is translated into the session
# language, so matching on the English wording silently stops working in a
# German or Portuguese session.
#
# The rules below match a warning against the message template itself,
# translated at match time with gettext() in the domain the warning comes
# from. That is the same catalogue R used to produce the message, so the
# comparison holds in every language R ships translations for.

warning_rule <- function(id, type, domain, templates) {
  list(id = id, type = type, domain = domain, templates = templates)
}

warning_rules <- function() {
  list(
    warning_rule(
      "glm_not_converged", "ConvergenceWarning", "R-stats",
      c(
        "glm.fit: algorithm did not converge",
        "fitting to calculate the null deviance did not converge -- increase 'maxit'?"
      )
    ),
    warning_rule(
      "glm_fitted_probabilities", "SeparationWarning", "R-stats",
      "glm.fit: fitted probabilities numerically 0 or 1 occurred"
    ),
    warning_rule(
      "glm_boundary", "BoundaryFitWarning", "R-stats",
      c(
        "glm.fit: algorithm stopped at boundary value",
        "glm.fit: fitted rates numerically 0 occurred",
        "step size truncated: out of bounds"
      )
    ),
    warning_rule(
      "rank_deficient_prediction", "RankDeficientPredictionWarning", "R-stats",
      c(
        "prediction from a rank-deficient fit may be misleading",
        "prediction from rank-deficient fit; attr(*, \"non-estim\") has doubtful cases"
      )
    ),
    warning_rule(
      "chisq_approximation", "ApproximationWarning", "R-stats",
      "Chi-squared approximation may be incorrect"
    ),
    warning_rule(
      "zero_standard_deviation", "ZeroVarianceWarning", "stats",
      "the standard deviation is zero"
    ),
    warning_rule(
      "na_by_coercion", "CoercionWarning", "R",
      c("NAs introduced by coercion", "NAs introduced by coercion to integer range")
    ),
    warning_rule(
      "recycling_length", "RecyclingWarning", "R",
      "longer object length is not a multiple of shorter object length"
    ),
    warning_rule(
      "nan_produced", "NaNProducedWarning", "R",
      "NaNs produced"
    ),
    warning_rule(
      "non_numeric_argument", "NonNumericArgumentWarning", "R-base",
      "argument is not numeric or logical: returning NA"
    )
  )
}

rule_messages <- function(rule) {
  translated <- vapply(rule$templates, function(template) {
    tryCatch(gettext(template, domain = rule$domain), error = function(e) template)
  }, character(1), USE.NAMES = FALSE)
  unique(c(rule$templates, translated))
}

match_warning_rule <- function(message) {
  for (rule in warning_rules()) {
    if (message %in% rule_messages(rule)) {
      return(rule)
    }
  }
  NULL
}

#' Give base R's text-only warnings a class
#'
#' `with_classed_warnings()` evaluates `expr` and re-signals the base R and
#' stats warnings listed by `classed_warning_rules()` as classed warnings, so
#' they can be handled by class instead of by matching their text:
#'
#' ```r
#' withCallingHandlers(
#'   with_classed_warnings(glm(y ~ x, family = binomial, data = d)),
#'   dataexcept_separation_warning = function(w) ...
#' )
#' ```
#'
#' Recognition does not depend on the session language. A warning is compared
#' with its template translated through R's own message catalogue, the one R
#' used to write the warning, so the same code works in an English, German or
#' Portuguese session.
#'
#' Each classed warning keeps the original message and call, stores the
#' original warning in `parent`, and records the matching rule in `rule`.
#' Warnings no rule matches pass through untouched, as does everything else
#' `expr` signals. Written to an envelope, a classed warning has a `type` such
#' as `"SeparationWarning"` and the original `simpleWarning` as its `cause`.
#'
#' `classify_warning()` does the recognition for a single warning object.
#'
#' @param expr An expression to evaluate.
#' @param w A warning condition.
#' @return `with_classed_warnings()` returns the value of `expr`.
#'   `classify_warning()` returns the classed warning, or `NULL` when no rule
#'   matches. `classed_warning_rules()` returns a data frame with one row per
#'   recognised message template.
#' @export
#' @examples
#' separated <- data.frame(y = c(0, 0, 1, 1), x = 1:4)
#'
#' # Handle one family of warnings by class, whatever the session language.
#' withCallingHandlers(
#'   with_classed_warnings(glm(y ~ x, family = binomial, data = separated)),
#'   dataexcept_separation_warning = function(w) {
#'     message("Perfect separation: ", conditionMessage(w))
#'     invokeRestart("muffleWarning")
#'   },
#'   dataexcept_convergence_warning = function(w) invokeRestart("muffleWarning")
#' )
#'
#' # Or fail closed: turn non-convergence into an error.
#' try(withCallingHandlers(
#'   with_classed_warnings(glm(y ~ x,
#'     family = binomial, data = separated,
#'     control = glm.control(maxit = 5)
#'   )),
#'   dataexcept_convergence_warning = function(w) {
#'     stop(convergence_error("glm", iterations = 5L, parent = w))
#'   }
#' ))
#'
#' classed_warning_rules()[, c("type", "template")]
with_classed_warnings <- function(expr) {
  withCallingHandlers(
    expr,
    warning = function(w) {
      if (inherits(w, "dataexcept_warning")) {
        return(invisible())
      }
      classed <- classify_warning(w)
      if (is.null(classed)) {
        return(invisible())
      }
      warning(classed)
      invokeRestart("muffleWarning")
    }
  )
}

#' @rdname with_classed_warnings
#' @export
classify_warning <- function(w) {
  if (!inherits(w, "warning")) {
    stop("`w` must be a warning condition.", call. = FALSE)
  }
  if (inherits(w, "dataexcept_warning")) {
    return(w)
  }
  rule <- match_warning_rule(condition_text(w))
  if (is.null(rule)) {
    return(NULL)
  }
  make_condition(rule$type, condition_text(w),
    fields = list(rule = rule$id),
    parent = w,
    call = conditionCall(w)
  )
}

#' @rdname with_classed_warnings
#' @export
classed_warning_rules <- function() {
  rows <- lapply(warning_rules(), function(rule) {
    data.frame(
      rule = rule$id,
      type = rule$type,
      class = type_classes(rule$type)[1L],
      domain = rule$domain,
      template = rule$templates,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
