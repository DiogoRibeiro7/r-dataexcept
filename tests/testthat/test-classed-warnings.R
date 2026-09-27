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
  expect_named(rules, c("rule", "type", "class", "domain", "template"))
  expect_true(all(rules$class %in% dataexcept_classes()$class))
  expect_false(anyDuplicated(rules$template) > 0)
})
