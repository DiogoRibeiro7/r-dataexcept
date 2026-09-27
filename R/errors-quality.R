# Constructors for failures in the data a model is given and in the model it
# produces. All belong to the DataScienceError family, as in the Python
# package; the messages follow its wording.

#' Data quality failures
#'
#' Errors about the data itself rather than the code handling it: a file in
#' the wrong format, a schema that does not match, drift from a reference
#' distribution, leakage between training and test data, classes too
#' imbalanced to learn from, and outlier detection that could not run. All
#' inherit from `dataexcept_data_science_error`.
#'
#' Their failure metadata is `"unknown"` by default: the same data would fail
#' again, but whether the data will change is for the caller to say.
#'
#' @param expected_formats Character vector of the formats accepted, such as
#'   `c("csv", "parquet")`.
#' @param found_format The format found.
#' @param expected,found Descriptions of the schema expected and the schema
#'   found, each a single string.
#' @param feature Name of the feature concerned.
#' @param drift_score The drift statistic, written to four decimal places in
#'   the default message.
#' @param stage The stage at which the leak was found, such as
#'   `"cross-validation"`.
#' @param ratio The ratio of the smallest class to the largest.
#' @param threshold The smallest ratio accepted.
#' @param method The name of the detection method.
#' @param details Optional detail, appended to the message.
#' @inheritParams validation_error
#' @return A condition inheriting from `dataexcept_data_science_error`.
#' @family dataexcept errors
#' @name data_quality_errors
#' @examples
#' check_balance <- function(y, threshold = 0.2) {
#'   counts <- table(y)
#'   ratio <- min(counts) / max(counts)
#'   if (ratio < threshold) stop(data_imbalance_error(ratio, threshold))
#'   invisible(y)
#' }
#' tryCatch(
#'   check_balance(c(rep("no", 95), rep("yes", 5))),
#'   dataexcept_data_imbalance_error = function(e) conditionMessage(e)
#' )
#'
#' err <- data_drift_error("income", drift_score = 0.4172)
#' err$drift_score
#'
#' schema_mismatch_error(
#'   expected = "id: integer, amount: numeric",
#'   found = "id: integer, amount: character"
#' )
NULL

#' @rdname data_quality_errors
#' @export
data_format_error <- function(expected_formats, found_format, parent = NULL, call = NULL) {
  check_strings(expected_formats, "expected_formats")
  check_string(found_format, "found_format")
  make_condition("DataFormatError",
    sprintf("Expected data format %s; got %s", format_list(expected_formats), found_format),
    fields = list(expected_formats = I(expected_formats), found_format = found_format),
    parent = parent, call = call
  )
}

#' @rdname data_quality_errors
#' @export
schema_mismatch_error <- function(expected, found, parent = NULL, call = NULL) {
  check_string(expected, "expected")
  check_string(found, "found")
  make_condition("SchemaMismatchError",
    sprintf("Schema mismatch. Expected: %s, Found: %s", expected, found),
    fields = list(expected = expected, found = found),
    parent = parent, call = call
  )
}

#' @rdname data_quality_errors
#' @export
data_drift_error <- function(feature, drift_score, message = NULL, parent = NULL, call = NULL) {
  check_string(feature, "feature")
  check_number(drift_score, "drift_score")
  check_string(message, "message", allow_null = TRUE)
  drift_score <- as.double(drift_score)
  make_condition("DataDriftError",
    message %||% sprintf(
      "Data drift detected on %s, score=%s",
      quote_name(feature), format_number(drift_score, digits = 4L)
    ),
    fields = list(feature = feature, drift_score = drift_score),
    parent = parent, call = call
  )
}

#' @rdname data_quality_errors
#' @export
data_leakage_error <- function(feature, stage, message = NULL, parent = NULL, call = NULL) {
  check_string(feature, "feature")
  check_string(stage, "stage")
  check_string(message, "message", allow_null = TRUE)
  make_condition("DataLeakageError",
    message %||% sprintf("Data leakage detected for %s during %s", quote_name(feature), stage),
    fields = list(feature = feature, stage = stage),
    parent = parent, call = call
  )
}

#' @rdname data_quality_errors
#' @export
data_imbalance_error <- function(ratio, threshold, message = NULL, parent = NULL, call = NULL) {
  check_number(ratio, "ratio")
  check_number(threshold, "threshold")
  check_string(message, "message", allow_null = TRUE)
  ratio <- as.double(ratio)
  threshold <- as.double(threshold)
  make_condition("DataImbalanceError",
    message %||% sprintf(
      "Data imbalance detected: ratio=%s < threshold=%s",
      format_number(ratio, digits = 3L), format_number(threshold, digits = 3L)
    ),
    fields = list(ratio = ratio, threshold = threshold),
    parent = parent, call = call
  )
}

#' @rdname data_quality_errors
#' @export
outlier_detection_error <- function(method, details = NULL, parent = NULL, call = NULL) {
  check_string(method, "method")
  check_string(details, "details", allow_null = TRUE)
  make_condition("OutlierDetectionError",
    with_details(sprintf("Outlier detection failed using method %s", quote_name(method)), details),
    fields = list(method = method, details = details),
    parent = parent, call = call
  )
}

#' Model evaluation and training failures
#'
#' Errors about a model's quality and the process that produces it: a metric
#' that could not be computed, cross-validation that failed, an invalid
#' hyperparameter, training that ran out of time, a model that fits its
#' training data too closely or not closely enough, a model that could not be
#' saved, and a computation that exceeded its resources. All inherit from
#' `dataexcept_data_science_error`; `training_timeout_error()` also inherits from
#' `dataexcept_model_training_error`, so a handler for training failures
#' catches it.
#'
#' @param metric Name of the metric.
#' @param value For `model_evaluation_error()`, the value computed, often `NaN`.
#'   For `hyperparameter_error()`, the value rejected, stored as given.
#' @param folds Number of folds.
#' @param details Optional detail, appended to the message.
#' @param param Name of the hyperparameter.
#' @param model_type The model, as a name such as `"xgboost"`.
#' @param timeout The time limit that was exceeded, in seconds.
#' @param path The file the model was being written to. A URL is redacted.
#' @param train_metric The metric on the training data.
#' @param val_metric The metric on the validation data.
#' @param threshold The smallest training metric accepted.
#' @param resource The resource that ran out, such as `"memory"`.
#' @param limit The limit that was exceeded, stored as given.
#' @inheritParams validation_error
#' @return A condition inheriting from `dataexcept_data_science_error`.
#' @family dataexcept errors
#' @name model_quality_errors
#' @examples
#' check_fit <- function(train_auc, val_auc, tolerance = 0.1) {
#'   if (train_auc - val_auc > tolerance) stop(overfitting_error(train_auc, val_auc))
#'   invisible(TRUE)
#' }
#' tryCatch(check_fit(0.99, 0.71), dataexcept_data_science_error = conditionMessage)
#'
#' # A metric that could not be computed is usually NaN.
#' err <- model_evaluation_error("auc", NaN)
#' conditionMessage(err)
#'
#' # The cause of a failed save is kept, and its message appended.
#' saved <- tryCatch(
#'   saveRDS(lm(dist ~ speed, cars), file.path(tempfile(), "model.rds")),
#'   warning = function(w) model_serialization_error("model.rds", parent = w)
#' )
#' conditionMessage(saved)
NULL

#' @rdname model_quality_errors
#' @export
model_evaluation_error <- function(metric, value, message = NULL, parent = NULL, call = NULL) {
  check_string(metric, "metric")
  check_number(value, "value")
  check_string(message, "message", allow_null = TRUE)
  value <- as.double(value)
  make_condition("ModelEvaluationError",
    message %||% sprintf(
      "Failed to compute metric %s, got %s", quote_name(metric), format_number(value)
    ),
    fields = list(metric = metric, value = value),
    parent = parent, call = call
  )
}

#' @rdname model_quality_errors
#' @export
cross_validation_error <- function(folds, details = NULL, parent = NULL, call = NULL) {
  check_count(folds, "folds")
  check_string(details, "details", allow_null = TRUE)
  make_condition("CrossValidationError",
    with_details(sprintf("Cross-validation failed on %s folds", format_number(folds)), details),
    fields = list(folds = folds),
    parent = parent, call = call
  )
}

#' @rdname model_quality_errors
#' @export
hyperparameter_error <- function(param, value, message = NULL, parent = NULL, call = NULL) {
  check_string(param, "param")
  check_string(message, "message", allow_null = TRUE)
  make_condition("HyperparameterError",
    message %||% sprintf("Invalid hyperparameter %s: %s", quote_name(param), format_value(value)),
    fields = list(param = param, value = value),
    parent = parent, call = call
  )
}

#' @rdname model_quality_errors
#' @export
training_timeout_error <- function(model_type, timeout, parent = NULL, call = NULL) {
  check_string(model_type, "model_type")
  check_seconds(timeout, "timeout")
  make_condition("TrainingTimeoutError",
    sprintf(
      "Training %s exceeded timeout of %s seconds",
      quote_name(model_type), format_number(timeout)
    ),
    fields = list(model_type = model_type, epoch = NULL, timeout = as.double(timeout)),
    parent = parent, call = call
  )
}

#' @rdname model_quality_errors
#' @export
model_serialization_error <- function(path, parent = NULL, call = NULL) {
  check_string(path, "path")
  check_condition(parent, "parent")
  make_condition("ModelSerializationError",
    with_cause(sprintf("Failed to serialize to %s", quote_name(path)), parent),
    fields = list(path = path),
    parent = parent, call = call
  )
}

#' @rdname model_quality_errors
#' @export
overfitting_error <- function(train_metric, val_metric, parent = NULL, call = NULL) {
  check_number(train_metric, "train_metric")
  check_number(val_metric, "val_metric")
  train_metric <- as.double(train_metric)
  val_metric <- as.double(val_metric)
  make_condition("OverfittingError",
    sprintf(
      "Overfitting detected: train=%s, val=%s",
      format_number(train_metric), format_number(val_metric)
    ),
    fields = list(train_metric = train_metric, val_metric = val_metric),
    parent = parent, call = call
  )
}

#' @rdname model_quality_errors
#' @export
underfitting_error <- function(train_metric, threshold, parent = NULL, call = NULL) {
  check_number(train_metric, "train_metric")
  check_number(threshold, "threshold")
  train_metric <- as.double(train_metric)
  threshold <- as.double(threshold)
  make_condition("UnderfittingError",
    sprintf(
      "Underfitting detected: training metric %s < threshold %s",
      format_number(train_metric), format_number(threshold)
    ),
    fields = list(train_metric = train_metric, threshold = threshold),
    parent = parent, call = call
  )
}

#' @rdname model_quality_errors
#' @export
resource_limit_error <- function(resource, limit, parent = NULL, call = NULL) {
  check_string(resource, "resource")
  make_condition("ResourceLimitError",
    sprintf("Resource limit exceeded: %s at %s", resource, format_value(limit)),
    fields = list(resource = resource, limit = limit),
    parent = parent, call = call
  )
}

# The message with optional detail appended, as the Python classes append it.
with_details <- function(message, details) {
  if (is.null(details) || !nzchar(details)) {
    return(message)
  }
  paste0(message, ": ", details)
}

# The message with the cause's message appended, where the Python class
# appends the exception it is given.
with_cause <- function(message, parent) {
  if (is.null(parent)) {
    return(message)
  }
  paste0(message, ": ", condition_text(parent))
}
