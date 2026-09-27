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
    api_error("https://api.example.com/v1", status_code = 503L),
    condition_group(list(root)),
    training_timeout_error("xgboost", 3600),
    data_format_error(c("csv", "parquet"), "xlsx"),
    schema_mismatch_error("id: integer", "id: character"),
    data_drift_error("income", 0.42),
    data_leakage_error("target_mean", "cross-validation"),
    data_imbalance_error(0.05, 0.2),
    outlier_detection_error("iqr"),
    model_evaluation_error("auc", NaN),
    cross_validation_error(5L),
    hyperparameter_error("max_depth", -1),
    model_serialization_error("model.rds", parent = root),
    overfitting_error(0.99, 0.71),
    underfitting_error(0.52, 0.7),
    resource_limit_error("memory", "16GB"),
    transaction_error("tx-42"),
    external_service_error("rates-api", status_code = 503L),
    service_timeout_error("payments", 30),
    service_authentication_error("rates-api"),
    service_authorization_error("rates-api"),
    retry_limit_exceeded_error("fetch_rates", 5L),
    storage_error("s3://reports/q3.parquet", "write"),
    authentication_error("analyst"),
    authorization_error("analyst", "write:reports"),
    configuration_error("timeout"),
    resource_not_found_error("Dataset", "sales"),
    operation_timeout_error("refresh", 600),
    data_transformation_error("normalise"),
    etl_job_error("daily_sales"),
    batch_processing_error("b-7", parent = root)
  )
  types <- vapply(conditions, function(x) x$.dataexcept$type, character(1))
  registered <- dataexcept_classes()
  error_types <- registered$type[registered$kind == "error" &
    !registered$type %in% c(
      "DataExceptError", "DataFrameError", "DataScienceError", "FileError",
      "DatabaseError", "NetworkError", "PipelineError", "JobError",
      "DataEngineeringError", "EnvelopeError"
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

test_that("families catch their new members", {
  caught <- function(cnd, class) {
    tryCatch(stop(cnd), error = function(e) inherits(e, class))
  }
  expect_true(caught(training_timeout_error("glm", 60), "dataexcept_model_training_error"))
  expect_true(caught(service_timeout_error("payments"), "dataexcept_external_service_error"))
  expect_true(caught(service_timeout_error("payments"), "dataexcept_pipeline_error"))
  expect_true(caught(configuration_error("timeout"), "dataexcept_job_error"))
  expect_true(caught(etl_job_error("daily"), "dataexcept_data_engineering_error"))
  expect_true(caught(transaction_error(), "dataexcept_database_error"))
  expect_true(caught(data_drift_error("x", 1), "dataexcept_data_science_error"))
  # Unlike Python, where ValidationError is a JobError.
  expect_false(caught(validation_error("age", -1), "dataexcept_job_error"))
})

test_that("credentials and permissions are permanent failures", {
  for (cnd in list(
    authentication_error("analyst"),
    authorization_error("analyst", "read"),
    service_authentication_error("api"),
    service_authorization_error("api")
  )) {
    expect_identical(condition_failure(cnd)$kind, "permanent")
    expect_false(is_retryable(cnd))
  }
  expect_true(is.na(is_retryable(service_timeout_error("api", 5))))
})

test_that("optional parts of the new messages are left out when not given", {
  expect_identical(
    conditionMessage(service_timeout_error("payments")),
    "Operation timed out on service 'payments'."
  )
  expect_identical(
    conditionMessage(transaction_error("")),
    "Database transaction failed"
  )
  expect_identical(
    conditionMessage(outlier_detection_error("iqr", details = "")),
    "Outlier detection failed using method 'iqr'"
  )
  expect_identical(
    conditionMessage(model_serialization_error("m.rds")),
    "Failed to serialize to 'm.rds'"
  )
  expect_identical(
    conditionMessage(etl_job_error("daily", message = "daily load failed")),
    "daily load failed"
  )
})

test_that("numbers in messages are written as Python writes them", {
  metric <- function(value) conditionMessage(model_evaluation_error("m", value))
  expect_identical(metric(Inf), "Failed to compute metric 'm', got inf")
  expect_identical(metric(-Inf), "Failed to compute metric 'm', got -inf")
  expect_identical(metric(1e5), "Failed to compute metric 'm', got 100000")
  expect_identical(metric(1e-5), "Failed to compute metric 'm', got 1e-05")
  expect_identical(metric(1e16), "Failed to compute metric 'm', got 1e+16")
  expect_match(conditionMessage(data_drift_error("x", NaN)), "score=nan$")
  expect_match(conditionMessage(data_imbalance_error(0, -Inf)), "ratio=0.000 < threshold=-inf$")
  expect_match(conditionMessage(cross_validation_error(5L)), "on 5 folds$")
})

test_that("a value in a message is quoted as a name is", {
  expect_identical(
    conditionMessage(validation_error("country", "Atlantis")),
    "Validation failed for field 'country': 'Atlantis'"
  )
  expect_identical(
    conditionMessage(validation_error("n", 3L)),
    "Validation failed for field 'n': 3"
  )
  expect_identical(
    conditionMessage(hyperparameter_error("layers", c(64, 32))),
    "Invalid hyperparameter 'layers': c(64, 32)"
  )
  expect_identical(
    conditionMessage(hyperparameter_error("verbose", NA)),
    "Invalid hyperparameter 'verbose': NA"
  )
})

test_that("the new constructors check their arguments", {
  expect_error(data_format_error("csv", 1), "`found_format` must be a single string")
  expect_error(data_format_error(1, "csv"), "`expected_formats` must be a character vector")
  expect_error(data_drift_error("x", NA_real_), "`drift_score` must be a single number")
  expect_error(data_drift_error("x", "0.4"), "`drift_score` must be a single number")
  expect_error(data_imbalance_error(c(0.1, 0.2), 0.3), "`ratio` must be a single number")
  expect_error(model_evaluation_error("auc", TRUE), "`value` must be a single number")
  expect_error(cross_validation_error(2.5), "`folds` must be a non-negative whole number")
  expect_error(training_timeout_error("glm", -1), "`timeout` must be a finite, non-negative number")
  expect_error(service_timeout_error("x", "30"), "`timeout_seconds`")
  expect_error(external_service_error("x", status_code = "503"), "`status_code`")
  expect_error(retry_limit_exceeded_error("x", -1), "`retries`")
  expect_error(storage_error("s3://b/k", 1), "`operation` must be a single string")
  expect_error(authorization_error("analyst", NULL), "`permission` must be a single string")
  expect_error(resource_not_found_error("Dataset", 42), "`identifier` must be a single string")
  expect_error(transaction_error(42), "`transaction_id` must be a single string or NULL")
  expect_error(batch_processing_error("b", parent = "boom"), "condition object")
  expect_error(model_serialization_error("m.rds", parent = "boom"), "condition object")
})
