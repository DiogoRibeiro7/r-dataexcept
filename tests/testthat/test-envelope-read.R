test_that("a Python envelope becomes an R condition with the matching classes", {
  cnd <- envelope_to_condition(fixture("ordinary-exception.json"))
  expect_s3_class(cnd, c(
    "dataexcept_validation_error", "dataexcept_error",
    "dataexcept_remote_condition", "error", "condition"
  ), exact = TRUE)
  expect_identical(conditionMessage(cnd), "Validation failed for field 'age': -1")
  expect_identical(cnd$field, "age")
  expect_identical(cnd$value, -1L)
  expect_false(is_retryable(cnd))

  caught <- tryCatch(stop(cnd), dataexcept_validation_error = function(e) "caught")
  expect_identical(caught, "caught")
})

test_that("a Python type R also defines gets its whole family of classes", {
  cnd <- envelope_to_condition(fixture("failure-metadata.json"))
  expect_s3_class(cnd, c(
    "dataexcept_service_timeout_error", "dataexcept_external_service_error",
    "dataexcept_pipeline_error", "dataexcept_error",
    "dataexcept_remote_condition", "error", "condition"
  ), exact = TRUE)
  expect_identical(condition_type(cnd), "ServiceTimeoutError")
  caught <- tryCatch(stop(cnd), dataexcept_external_service_error = function(e) is_retryable(e))
  expect_true(caught)
  expect_true(is_retryable(cnd))
  expect_identical(condition_failure(cnd)$retry_after_seconds, 2.5)
  expect_identical(cnd$service_name, "payments")
})

test_that("a DataExcept type R has no class for is still a dataexcept error", {
  json <- paste0(
    '{"type": "GPUOutOfMemoryError", "module": "dataexcept.datascience_exceptions.training", ',
    '"message": "GPU OOM on cuda:0: required=12GB, available=8GB", ',
    '"failure": {"kind": "transient", "retryable": true, "retry_after_seconds": 60}}'
  )
  cnd <- envelope_to_condition(json)
  expect_s3_class(cnd, c(
    "dataexcept_error", "dataexcept_remote_condition", "error", "condition"
  ), exact = TRUE)
  expect_identical(condition_type(cnd), "GPUOutOfMemoryError")
  caught <- tryCatch(stop(cnd), dataexcept_error = function(e) is_retryable(e))
  expect_true(caught)
  expect_identical(condition_failure(cnd)$retry_after_seconds, 60)
})

test_that("an envelope's cause becomes the parent", {
  cnd <- envelope_to_condition(fixture("explicit-cause.json"))
  expect_s3_class(cnd, "dataexcept_data_loading_error")
  expect_s3_class(cnd$parent, "dataexcept_remote_condition")
  expect_identical(conditionMessage(cnd$parent), "disk unavailable")
  expect_null(condition_failure(cnd$parent))
})

test_that("context, groups and markers are kept", {
  cnd <- envelope_to_condition(fixture("implicit-context.json"))
  expect_identical(conditionMessage(cnd$.dataexcept$context), "'customer_id'")
  expect_null(cnd$parent)

  cnd <- envelope_to_condition(fixture("nested-exception-group.json"))
  members <- cnd$.dataexcept$exceptions
  expect_length(members, 2L)
  expect_length(members[[1]]$.dataexcept$exceptions, 2L)

  cnd <- envelope_to_condition(fixture("truncation.json"))
  expect_s3_class(cnd$parent$parent$parent, "dataexcept_truncated")

  cnd <- envelope_to_condition(fixture("cycle.json"))
  expect_s3_class(cnd$parent$parent, "dataexcept_cycle")
  expect_identical(conditionMessage(cnd$parent$parent), "outer")
})

test_that("attributes that would clash with condition fields stay in the envelope only", {
  cnd <- envelope_to_condition(fixture("ordinary-exception.json"))
  # The Python ValidationError has a `message` attribute. It must not replace
  # the condition message, but it is kept for writing the envelope back.
  expect_identical(conditionMessage(cnd), "Validation failed for field 'age': -1")
  expect_identical(
    cnd$.dataexcept$attributes$message,
    "Validation failed for field 'age': -1"
  )

  json <- '{"type": "X", "module": "m", "message": "real",
            "attributes": {"message": "fake", "parent": 1, "call": 2, ".x": 3, "ok": 4}}'
  cnd <- envelope_to_condition(json)
  expect_identical(conditionMessage(cnd), "real")
  expect_null(cnd$parent)
  expect_null(cnd$call)
  expect_identical(cnd$ok, 4L)
  expect_false(".x" %in% names(cnd))
})

test_that("only dataexcept modules map onto dataexcept classes", {
  json <- '{"type": "ValidationError", "module": "pydantic", "message": "x"}'
  cnd <- envelope_to_condition(json)
  expect_false(inherits(cnd, "dataexcept_validation_error"))
  expect_false(inherits(cnd, "dataexcept_error"))
  expect_identical(condition_type(cnd), "ValidationError")
  cnd <- envelope_to_condition('{"type": "OSError", "module": "builtins", "message": "x"}')
  expect_false(inherits(cnd, "dataexcept_error"))
  json <- '{"type": "ValidationError", "module": "dataexcept", "message": "x",
            "failure": {"kind": "permanent", "retryable": false, "retry_after_seconds": null}}'
  expect_s3_class(envelope_to_condition(json), "dataexcept_validation_error")
})

test_that("an R warning written to an envelope is read back as a warning", {
  w <- classify_warning(simpleWarning("NaNs produced"))
  cnd <- envelope_to_condition(condition_to_json(w))
  expect_s3_class(cnd, c("dataexcept_nan_produced_warning", "dataexcept_warning"))
  expect_s3_class(cnd, "warning")
  expect_false(inherits(cnd, "error"))

  cnd <- envelope_to_condition(condition_to_json(simpleWarning("w")))
  expect_s3_class(cnd, "warning")
  cnd <- envelope_to_condition(condition_to_json(simpleMessage("m")))
  expect_s3_class(cnd, "message")
})

test_that("a list envelope is accepted as well as JSON text", {
  env <- condition_to_envelope(validation_error("a", 1))
  expect_s3_class(envelope_to_condition(env), "dataexcept_validation_error")
})

test_that("invalid input is a classed, permanent envelope error", {
  err <- expect_error(envelope_to_condition("{not json"), class = "dataexcept_envelope_error")
  expect_false(is_retryable(err))
  expect_s3_class(err$parent, "error")

  err <- expect_error(
    envelope_to_condition('{"type": "X", "message": 1}'),
    class = "dataexcept_envelope_error"
  )
  expect_true(any(grepl("`module` is required", err$problems, fixed = TRUE)))
  expect_true(any(grepl("$.message: must be a string", err$problems, fixed = TRUE)))

  expect_error(envelope_to_condition(c("a", "b")), class = "dataexcept_envelope_error")
  expect_error(envelope_to_condition(1), class = "dataexcept_envelope_error")
})

test_that("the error message lists at most ten problems", {
  members <- paste(rep('{"type": 1}', 12), collapse = ",")
  json <- sprintf('{"type": "G", "module": "m", "message": "x", "exceptions": [%s]}', members)
  err <- expect_error(validate_envelope(json), class = "dataexcept_envelope_error")
  expect_length(err$problems, 36L)
  expect_match(conditionMessage(err), "and 26 more", fixed = TRUE)
})

deep_chain <- function(n) {
  paste0(
    strrep('{"type": "E", "module": "m", "message": "x", "cause": ', n),
    '{"truncated": true}',
    strrep("}", n)
  )
}

test_that("reading is bounded on deeply nested input", {
  expect_s3_class(envelope_to_condition(deep_chain(32)), "dataexcept_remote_condition")

  err <- expect_error(envelope_to_condition(deep_chain(33)), class = "dataexcept_envelope_error")
  expect_match(err$problems, "nested more than max_depth = 32", fixed = TRUE)

  # Far too deep to walk: rejected before the text is parsed.
  err <- expect_error(envelope_to_condition(deep_chain(5000)), class = "dataexcept_envelope_error")
  expect_match(err$problems, "nested more than 80 levels deep", fixed = TRUE)
  expect_false(is_envelope(deep_chain(5000)))

  expect_true(is_envelope(deep_chain(40), max_depth = 40L))
  expect_error(is_envelope(deep_chain(2), max_depth = -1), "non-negative")
})

test_that("the nesting count ignores brackets inside strings", {
  json <- '{"type": "E", "module": "m", "message": "[[[[{{{{\\"]]]]"}'
  expect_identical(json_nesting(json), 1L)
  expect_true(is_envelope(json, max_depth = 0L))
})
