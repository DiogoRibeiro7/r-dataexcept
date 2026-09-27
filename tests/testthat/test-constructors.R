test_that("constructors build classed conditions with their fields", {
  cnd <- missing_column_error("customer_id", dataframe = "orders")
  expect_s3_class(cnd, c(
    "dataexcept_missing_column_error", "dataexcept_data_frame_error",
    "dataexcept_error", "error", "condition"
  ), exact = TRUE)
  expect_identical(cnd$column, "customer_id")
  expect_identical(cnd$dataframe, "orders")
  expect_identical(
    conditionMessage(cnd),
    "Missing required column 'customer_id' in data frame 'orders'"
  )
  expect_null(conditionCall(cnd))
})

test_that("every registered error type has a working constructor", {
  root <- simpleError("root cause")
  conditions <- list(
    validation_error("age", -1),
    missing_column_error("id"),
    dtype_mismatch_error("amount", c("numeric", "integer"), "character"),
    merge_key_error(c("id", "date"), "id"),
    data_loading_error("orders.csv", parent = root),
    missing_data_error("income"),
    model_training_error("xgboost", epoch = 3L),
    convergence_error("glm", iterations = 25L),
    prediction_error("lm", inputs = data.frame(x = 1)),
    file_read_error("orders.csv", parent = root),
    file_write_error("orders.csv"),
    database_connection_error("postgresql://db:5432/sales"),
    query_execution_error("SELECT 1", parent = root),
    host_unreachable_error("api.example.com"),
    connection_timeout_error("api.example.com", 30),
    api_error("https://api.example.com/v1", status_code = 503L)
  )
  types <- vapply(conditions, function(x) x$.dataexcept$type, character(1))
  registered <- dataexcept_classes()
  error_types <- registered$type[registered$kind == "error" &
    !registered$type %in% c(
      "DataExceptError", "DataFrameError", "DataScienceError", "FileError",
      "DatabaseError", "NetworkError", "PipelineError", "EnvelopeError"
    )]
  expect_setequal(types, error_types)
  for (cnd in conditions) {
    expect_s3_class(cnd, "dataexcept_error")
    expect_true(is_string(conditionMessage(cnd)))
    expect_s3_class(condition_failure(cnd), "dataexcept_failure_metadata")
  }
})

test_that("default messages follow the Python package's wording", {
  expect_identical(
    conditionMessage(validation_error("age", -1)),
    "Validation failed for field 'age': -1"
  )
  expect_identical(
    conditionMessage(convergence_error("glm", 25L)),
    "Model 'glm' failed to converge after 25 iterations"
  )
  expect_identical(
    conditionMessage(model_training_error("xgboost", epoch = 3L)),
    "Training failed for model 'xgboost' at epoch 3"
  )
  expect_identical(
    conditionMessage(merge_key_error(c("id", "date"), "id")),
    "Failed to merge on keys ['id', 'date'] and ['id']"
  )
  expect_identical(
    conditionMessage(connection_timeout_error("h", 30)),
    "Connection to 'h' timed out after 30 seconds"
  )
  expect_identical(
    conditionMessage(api_error("https://h/v1", status_code = 502L)),
    "API call failed: https://h/v1 (status 502)"
  )
})

test_that("a parent's message is appended where the Python classes append it", {
  root <- simpleError("disk unavailable")
  expect_identical(
    conditionMessage(data_loading_error("orders.csv", parent = root)),
    "Failed to load data from 'orders.csv': disk unavailable"
  )
  expect_identical(
    conditionMessage(query_execution_error("SELECT 1", parent = root)),
    "Query failed: SELECT 1 (disk unavailable)"
  )
  expect_identical(data_loading_error("x", parent = root)$parent, root)
})

test_that("a family is caught through its parent class", {
  caught <- tryCatch(
    stop(dtype_mismatch_error("x", "numeric", "character")),
    dataexcept_data_frame_error = function(e) "data frame"
  )
  expect_identical(caught, "data frame")

  caught <- tryCatch(
    stop(convergence_error("glm", 25L)),
    dataexcept_model_training_error = function(e) e$iterations
  )
  expect_identical(caught, 25L)
})

test_that("custom messages replace the default", {
  expect_identical(
    conditionMessage(validation_error("age", -1, message = "Age must be positive")),
    "Age must be positive"
  )
})

test_that("invalid arguments are programming errors outside the hierarchy", {
  err <- expect_error(missing_column_error(1), "`column` must be a single string")
  expect_false(inherits(err, "dataexcept_error"))
  expect_error(missing_column_error(c("a", "b")), "single string")
  expect_error(dtype_mismatch_error("x", NA_character_, "y"), "without NA")
  expect_error(convergence_error("glm", -1), "non-negative whole number")
  expect_error(convergence_error("glm", 2.5), "non-negative whole number")
  expect_error(connection_timeout_error("h", Inf), "finite, non-negative")
  expect_error(data_loading_error("x", parent = "boom"), "condition object")
  expect_error(api_error("https://h", status_code = "500"), "whole number")
})

test_that("URLs are redacted at construction, in the message and the fields", {
  cnd <- database_connection_error("postgresql://analyst:s3cret@db.internal:5432/sales")
  expect_identical(cnd$db_url, "postgresql://***:***@db.internal:5432/sales")
  expect_false(grepl("s3cret", conditionMessage(cnd), fixed = TRUE))

  cnd <- api_error("https://api.example.com/v1/orders?page=2&api_key=abc123")
  expect_identical(cnd$endpoint, "https://api.example.com/v1/orders?page=2&api_key=***")

  cnd <- validation_error("url", "x",
    message = "Bad value at https://user:pw@example.com/data"
  )
  expect_identical(
    conditionMessage(cnd),
    "Bad value at https://***:***@example.com/data"
  )

  cnd <- new_dataexcept_error("x", sources = c("https://a:b@h/x", "local.csv"))
  expect_identical(cnd$sources, c("https://***:***@h/x", "local.csv"))
})

test_that("new_dataexcept_error() defines custom errors", {
  cnd <- new_dataexcept_error(
    "Quota exceeded",
    used = 1000L,
    type = "QuotaExceededError",
    class = "myapp_quota_error",
    failure = failure_metadata("transient", retryable = TRUE)
  )
  expect_s3_class(cnd, c("myapp_quota_error", "dataexcept_error", "error", "condition"),
    exact = TRUE
  )
  expect_identical(cnd$used, 1000L)
  expect_true(is_retryable(cnd))
  expect_identical(condition_to_envelope(cnd)$type, "QuotaExceededError")

  # A registered type supplies the classes behind the custom one.
  cnd <- new_dataexcept_error("x", type = "ValidationError", class = "myapp_error")
  expect_s3_class(cnd, c("myapp_error", "dataexcept_validation_error", "dataexcept_error"))
  expect_false(is_retryable(cnd))
})

test_that("new_dataexcept_error() rejects ambiguous definitions", {
  expect_error(new_dataexcept_error("x", type = "NotRegistered"), "needs at least one R class")
  expect_error(new_dataexcept_error("x", .dataexcept = list()), "reserved")
  expect_error(new_dataexcept_error("x", parent = 1), "condition object")
  expect_error(new_dataexcept_error("x", 1), "unique, non-empty name")
  expect_error(new_dataexcept_error("x", a = 1, a = 2), "unique, non-empty name")
  expect_error(new_dataexcept_error("x", failure = list()), "failure_metadata")
})

test_that("the call is reported when supplied", {
  f <- function() stop(validation_error("x", 1, call = sys.call()))
  err <- tryCatch(f(), error = identity)
  expect_identical(conditionCall(err), quote(f()))
})

test_that("dataexcept_classes() describes a consistent hierarchy", {
  classes <- dataexcept_classes()
  expect_false(anyDuplicated(classes$type) > 0)
  expect_false(anyDuplicated(classes$class) > 0)
  expect_true(all(startsWith(classes$class, "dataexcept_")))
  expect_true(all(is.na(classes$parent) | classes$parent %in% classes$type))
  expect_identical(
    classes$failure_kind[classes$type == "ValidationError"], "permanent"
  )
})
