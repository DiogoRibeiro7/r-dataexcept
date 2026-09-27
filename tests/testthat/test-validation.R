test_that("validate_envelope() agrees with a JSON Schema validator", {
  path <- test_path("fixtures", "validation-cases.json")
  cases <- jsonlite::read_json(path, simplifyVector = FALSE)
  expect_gt(length(cases), 20L)
  for (case in cases) {
    expect_identical(is_envelope(case$payload), case$valid, info = case$name)
  }
})

test_that("every envelope this package writes is valid", {
  conditions <- list(
    validation_error("a", 1, parent = simpleError("root")),
    new_dataexcept_error("x", v = list(NaN, Inf, NA), type = "X", class = "x_error"),
    classify_warning(simpleWarning("NaNs produced")),
    simpleMessage("m"),
    validation_error("a", 1, parent = validation_error("b", 2, parent = simpleError("c")))
  )
  for (cnd in conditions) {
    expect_true(is_envelope(condition_to_json(cnd)))
    expect_true(is_envelope(condition_to_json(cnd, max_depth = 0L)))
  }
})

test_that("validate_envelope() returns its input invisibly", {
  json <- '{"type": "ValueError", "module": "builtins", "message": "bad row"}'
  expect_invisible(validate_envelope(json))
  expect_identical(validate_envelope(json), json)
})

test_that("the schema ships with the package", {
  schema <- envelope_schema()
  expect_identical(schema$`$id`, envelope_schema_id())
  expect_match(envelope_schema_id(), envelope_schema_version(), fixed = TRUE)
  expect_setequal(
    names(schema$`$defs`),
    c(
      "envelope", "truncationMarker", "cycleRecord", "exceptionRecord",
      "exceptionType", "exceptionModule", "exceptionMessage", "failure"
    )
  )
})
