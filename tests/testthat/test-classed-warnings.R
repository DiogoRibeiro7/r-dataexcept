collect_warnings <- function(expr) {
  seen <- list()
  withCallingHandlers(
    with_classed_warnings(expr),
    warning = function(w) {
      seen[[length(seen) + 1L]] <<- w
      invokeRestart("muffleWarning")
    }
  )
  seen
}

first_class <- function(warnings) {
  vapply(warnings, function(w) class(w)[1L], character(1))
}

separated <- data.frame(y = c(0, 0, 1, 1), x = 1:4)

test_that("each rule turns its warning into a classed warning", {
  cases <- list(
    dataexcept_convergence_warning = quote(
      glm(y ~ x, family = binomial, data = separated, control = list(maxit = 1))
    ),
    dataexcept_separation_warning = quote(glm(y ~ x, family = binomial, data = separated)),
    dataexcept_boundary_fit_warning = quote(
      glm(c(0, 0, 1, 1) ~ c(1, 2, 3, 4), family = binomial(link = "log"), start = c(-3, 0.5))
    ),
    dataexcept_approximation_warning = quote(chisq.test(matrix(c(1, 2, 3, 1), 2))),
    dataexcept_zero_variance_warning = quote(cor(c(1, 1, 1), 1:3)),
    dataexcept_coercion_warning = quote(as.numeric("a")),
    dataexcept_recycling_warning = quote(1:3 + 1:2),
    dataexcept_nan_produced_warning = quote(log(-1)),
    dataexcept_non_numeric_argument_warning = quote(mean("a"))
  )
  for (class in names(cases)) {
    seen <- collect_warnings(eval(cases[[class]]))
    expect_true(class %in% first_class(seen), info = class)
  }
})

# The warning a rule was written for, raised by the function that raises it.
# Returns the classed warnings seen. Whether a fit warns, and which warning it
# gives, can differ between platforms, BLAS libraries and package versions,
# so the test skips when the fit fails outright or does not raise the
# warning; it fails only when a warning that is raised is not classed.
expect_rule <- function(expr, rule, class, pattern) {
  code <- substitute(expr)
  env <- parent.frame()
  fitted <- tryCatch(
    {
      suppressWarnings(eval(code, env))
      TRUE
    },
    error = function(e) conditionMessage(e)
  )
  if (!isTRUE(fitted)) {
    testthat::skip(sprintf("the call fails on this platform: %s", fitted))
  }
  seen <- collect_warnings(eval(code, env))
  raised <- vapply(seen, function(w) grepl(pattern, conditionMessage(w), fixed = TRUE), logical(1))
  if (!any(raised)) {
    testthat::skip(sprintf("this version does not raise '%s'", pattern))
  }
  for (w in seen[raised]) {
    testthat::expect_s3_class(w, class)
    testthat::expect_identical(w$rule, rule)
  }
  invisible(seen[raised])
}

set.seed(1)
points <- matrix(rnorm(200), ncol = 2)

lme4_data <- function(name) {
  env <- new.env()
  utils::data(list = name, package = "lme4", envir = env)
  env[[name]]
}

test_that("k-means non-convergence is classed, with the iterations", {
  for (algorithm in c("Hartigan-Wong", "Lloyd", "MacQueen")) {
    seen <- expect_rule(
      kmeans(points, 3, iter.max = 1, algorithm = algorithm),
      "kmeans_not_converged", "dataexcept_convergence_warning", "did not converge"
    )
    expect_identical(seen[[1]]$iterations, 1L)
  }
})

test_that("medpolish() and arima() non-convergence is classed", {
  table <- matrix(c(1, 5, 2, 8, 3, 1, 7, 2, 9), 3)
  seen <- expect_rule(
    medpolish(table, maxiter = 1, trace.iter = FALSE),
    "medpolish_not_converged", "dataexcept_convergence_warning", "did not converge"
  )
  expect_identical(seen[[1]]$iterations, 1L)

  seen <- expect_rule(
    arima(lh, order = c(3, 0, 0), optim.control = list(maxit = 2)),
    "arima_convergence", "dataexcept_convergence_warning", "optim gave code"
  )
  expect_type(seen[[1]]$code, "integer")
})

test_that("rank tests that fall back to an approximation are classed", {
  x <- c(1, 2, 2, 3)
  y <- c(1, 2, 3, 3)
  expect_rule(
    cor.test(x, y, method = "spearman"),
    "exact_test_ties", "dataexcept_approximation_warning", "exact p-value with ties"
  )
  expect_rule(
    cor.test(x, y, method = "kendall"),
    "exact_test_ties", "dataexcept_approximation_warning", "exact p-value with ties"
  )
  expect_rule(
    ks.test(c(0.1, 0.1, 0.5), "pnorm"),
    "exact_test_ties", "dataexcept_approximation_warning", "ties should not be present"
  )
})

test_that("wilcox.test() ties and zeroes are classed where R still warns", {
  expect_rule(
    wilcox.test(c(1, 2, 2, 3), c(2, 3, 3, 4), conf.int = TRUE),
    "exact_test_ties", "dataexcept_approximation_warning", "cannot compute exact"
  )
  expect_rule(
    wilcox.test(c(0, 1, 2, 3)),
    "exact_test_ties", "dataexcept_approximation_warning", "with zeroes"
  )
})

test_that("survival's Cox model warnings are classed", {
  skip_if_not_installed("survival")
  separated_times <- data.frame(
    time = 1:20, status = rep(c(1, 0), each = 10), x = rep(c(1, 0), each = 10)
  )
  seen <- expect_rule(
    survival::coxph(survival::Surv(time, status) ~ x, data = separated_times),
    "coxph_infinite_coefficient", "dataexcept_separation_warning", "may be infinite"
  )
  # Which of survival's two messages appears depends on the numerics; only
  # the "Loglik converged" one names the variables.
  for (w in seen) {
    if (grepl("Loglik converged", conditionMessage(w), fixed = TRUE)) {
      expect_identical(w$variables, "1")
    }
  }

  few <- data.frame(time = 1:6, status = c(1, 1, 1, 0, 0, 0), x = c(1, 1, 1, 0, 0, 0))
  expect_rule(
    survival::coxph(survival::Surv(time, status) ~ x, data = few),
    "survival_not_converged", "dataexcept_convergence_warning", "Ran out of iterations"
  )
})

test_that("lme4's convergence checks are classed", {
  skip_if_not_installed("lme4")
  cbpp <- lme4_data("cbpp")
  seen <- expect_rule(
    lme4::glmer(cbind(incidence, size - incidence) ~ period + (1 | herd), cbpp, binomial,
      control = lme4::glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 10))
    ),
    "lme4_convergence", "dataexcept_convergence_warning", "convergence code"
  )
  expect_identical(seen[[1]]$optimizer, "bobyqa")
  expect_type(seen[[1]]$code, "integer")
})

test_that("lme4's gradient check is classed, with its values", {
  skip_if_not_installed("lme4")
  cbpp <- lme4_data("cbpp")
  seen <- expect_rule(
    lme4::glmer(cbind(incidence, size - incidence) ~ period + (1 | herd), cbpp, binomial,
      control = lme4::glmerControl(optCtrl = list(maxfun = 20))
    ),
    "lme4_convergence", "dataexcept_convergence_warning", "max|grad|"
  )
  expect_type(seen[[1]]$max_grad, "double")
  expect_type(seen[[1]]$tol, "double")
  expect_type(seen[[1]]$component, "integer")
})

test_that("lme4's identifiability check is classed", {
  skip_if_not_installed("lme4")
  set.seed(3)
  scaled <- lme4_data("cbpp")
  scaled$big <- as.numeric(scaled$period) * 100 + rnorm(nrow(scaled))
  expect_rule(
    lme4::glmer(cbind(incidence, size - incidence) ~ big + (1 | herd), scaled, binomial),
    "lme4_convergence", "dataexcept_convergence_warning", "nearly unidentifiable"
  )
})

test_that("a singular lme4 fit is a boundary fit when lme4 is asked to warn", {
  skip_if_not_installed("lme4")
  flat <- data.frame(y = rep(c(1, 2, 3), 10), g = factor(rep(1:10, each = 3)))
  expect_rule(
    lme4::lmer(y ~ 1 + (1 | g), flat,
      control = lme4::lmerControl(
        check.conv.singular = lme4::.makeCC(action = "warning", tol = 1e-4)
      )
    ),
    "lme4_singular_fit", "dataexcept_boundary_fit_warning", "singular"
  )
})

test_that("templates with values match only their own shape", {
  classify <- function(message) classify_warning(simpleWarning(message))
  expect_null(classify("did not converge in 1 iterationx"))
  expect_null(classify("did not converge in many iterations"))
  expect_null(classify("xdid not converge in 1 iteration"))
  expect_null(classify(
    "Model failed to converge with max|grad| = 0.1 (tol = 0.002, component 1) and more"
  ))

  w <- classify(paste(
    "Model failed to converge with max|grad| = 0.0485299 (tol = 0.002, component 1)",
    "See ?lme4::convergence and ?lme4::troubleshooting.",
    sep = "\n  "
  ))
  expect_identical(w$max_grad, 0.0485299)
  expect_identical(conditionMessage(w), conditionMessage(w$parent))

  w <- classify("Model failed to converge: degenerate  Hessian with 2 negative eigenvalues")
  expect_identical(w$hessian, "")
  expect_identical(w$negative_eigenvalues, 2L)

  w <- classify("Loglik converged before variable  1,3 ; beta may be infinite. ")
  expect_identical(w$variables, "1,3")
})

test_that("a translated template may reorder and escape its placeholders", {
  format <- "%2$s: %1$d%% done in %3$.3f s"
  expect_identical(format_regex(format)$positions, c(2L, 1L, 3L))
  fields <- c("count", "name", "seconds")
  expect_identical(
    match_template("fit: 12% done in 0.250 s", format, fields, prefix = FALSE),
    list(name = "fit", count = 12L, seconds = 0.25)
  )
  expect_identical(
    match_template("fit: 12% done in 0.250 s; next", format, fields, prefix = TRUE)$count,
    12L
  )
  expect_null(match_template("fit: 12% done in 0.250 s; next", format, fields, prefix = FALSE))
  expect_null(match_template("fit: 12 done in 0.250 s", format, fields, prefix = FALSE))
})

test_that("padded, long and out-of-range values are read", {
  expect_identical(
    match_template("value  5.25 of  7", "value %5.2f of %3d", c("value", "count"), FALSE),
    list(value = 5.25, count = 7L)
  )
  expect_identical(
    match_template("used 12 bytes", "used %lld bytes", "bytes", FALSE),
    list(bytes = 12L)
  )
  expect_no_warning(
    values <- match_template("used 99999999999 bytes", "used %d bytes", "bytes", FALSE)
  )
  expect_identical(values, list(bytes = 99999999999))
})

test_that("classed warnings with values are written with them as attributes", {
  w <- classify_warning(simpleWarning("possible convergence problem: optim gave code = 52"))
  envelope <- condition_to_envelope(w)
  expect_identical(envelope$type, "ConvergenceWarning")
  expect_identical(envelope$attributes, list(rule = "arima_convergence", code = 52L))
})

test_that("near-zero Poisson rates are a boundary fit", {
  seen <- collect_warnings(glm(
    c(0, 0, 0, 0, 10, 20) ~ factor(c(1, 1, 1, 2, 2, 2)),
    family = poisson, control = list(epsilon = 1e-30, maxit = 500)
  ))
  expect_true("dataexcept_boundary_fit_warning" %in% first_class(seen))
})

test_that("a classed warning keeps the original message, call and parent", {
  seen <- collect_warnings(log(-1))
  w <- seen[[1]]
  expect_s3_class(w, c(
    "dataexcept_nan_produced_warning", "dataexcept_warning", "warning", "condition"
  ), exact = TRUE)
  expect_identical(conditionMessage(w), conditionMessage(w$parent))
  expect_identical(conditionCall(w), conditionCall(w$parent))
  expect_s3_class(w$parent, "simpleWarning")
  expect_identical(w$rule, "nan_produced")
  expect_null(condition_failure(w))
})

test_that("recognition holds in another session language", {
  skip_if(getRversion() < "4.2.0", "Sys.setLanguage() needs R 4.2 or later")
  old <- Sys.setLanguage("de")
  on.exit(Sys.setLanguage(old), add = TRUE)
  skip_if(
    identical(gettext("NaNs produced", domain = "R"), "NaNs produced"),
    "German message translations are not available in this session"
  )
  seen <- collect_warnings({
    glm(y ~ x, family = binomial, data = separated)
    1:3 + 1:2
  })
  expect_identical(
    first_class(seen),
    c("dataexcept_separation_warning", "dataexcept_recycling_warning")
  )
  expect_false(grepl("fitted probabilities", conditionMessage(seen[[1]]), fixed = TRUE))

  # A template with plural forms, and one with values. Whether optim() gives
  # up within two iterations depends on the platform, so the arima() warning
  # is checked only when it is raised.
  seen <- collect_warnings({
    kmeans(points, 3, iter.max = 1, algorithm = "Lloyd")
    arima(lh, order = c(3, 0, 0), optim.control = list(maxit = 2))
  })
  rules <- vapply(seen, function(w) w$rule %||% NA_character_, character(1))
  expect_true("kmeans_not_converged" %in% rules)
  expect_true(all(first_class(seen) == "dataexcept_convergence_warning"))
  kmeans_warning <- seen[[match("kmeans_not_converged", rules)]]
  expect_identical(kmeans_warning$iterations, 1L)
  expect_false(grepl("converge", conditionMessage(kmeans_warning), fixed = TRUE))
})

test_that("unmatched warnings, messages and values pass through", {
  seen <- collect_warnings(warning("something else"))
  expect_identical(first_class(seen), "simpleWarning")

  expect_message(with_classed_warnings(message("hello")), "hello")
  expect_identical(with_classed_warnings(1 + 1), 2)
  expect_error(with_classed_warnings(stop("boom")), "boom")
})

test_that("an outer handler can catch a classed warning by class", {
  result <- tryCatch(
    with_classed_warnings(as.numeric("a")),
    dataexcept_coercion_warning = function(w) "coercion"
  )
  expect_identical(result, "coercion")
})

test_that("a classed warning can be escalated to an error", {
  err <- tryCatch(
    withCallingHandlers(
      with_classed_warnings(
        glm(y ~ x, family = binomial, data = separated, control = list(maxit = 1))
      ),
      dataexcept_convergence_warning = function(w) {
        stop(convergence_error("glm", iterations = 1L, parent = w))
      },
      dataexcept_separation_warning = function(w) invokeRestart("muffleWarning")
    ),
    error = identity
  )
  expect_s3_class(err, "dataexcept_convergence_error")
  expect_s3_class(err$parent, "dataexcept_convergence_warning")
  env <- condition_to_envelope(err)
  expect_identical(env$cause$type, "ConvergenceWarning")
  expect_identical(env$cause$cause$type, "simpleWarning")
})

test_that("suppressWarnings() still silences classed warnings", {
  expect_silent(suppressWarnings(with_classed_warnings(as.numeric("a"))))
})

test_that("classify_warning() handles one warning", {
  expect_null(classify_warning(simpleWarning("unrelated")))
  w <- classify_warning(simpleWarning("NAs introduced by coercion"))
  expect_s3_class(w, "dataexcept_coercion_warning")
  expect_identical(classify_warning(w), w)
  expect_error(classify_warning(simpleError("x")), "warning condition")
})

test_that("classed_warning_rules() lists every template with its class", {
  rules <- classed_warning_rules()
  expect_named(rules, c("rule", "type", "class", "domain", "template", "fields"))
  expect_true(all(rules$class %in% dataexcept_classes()$class))
  expect_false(anyDuplicated(rules$template) > 0)
})
