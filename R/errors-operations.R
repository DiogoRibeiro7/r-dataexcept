# Constructors for failures in running a pipeline or job: calls to other
# services, storage, retries, credentials, configuration and batch
# processing. The families and messages follow the Python package.

#' Pipeline and external service failures
#'
#' Errors raised by a pipeline step: a call to another service that failed,
#' timed out, or was refused; an operation retried until the limit; and a read
#' or write to storage that failed. All inherit from
#' `dataexcept_pipeline_error`, and the four service errors from
#' `dataexcept_external_service_error` too.
#'
#' A refused credential or permission will be refused again, so
#' `service_authentication_error()` and `service_authorization_error()` are
#' permanent and not retryable. The others are `"unknown"`: whether a retry
#' would help depends on the service, and [with_failure_metadata()] records
#' what it said.
#'
#' @param service_name Name of the service called.
#' @param status_code The HTTP status code, if a response arrived.
#' @param response The response, or part of it, stored as given. The envelope
#'   writes it as an attribute, so store only what is safe to log.
#' @param timeout_seconds The time limit that elapsed, in seconds, or `NULL`.
#' @param operation For `retry_limit_exceeded_error()`, the operation retried.
#'   For `storage_error()`, what was being done, such as `"write"`.
#' @param retries Number of attempts made.
#' @param location Where the data was stored, such as a path or a bucket URL.
#'   A URL is redacted.
#' @inheritParams validation_error
#' @return A condition inheriting from `dataexcept_pipeline_error`.
#' @family dataexcept errors
#' @name pipeline_errors
#' @examples
#' call_rates_api <- function(status) {
#'   if (status == 401L) stop(service_authentication_error("rates-api"))
#'   if (status >= 500L) stop(external_service_error("rates-api", status_code = status))
#'   "ok"
#' }
#'
#' err <- tryCatch(call_rates_api(401L), dataexcept_external_service_error = identity)
#' conditionMessage(err)
#' is_retryable(err)
#'
#' err <- tryCatch(call_rates_api(503L), dataexcept_external_service_error = identity)
#' is_retryable(err)
#'
#' storage_error("s3://reports/2026/q3.parquet", "write")
NULL

#' @rdname pipeline_errors
#' @export
external_service_error <- function(service_name, status_code = NULL, response = NULL,
                                   message = NULL, parent = NULL, call = NULL) {
  check_string(service_name, "service_name")
  check_count(status_code, "status_code", allow_null = TRUE)
  check_string(message, "message", allow_null = TRUE)
  service_condition("ExternalServiceError",
    message_or(message, sprintf("Call to external service %s failed.", quote_name(service_name))),
    service_name = service_name, status_code = status_code, response = response,
    parent = parent, call = call
  )
}

#' @rdname pipeline_errors
#' @export
service_timeout_error <- function(service_name, timeout_seconds = NULL,
                                  parent = NULL, call = NULL) {
  check_string(service_name, "service_name")
  check_seconds(timeout_seconds, "timeout_seconds", allow_null = TRUE)
  after <- ""
  if (!is.null(timeout_seconds)) {
    after <- sprintf(" after %ss", format_number(timeout_seconds))
  }
  service_condition("ServiceTimeoutError",
    sprintf("Operation timed out%s on service %s.", after, quote_name(service_name)),
    service_name = service_name,
    timeout_seconds = timeout_seconds,
    parent = parent, call = call
  )
}

#' @rdname pipeline_errors
#' @export
service_authentication_error <- function(service_name, message = NULL, parent = NULL, call = NULL) {
  check_string(service_name, "service_name")
  check_string(message, "message", allow_null = TRUE)
  service_condition("ServiceAuthenticationError",
    message_or(message, sprintf("Authentication failed for service %s.", quote_name(service_name))),
    service_name = service_name,
    parent = parent, call = call
  )
}

#' @rdname pipeline_errors
#' @export
service_authorization_error <- function(service_name, message = NULL, parent = NULL, call = NULL) {
  check_string(service_name, "service_name")
  check_string(message, "message", allow_null = TRUE)
  service_condition("ServiceAuthorizationError",
    message_or(message, sprintf("Authorization denied for service %s.", quote_name(service_name))),
    service_name = service_name,
    parent = parent, call = call
  )
}

# Every external service error carries the service, the status code and the
# response, as the Python base class does, even when a subclass leaves the
# last two empty.
service_condition <- function(type, message, service_name, status_code = NULL,
                              response = NULL, ..., parent, call) {
  make_condition(type, message,
    fields = c(
      list(...),
      list(service_name = service_name, status_code = status_code, response = response)
    ),
    parent = parent, call = call
  )
}

#' @rdname pipeline_errors
#' @export
retry_limit_exceeded_error <- function(operation, retries, message = NULL,
                                       parent = NULL, call = NULL) {
  check_string(operation, "operation")
  check_count(retries, "retries")
  check_string(message, "message", allow_null = TRUE)
  make_condition("RetryLimitExceededError",
    message_or(message, sprintf(
      "Retry limit exceeded for operation %s after %s attempts.",
      quote_name(operation), format_number(retries)
    )),
    fields = list(operation = operation, retries = retries),
    parent = parent, call = call
  )
}

#' @rdname pipeline_errors
#' @export
storage_error <- function(location, operation, message = NULL, parent = NULL, call = NULL) {
  check_string(location, "location")
  check_string(operation, "operation")
  check_string(message, "message", allow_null = TRUE)
  make_condition("StorageError",
    message_or(message, sprintf(
      "Storage %s failed at location: %s.", operation, quote_name(location)
    )),
    fields = list(location = location, operation = operation),
    parent = parent, call = call
  )
}

#' Job failures
#'
#' Errors that stop a job before or while it does its work: credentials that
#' are refused, a permission that is missing, a configuration option that is
#' invalid, a resource that does not exist, and an operation that ran out of
#' time. All inherit from `dataexcept_job_error`, as they inherit from
#' `JobError` in the Python package.
#'
#' `authentication_error()` and `authorization_error()` are permanent and not
#' retryable: the same credentials will be refused again. The others are
#' `"unknown"`.
#'
#' In the Python package `ValidationError` is a `JobError` too. In R,
#' [validation_error()] stays a direct child of `dataexcept_error`, as it has
#' been since the first release, so a `dataexcept_job_error` handler does not
#' catch it.
#'
#' @param user The user whose credentials or permissions were refused.
#' @param permission The permission the user lacks.
#' @param option The configuration option that is invalid.
#' @param resource_type The kind of resource, such as `"Dataset"`.
#' @param identifier The identifier that was looked up.
#' @param operation The operation that timed out.
#' @param timeout The time limit that elapsed, in seconds.
#' @inheritParams validation_error
#' @return A condition inheriting from `dataexcept_job_error`.
#' @family dataexcept errors
#' @name job_errors
#' @examples
#' get_setting <- function(settings, option) {
#'   value <- settings[[option]]
#'   if (is.null(value)) stop(configuration_error(option))
#'   value
#' }
#' tryCatch(
#'   get_setting(list(retries = 3), "timeout"),
#'   dataexcept_job_error = function(e) conditionMessage(e)
#' )
#'
#' err <- resource_not_found_error("Dataset", "sales-2026-q3")
#' conditionMessage(err)
#'
#' is_retryable(authorization_error("analyst", "write:reports"))
NULL

#' @rdname job_errors
#' @export
authentication_error <- function(user, message = NULL, parent = NULL, call = NULL) {
  check_string(user, "user")
  check_string(message, "message", allow_null = TRUE)
  make_condition("AuthenticationError",
    message_or(message, sprintf("Authentication failed for user %s", quote_name(user))),
    fields = list(user = user),
    parent = parent, call = call
  )
}

#' @rdname job_errors
#' @export
authorization_error <- function(user, permission, parent = NULL, call = NULL) {
  check_string(user, "user")
  check_string(permission, "permission")
  make_condition("AuthorizationError",
    sprintf("User %s lacks permission %s", quote_name(user), quote_name(permission)),
    fields = list(user = user, permission = permission),
    parent = parent, call = call
  )
}

#' @rdname job_errors
#' @export
configuration_error <- function(option, message = NULL, parent = NULL, call = NULL) {
  check_string(option, "option")
  check_string(message, "message", allow_null = TRUE)
  make_condition("ConfigurationError",
    message_or(message, sprintf("Invalid configuration for %s", quote_name(option))),
    fields = list(option = option),
    parent = parent, call = call
  )
}

#' @rdname job_errors
#' @export
resource_not_found_error <- function(resource_type, identifier, parent = NULL, call = NULL) {
  check_string(resource_type, "resource_type")
  check_string(identifier, "identifier")
  make_condition("ResourceNotFoundError",
    sprintf("%s with identifier %s not found", resource_type, quote_name(identifier)),
    fields = list(resource_type = resource_type, identifier = identifier),
    parent = parent, call = call
  )
}

#' @rdname job_errors
#' @export
operation_timeout_error <- function(operation, timeout, parent = NULL, call = NULL) {
  check_string(operation, "operation")
  check_seconds(timeout, "timeout")
  make_condition("OperationTimeoutError",
    sprintf(
      "Operation %s timed out after %s seconds",
      quote_name(operation), format_number(timeout)
    ),
    fields = list(operation = operation, timeout = timeout),
    parent = parent, call = call
  )
}

#' Data engineering failures
#'
#' Errors raised by batch data processing: a transformation step that failed,
#' an ETL job that did not complete, and a batch that could not be processed.
#' All inherit from `dataexcept_data_engineering_error`.
#'
#' @param step Name of the transformation step.
#' @param details Optional detail, appended to the message.
#' @param job_name Name of the ETL job.
#' @param batch_id Identifier of the batch.
#' @inheritParams validation_error
#' @return A condition inheriting from `dataexcept_data_engineering_error`.
#' @family dataexcept errors
#' @name data_engineering_errors
#' @examples
#' process_batch <- function(id, rows) {
#'   tryCatch(
#'     sum(rows),
#'     error = function(e) stop(batch_processing_error(id, parent = e))
#'   )
#' }
#' err <- tryCatch(process_batch("2026-09-27", list("a", 1)), error = identity)
#' conditionMessage(err)
#'
#' data_transformation_error("normalise_amounts", details = "12 rows had no currency")
NULL

#' @rdname data_engineering_errors
#' @export
data_transformation_error <- function(step, details = NULL, parent = NULL, call = NULL) {
  check_string(step, "step")
  check_string(details, "details", allow_null = TRUE)
  make_condition("DataTransformationError",
    with_details(sprintf("Data transformation %s failed", quote_name(step)), details),
    fields = list(step = step, details = details),
    parent = parent, call = call
  )
}

#' @rdname data_engineering_errors
#' @export
etl_job_error <- function(job_name, message = NULL, parent = NULL, call = NULL) {
  check_string(job_name, "job_name")
  check_string(message, "message", allow_null = TRUE)
  make_condition("ETLJobError",
    message_or(message, sprintf("ETL job %s failed", quote_name(job_name))),
    fields = list(job_name = job_name),
    parent = parent, call = call
  )
}

#' @rdname data_engineering_errors
#' @export
batch_processing_error <- function(batch_id, parent = NULL, call = NULL) {
  check_string(batch_id, "batch_id")
  check_condition(parent, "parent")
  make_condition("BatchProcessingError",
    with_cause(sprintf("Batch %s processing failed", quote_name(batch_id)), parent),
    fields = list(batch_id = batch_id),
    parent = parent, call = call
  )
}
