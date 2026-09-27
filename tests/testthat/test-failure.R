test_that("failure metadata validates its fields", {
  md <- failure_metadata("transient", retryable = TRUE, retry_after_seconds = 2L)
  expect_s3_class(md, "dataexcept_failure_metadata")
  expect_identical(md$retry_after_seconds, 2)
  expect_true(is.double(md$retry_after_seconds))

  expect_error(failure_metadata("fatal"), "must be one of")
  expect_error(failure_metadata(retryable = NA), "TRUE, FALSE or NULL")
  expect_error(failure_metadata(retryable = "yes"), "TRUE, FALSE or NULL")
  expect_error(failure_metadata(retry_after_seconds = -1), "non-negative")
  expect_error(failure_metadata(retry_after_seconds = Inf), "finite")
})

test_that("the default is conservative and NULL is not FALSE", {
  md <- failure_metadata()
  expect_identical(md$kind, "unknown")
  expect_null(md$retryable)
  expect_true("retryable" %in% names(md))
  expect_true("retry_after_seconds" %in% names(md))
})

test_that("class defaults follow the Python package", {
  expect_identical(condition_failure(validation_error("a", 1))$kind, "permanent")
  expect_false(is_retryable(validation_error("a", 1)))
  expect_identical(condition_failure(api_error("https://h"))$kind, "unknown")
  expect_identical(is_retryable(api_error("https://h")), NA)
  expect_identical(is_retryable(host_unreachable_error("h")), NA)
})

test_that("with_failure_metadata() attaches backend-informed metadata", {
  err <- with_failure_metadata(
    api_error("https://h", status_code = 503L),
    failure_metadata("transient", retryable = TRUE, retry_after_seconds = 30)
  )
  expect_true(is_retryable(err))
  expect_identical(condition_failure(err)$retry_after_seconds, 30)

  expect_error(with_failure_metadata(simpleError("x"), failure_metadata()), "dataexcept error")
  expect_error(with_failure_metadata(validation_error("a", 1), list()), "failure_metadata")
})

test_that("unclassified conditions carry no metadata", {
  expect_null(condition_failure(simpleError("x")))
  expect_identical(is_retryable(simpleError("x")), NA)
  expect_error(condition_failure("x"), "condition object")
})

test_that("failure metadata prints", {
  expect_output(
    print(failure_metadata("transient", TRUE, 1.5)),
    "kind = transient, retryable = TRUE, retry_after_seconds = 1.5"
  )
  expect_output(print(failure_metadata()), "retryable = NULL")
})
