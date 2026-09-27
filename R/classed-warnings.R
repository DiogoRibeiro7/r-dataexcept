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

# A rule classes the warnings that match any of its templates. A template is
# the text R formats the warning from: a literal message, or a format string
# whose placeholders (%d, %s, %g, ...) take the values named in `fields`, in
# argument order; those values are stored on the classed warning. A template
# with a `plural` form is looked up with ngettext(), as R looks it up.
#
# `prefix` rules match a message that begins with the template and continues
# after a colon, a semicolon or a new line: lme4 appends a pointer to its help
# pages to some warnings, and joins several checks into one.
warning_rule <- function(id, type, domain, templates, prefix = FALSE) {
  templates <- lapply(templates, function(t) if (is.character(t)) template(t) else t)
  list(id = id, type = type, domain = domain, templates = templates, prefix = prefix)
}

template <- function(text, fields = character(), plural = NULL) {
  list(text = text, fields = fields, plural = plural)
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
    ),
    warning_rule(
      "kmeans_not_converged", "ConvergenceWarning", "R-stats",
      list(template(
        "did not converge in %d iteration", "iterations",
        plural = "did not converge in %d iterations"
      ))
    ),
    warning_rule(
      "medpolish_not_converged", "ConvergenceWarning", "R-stats",
      list(template(
        "medpolish() did not converge in %d iteration", "iterations",
        plural = "medpolish() did not converge in %d iterations"
      ))
    ),
    warning_rule(
      "arima_convergence", "ConvergenceWarning", "R-stats",
      list(template("possible convergence problem: optim gave code = %d", "code"))
    ),
    # Rank tests fall back to the normal approximation when the data have ties
    # or zeroes. R 4.4 changed the capital letter in cor.test()'s message, and
    # later versions compute some of these exactly and no longer warn.
    warning_rule(
      "exact_test_ties", "ApproximationWarning", "R-stats",
      c(
        "cannot compute exact p-value with ties",
        "Cannot compute exact p-value with ties",
        "cannot compute exact p-value with zeroes",
        "cannot compute exact confidence interval with ties",
        "cannot compute exact confidence intervals with ties",
        "cannot compute exact confidence interval with zeroes",
        "ties should not be present for the Kolmogorov-Smirnov test",
        "ties should not be present for the one-sample Kolmogorov-Smirnov test",
        "p-value will be approximate in the presence of ties"
      )
    ),
    # survival builds these with paste(), hence the doubled and trailing
    # spaces. Older versions say "coefficient", newer ones "beta" in some
    # fitters.
    warning_rule(
      "coxph_infinite_coefficient", "SeparationWarning", "R-survival",
      list(
        template(
          "Loglik converged before variable  %s ; coefficient may be infinite. ", "variables"
        ),
        template("Loglik converged before variable  %s ; beta may be infinite. ", "variables"),
        "one or more coefficients may be infinite"
      )
    ),
    warning_rule(
      "survival_not_converged", "ConvergenceWarning", "R-survival",
      "Ran out of iterations and did not converge"
    ),
    warning_rule(
      "lme4_convergence", "ConvergenceWarning", "R-lme4",
      list(
        template(
          "Model failed to converge with max|grad| = %g (tol = %g, component %d)",
          c("max_grad", "tol", "component")
        ),
        template(
          "Model failed to converge with max|relative grad| = %g (tol = %g)",
          c("max_relative_grad", "tol")
        ),
        template(
          "Model failed to converge: degenerate %s Hessian with %d negative eigenvalues",
          c("hessian", "negative_eigenvalues")
        ),
        "Model is nearly unidentifiable: very large eigenvalue",
        "Model is nearly unidentifiable: large eigenvalue ratio",
        "unable to evaluate scaled gradient",
        template("convergence code %d from %s", c("code", "optimizer")),
        template("failure to converge in %d evaluations", "evaluations")
      ),
      prefix = TRUE
    ),
    warning_rule(
      "lme4_singular_fit", "BoundaryFitWarning", "R-lme4",
      "boundary (singular) fit: see help('isSingular')"
    )
  )
}

# Every form a template can take in this session: the English text, its
# translation, and for a plural, the form ngettext() picks for a range of
# counts -- enough to reach every plural form of the languages R ships.
template_forms <- function(template, domain) {
  translate <- function(f) tryCatch(f(), error = function(e) character())
  forms <- c(template$text, template$plural)
  if (is.null(template$plural)) {
    forms <- c(forms, translate(function() gettext(template$text, domain = domain)))
  } else {
    counts <- c(0L, 1L, 2L, 3L, 5L, 11L, 21L, 22L, 25L, 101L, 111L)
    forms <- c(forms, translate(function() {
      vapply(counts, function(n) {
        ngettext(n, template$text, template$plural, domain = domain)
      }, character(1))
    }))
  }
  unique(forms)
}

placeholder_pattern <- "%(?:([0-9]+)\\$)?[-+ #0]*[0-9]*(?:\\.[0-9]+)?([a-zA-Z%])"

escape_regex <- function(text) {
  gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", text)
}

# A format string as a regular expression, with a capture group per
# placeholder, and for each group the argument it holds and how to convert it.
# Translations may reorder arguments with %2$s, so positions are kept.
format_regex <- function(format) {
  matches <- gregexpr(placeholder_pattern, format, perl = TRUE)[[1L]]
  if (matches[1L] == -1L) {
    return(list(regex = escape_regex(format), positions = integer(), conversions = character()))
  }
  starts <- as.integer(matches)
  ends <- starts + attr(matches, "match.length") - 1L
  capture_starts <- attr(matches, "capture.start")
  capture_lengths <- attr(matches, "capture.length")
  capture <- function(i, group) {
    first <- capture_starts[i, group]
    substr(format, first, first + capture_lengths[i, group] - 1L)
  }
  regex <- ""
  last <- 0L
  positions <- integer()
  conversions <- character()
  sequential <- 0L
  for (i in seq_along(starts)) {
    regex <- paste0(regex, escape_regex(substr(format, last + 1L, starts[i] - 1L)))
    conversion <- capture(i, 2L)
    if (conversion == "%") {
      regex <- paste0(regex, "%")
    } else {
      sequential <- sequential + 1L
      position <- if (capture_lengths[i, 1L] > 0L) as.integer(capture(i, 1L)) else sequential
      regex <- paste0(regex, conversion_regex(conversion))
      positions <- c(positions, position)
      conversions <- c(conversions, conversion)
    }
    last <- ends[i]
  }
  regex <- paste0(regex, escape_regex(substr(format, last + 1L, nchar(format))))
  list(regex = regex, positions = positions, conversions = conversions)
}

conversion_regex <- function(conversion) {
  switch(conversion,
    d = ,
    i = "(-?[0-9]+)",
    s = "([\\s\\S]*?)",
    "([-+]?(?:[0-9]*\\.?[0-9]+(?:[eE][-+]?[0-9]+)?|Inf|NaN|NA))"
  )
}

convert_capture <- function(text, conversion) {
  switch(conversion,
    d = ,
    i = as.integer(text),
    s = text,
    suppressWarnings(as.numeric(text))
  )
}

# The values a message gives a template's placeholders, as a named list --
# empty for a template without any -- or NULL when the message does not match.
match_template <- function(message, format, fields, prefix) {
  compiled <- format_regex(format)
  ending <- if (prefix) "(?=$|[:;\\n])" else "$"
  pattern <- paste0("^", compiled$regex, ending)
  hit <- regmatches(message, regexec(pattern, message, perl = TRUE))[[1L]]
  if (length(hit) == 0L) {
    return(NULL)
  }
  captures <- hit[-1L]
  values <- list()
  for (i in seq_along(captures)) {
    position <- compiled$positions[i]
    if (position <= length(fields)) {
      values[[fields[[position]]]] <- convert_capture(captures[[i]], compiled$conversions[i])
    }
  }
  values
}

match_warning_rule <- function(message) {
  for (rule in warning_rules()) {
    for (template in rule$templates) {
      for (format in template_forms(template, rule$domain)) {
        values <- match_template(message, format, template$fields, rule$prefix)
        if (!is.null(values)) {
          return(list(rule = rule, values = values))
        }
      }
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
#' Portuguese session. Templates with values are format strings, matched with
#' their placeholders as slots, and plural messages are matched in every form
#' of the language.
#'
#' Besides base R and stats, the rules cover the convergence warnings of
#' survival's Cox and parametric models and of lme4's mixed models.
#'
#' Each classed warning keeps the original message and call, stores the
#' original warning in `parent`, and records the matching rule in `rule`. A
#' warning that carries values -- the iterations `kmeans()` ran, the code
#' `optim()` returned in `arima()`, the gradient lme4 measured -- has them as
#' fields too, named in the `fields` column of `classed_warning_rules()`.
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
#'   recognised message template, and in `fields` the values it carries.
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
  matched <- match_warning_rule(condition_text(w))
  if (is.null(matched)) {
    return(NULL)
  }
  make_condition(matched$rule$type, condition_text(w),
    fields = c(list(rule = matched$rule$id), matched$values),
    parent = w,
    call = conditionCall(w)
  )
}

#' @rdname with_classed_warnings
#' @export
classed_warning_rules <- function() {
  rows <- lapply(warning_rules(), function(rule) {
    texts <- lapply(rule$templates, function(t) c(t$text, t$plural))
    fields <- lapply(rule$templates, function(t) {
      rep(paste(t$fields, collapse = ", "), length(c(t$text, t$plural)))
    })
    data.frame(
      rule = rule$id,
      type = rule$type,
      class = type_classes(rule$type)[1L],
      domain = rule$domain,
      template = unlist(texts),
      fields = unlist(fields),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
