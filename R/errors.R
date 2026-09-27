# Constructors for the registered error types. Each returns the condition
# without signalling it, so the caller decides between stop(), warning() and
# passing it on; each stores its arguments as fields a handler can read.

#' Validation failures
#'
#' `validation_error()` reports a value that fails a rule: the payload is
#' wrong, so it is classified as permanent and not retryable for the same
#' unchanged input.
#'
#' @param field Name of the field that failed validation.
#' @param value The offending value. Stored as given; rendered in the default
#'   message with [deparse()].
#' @param message A message to use instead of the default.
#' @param parent The condition that caused this one, or `NULL`.
#' @param call The call to report, or `NULL`.
#' @return A condition of class `dataexcept_validation_error`.
#' @family dataexcept errors
#' @export
#' @examples
#' check_age <- function(age) {
#'   if (age < 0) stop(validation_error("age", age))
#'   age
#' }
#' tryCatch(check_age(-1), dataexcept_validation_error = function(e) e$field)
validation_error <- function(field, value, message = NULL, parent = NULL, call = NULL) {
  check_string(field, "field")
  check_string(message, "message", allow_null = TRUE)
  message <- message %||%
    sprintf("Validation failed for field %s: %s", quote_name(field), format_value(value))
  make_condition("ValidationError", message,
    fields = list(field = field, value = value),
    parent = parent, call = call
  )
}

#' Data frame failures
#'
#' Errors about the shape of a data frame: a required column that is absent, a
#' column of the wrong type, and a join whose keys do not line up. All three
#' inherit from `dataexcept_data_frame_error`, so one handler can catch the
#' family.
#'
#' @param column Name of the column.
#' @param dataframe Optional name of the data frame, for the message.
#' @param expected Character vector of acceptable types, such as
#'   `c("numeric", "integer")`.
#' @param found The type actually found, typically `class(x)[1]`.
#' @param left_keys,right_keys Character vectors of join keys.
#' @inheritParams validation_error
#' @return A condition inheriting from `dataexcept_data_frame_error`.
#' @family dataexcept errors
#' @name data_frame_errors
#' @examples
#' orders <- data.frame(id = 1:3, amount = c("10", "20", "30"))
#'
#' require_numeric <- function(df, column) {
#'   if (!column %in% names(df)) {
#'     stop(missing_column_error(column, dataframe = "orders"))
#'   }
#'   if (!is.numeric(df[[column]])) {
#'     stop(dtype_mismatch_error(column, "numeric", class(df[[column]])[1]))
#'   }
#'   invisible(df)
#' }
#'
#' tryCatch(
#'   require_numeric(orders, "amount"),
#'   dataexcept_data_frame_error = function(e) conditionMessage(e)
#' )
NULL

#' @rdname data_frame_errors
#' @export
missing_column_error <- function(column, dataframe = NULL, parent = NULL, call = NULL) {
  check_string(column, "column")
  check_string(dataframe, "dataframe", allow_null = TRUE)
  where <- if (is.null(dataframe)) "" else sprintf(" in data frame %s", quote_name(dataframe))
  make_condition("MissingColumnError",
    sprintf("Missing required column %s%s", quote_name(column), where),
    fields = list(column = column, dataframe = dataframe),
    parent = parent, call = call
  )
}

#' @rdname data_frame_errors
#' @export
dtype_mismatch_error <- function(column, expected, found, parent = NULL, call = NULL) {
  check_string(column, "column")
  check_strings(expected, "expected")
  check_string(found, "found")
  make_condition("DtypeMismatchError",
    sprintf(
      "Column %s has type %s; expected %s",
      quote_name(column), found, format_list(expected)
    ),
    fields = list(column = column, expected = I(expected), found = found),
    parent = parent, call = call
  )
}

#' @rdname data_frame_errors
#' @export
merge_key_error <- function(left_keys, right_keys, parent = NULL, call = NULL) {
  check_strings(left_keys, "left_keys")
  check_strings(right_keys, "right_keys")
  make_condition("MergeKeyError",
    sprintf(
      "Failed to merge on keys %s and %s",
      format_keys(left_keys), format_keys(right_keys)
    ),
    fields = list(left_keys = I(left_keys), right_keys = I(right_keys)),
    parent = parent, call = call
  )
}

#' Data and modelling failures
#'
#' Errors raised while loading data and fitting or using a model. All inherit
#' from `dataexcept_data_science_error`; `convergence_error()` also inherits
#' from `dataexcept_model_training_error`, so a handler for training failures
#' catches non-convergence too.
#'
#' @param source The file path or URL the data came from. A URL is redacted.
#' @param feature Name of the missing feature.
#' @param model_type The model, as a name such as `"glm"`.
#' @param epoch Optional iteration or epoch at which training failed.
#' @param iterations Number of iterations run before giving up.
#' @param inputs Optional snapshot of the inputs a prediction failed on. It is
#'   stored as given; the envelope renders a data frame or matrix as a short
#'   description rather than its contents.
#' @inheritParams validation_error
#' @return A condition inheriting from `dataexcept_data_science_error`.
#' @family dataexcept errors
#' @name modelling_errors
#' @examples
#' fit_or_fail <- function(formula, data, maxit = 25) {
#'   fit <- suppressWarnings(glm(formula,
#'     family = binomial, data = data,
#'     control = glm.control(maxit = maxit)
#'   ))
#'   if (!fit$converged) {
#'     stop(convergence_error("glm", iterations = fit$iter))
#'   }
#'   fit
#' }
#'
#' separated <- data.frame(y = c(0, 0, 1, 1), x = 1:4)
#' tryCatch(
#'   fit_or_fail(y ~ x, separated, maxit = 5),
#'   dataexcept_model_training_error = function(e) e$iterations
#' )
NULL

#' @rdname modelling_errors
#' @export
data_loading_error <- function(source, parent = NULL, call = NULL) {
  check_string(source, "source")
  check_condition(parent, "parent")
  message <- sprintf("Failed to load data from %s", quote_name(source))
  if (!is.null(parent)) {
    message <- paste0(message, ": ", condition_text(parent))
  }
  make_condition("DataLoadingError", message,
    fields = list(source = source),
    parent = parent, call = call
  )
}

#' @rdname modelling_errors
#' @export
missing_data_error <- function(feature, message = NULL, parent = NULL, call = NULL) {
  check_string(feature, "feature")
  check_string(message, "message", allow_null = TRUE)
  make_condition("MissingDataError",
    message %||% sprintf("Missing required feature: %s", quote_name(feature)),
    fields = list(feature = feature),
    parent = parent, call = call
  )
}

#' @rdname modelling_errors
#' @export
model_training_error <- function(model_type, epoch = NULL, message = NULL,
                                 parent = NULL, call = NULL) {
  check_string(model_type, "model_type")
  check_count(epoch, "epoch", allow_null = TRUE)
  check_string(message, "message", allow_null = TRUE)
  if (is.null(message)) {
    message <- sprintf("Training failed for model %s", quote_name(model_type))
    if (!is.null(epoch)) {
      message <- sprintf("%s at epoch %s", message, format(epoch))
    }
  }
  make_condition("ModelTrainingError", message,
    fields = list(model_type = model_type, epoch = epoch),
    parent = parent, call = call
  )
}

#' @rdname modelling_errors
#' @export
convergence_error <- function(model_type, iterations, message = NULL,
                              parent = NULL, call = NULL) {
  check_string(model_type, "model_type")
  check_count(iterations, "iterations")
  check_string(message, "message", allow_null = TRUE)
  make_condition("ConvergenceError",
    message %||% sprintf(
      "Model %s failed to converge after %s iterations",
      quote_name(model_type), format(iterations)
    ),
    fields = list(model_type = model_type, iterations = iterations),
    parent = parent, call = call
  )
}

#' @rdname modelling_errors
#' @export
prediction_error <- function(model_type, inputs = NULL, message = NULL,
                             parent = NULL, call = NULL) {
  check_string(model_type, "model_type")
  check_string(message, "message", allow_null = TRUE)
  make_condition("PredictionError",
    message %||% sprintf("Prediction failed for model %s", quote_name(model_type)),
    fields = list(model_type = model_type, inputs = inputs),
    parent = parent, call = call
  )
}

#' File failures
#'
#' Errors reading or writing a file. Both inherit from
#' `dataexcept_file_error`. The underlying condition, typically the error or
#' warning from the base R function that failed, goes in `parent`, and its
#' message is appended to this one.
#'
#' @param path The file path. A URL is redacted.
#' @inheritParams validation_error
#' @return A condition inheriting from `dataexcept_file_error`.
#' @family dataexcept errors
#' @name file_errors
#' @examples
#' read_orders <- function(path) {
#'   tryCatch(
#'     read.csv(path),
#'     error = function(e) stop(file_read_error(path, parent = e)),
#'     warning = function(w) stop(file_read_error(path, parent = w))
#'   )
#' }
#' tryCatch(
#'   read_orders(tempfile(fileext = ".csv")),
#'   dataexcept_file_error = function(e) conditionMessage(e)
#' )
NULL

#' @rdname file_errors
#' @export
file_read_error <- function(path, parent = NULL, call = NULL) {
  file_error("FileReadError", "Failed to read file", path, parent, call)
}

#' @rdname file_errors
#' @export
file_write_error <- function(path, parent = NULL, call = NULL) {
  file_error("FileWriteError", "Failed to write file", path, parent, call)
}

file_error <- function(type, prefix, path, parent, call) {
  check_string(path, "path")
  check_condition(parent, "parent")
  message <- sprintf("%s %s", prefix, quote_name(path))
  if (!is.null(parent)) {
    message <- paste0(message, ": ", condition_text(parent))
  }
  make_condition(type, message,
    fields = list(path = path),
    parent = parent, call = call
  )
}

#' Database, network and service failures
#'
#' Errors at the boundary with another system. Their failure metadata stays
#' `"unknown"` by default, because only the backend's response can say whether
#' a retry would help; attach that answer with [with_failure_metadata()] when
#' you have it.
#'
#' Connection URLs routinely carry a user name and password, and API endpoints
#' carry tokens in their query string. Both are redacted before they reach the
#' condition.
#'
#' @param db_url The database connection URL.
#' @param query The SQL that failed.
#' @param host The host that could not be reached.
#' @param timeout The timeout that elapsed, in seconds.
#' @param endpoint The API endpoint URL.
#' @param status_code The HTTP status code, if a response arrived.
#' @inheritParams validation_error
#' @return A condition inheriting from `dataexcept_database_error`,
#'   `dataexcept_network_error` or `dataexcept_pipeline_error`.
#' @family dataexcept errors
#' @name service_errors
#' @examples
#' err <- database_connection_error("postgresql://analyst:s3cret@db.internal:5432/sales")
#' conditionMessage(err)
#'
#' err <- api_error("https://api.example.com/v1/orders?api_key=abc123", status_code = 503L)
#' err <- with_failure_metadata(err, failure_metadata("transient", TRUE, 30))
#' condition_to_json(err)
NULL

#' @rdname service_errors
#' @export
database_connection_error <- function(db_url, message = NULL, parent = NULL, call = NULL) {
  check_string(db_url, "db_url")
  check_string(message, "message", allow_null = TRUE)
  db_url <- redact_url(db_url)
  make_condition("DatabaseConnectionError",
    message %||% sprintf("Failed to connect to database at %s", quote_name(db_url)),
    fields = list(db_url = db_url),
    parent = parent, call = call
  )
}

#' @rdname service_errors
#' @export
query_execution_error <- function(query, parent = NULL, call = NULL) {
  check_string(query, "query")
  check_condition(parent, "parent")
  message <- sprintf("Query failed: %s", query)
  if (!is.null(parent)) {
    message <- sprintf("%s (%s)", message, condition_text(parent))
  }
  make_condition("QueryExecutionError", message,
    fields = list(query = query),
    parent = parent, call = call
  )
}

#' @rdname service_errors
#' @export
host_unreachable_error <- function(host, message = NULL, parent = NULL, call = NULL) {
  check_string(host, "host")
  check_string(message, "message", allow_null = TRUE)
  make_condition("HostUnreachableError",
    message %||% sprintf("Host %s is unreachable", quote_name(host)),
    fields = list(host = host),
    parent = parent, call = call
  )
}

#' @rdname service_errors
#' @export
connection_timeout_error <- function(host, timeout, parent = NULL, call = NULL) {
  check_string(host, "host")
  check_seconds(timeout, "timeout")
  make_condition("ConnectionTimeoutError",
    sprintf(
      "Connection to %s timed out after %s seconds",
      quote_name(host), format(timeout)
    ),
    fields = list(host = host, timeout = timeout),
    parent = parent, call = call
  )
}

#' @rdname service_errors
#' @export
api_error <- function(endpoint, status_code = NULL, message = NULL,
                      parent = NULL, call = NULL) {
  check_string(endpoint, "endpoint")
  check_count(status_code, "status_code", allow_null = TRUE)
  check_string(message, "message", allow_null = TRUE)
  endpoint <- redact_url(endpoint)
  if (is.null(message)) {
    message <- sprintf("API call failed: %s", endpoint)
    if (!is.null(status_code)) {
      message <- sprintf("%s (status %s)", message, format(status_code))
    }
  }
  make_condition("ApiError", message,
    fields = list(endpoint = endpoint, status_code = status_code),
    parent = parent, call = call
  )
}
