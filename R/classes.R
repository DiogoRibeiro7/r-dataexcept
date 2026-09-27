# The class registry: one entry per envelope `type`.
#
# Each R class name is `dataexcept_` followed by the snake_case form of the
# type. Leaf types are shared with the Python package, so an envelope written
# by one language names the same failure the other language would. Two R base
# classes have no Python counterpart under the same name: DataFrameError
# (Python's PandasError) and FileError (Python's CustomIOError), since neither
# Python name means anything in R.

class_entry <- function(class, parent = NULL, kind = "error",
                        failure = failure_metadata(), python = TRUE) {
  list(
    class = class,
    parent = parent,
    kind = kind,
    failure = failure,
    python = python
  )
}

permanent <- function() failure_metadata("permanent", retryable = FALSE)

# The classed warnings are R-only and all children of DataExceptWarning.
warning_entry <- function(class) {
  class_entry(class, "DataExceptWarning", kind = "warning", python = FALSE)
}

class_registry <- function() {
  list(
    DataExceptError = class_entry("dataexcept_error"),
    ValidationError = class_entry(
      "dataexcept_validation_error", "DataExceptError",
      failure = permanent()
    ),
    DataFrameError = class_entry("dataexcept_data_frame_error", "DataExceptError", python = FALSE),
    MissingColumnError = class_entry("dataexcept_missing_column_error", "DataFrameError"),
    DtypeMismatchError = class_entry("dataexcept_dtype_mismatch_error", "DataFrameError"),
    MergeKeyError = class_entry("dataexcept_merge_key_error", "DataFrameError"),
    DataScienceError = class_entry("dataexcept_data_science_error", "DataExceptError"),
    DataLoadingError = class_entry("dataexcept_data_loading_error", "DataScienceError"),
    MissingDataError = class_entry("dataexcept_missing_data_error", "DataScienceError"),
    ModelTrainingError = class_entry("dataexcept_model_training_error", "DataScienceError"),
    ConvergenceError = class_entry("dataexcept_convergence_error", "ModelTrainingError"),
    PredictionError = class_entry("dataexcept_prediction_error", "DataScienceError"),
    FileError = class_entry("dataexcept_file_error", "DataExceptError", python = FALSE),
    FileReadError = class_entry("dataexcept_file_read_error", "FileError"),
    FileWriteError = class_entry("dataexcept_file_write_error", "FileError"),
    DatabaseError = class_entry("dataexcept_database_error", "DataExceptError"),
    DatabaseConnectionError = class_entry("dataexcept_database_connection_error", "DatabaseError"),
    QueryExecutionError = class_entry("dataexcept_query_execution_error", "DatabaseError"),
    NetworkError = class_entry("dataexcept_network_error", "DataExceptError"),
    HostUnreachableError = class_entry("dataexcept_host_unreachable_error", "NetworkError"),
    ConnectionTimeoutError = class_entry("dataexcept_connection_timeout_error", "NetworkError"),
    PipelineError = class_entry("dataexcept_pipeline_error", "DataExceptError"),
    ApiError = class_entry("dataexcept_api_error", "PipelineError"),

    # R-only: several failures reported as one, written as the envelope's
    # exception group.
    ConditionGroup = class_entry("dataexcept_condition_group", "DataExceptError", python = FALSE),

    # R-only: a payload that is not a valid envelope. Permanent -- reading the
    # same bytes again cannot succeed.
    EnvelopeError = class_entry(
      "dataexcept_envelope_error", "DataExceptError",
      failure = permanent(), python = FALSE
    ),

    # Warnings: R-only. They classify base R and stats warnings that arrive
    # with nothing but a message; see with_classed_warnings().
    DataExceptWarning = class_entry("dataexcept_warning", kind = "warning", python = FALSE),
    ConvergenceWarning = warning_entry("dataexcept_convergence_warning"),
    SeparationWarning = warning_entry("dataexcept_separation_warning"),
    BoundaryFitWarning = warning_entry("dataexcept_boundary_fit_warning"),
    RankDeficientPredictionWarning = warning_entry("dataexcept_rank_deficient_prediction_warning"),
    ApproximationWarning = warning_entry("dataexcept_approximation_warning"),
    ZeroVarianceWarning = warning_entry("dataexcept_zero_variance_warning"),
    CoercionWarning = warning_entry("dataexcept_coercion_warning"),
    RecyclingWarning = warning_entry("dataexcept_recycling_warning"),
    NaNProducedWarning = warning_entry("dataexcept_nan_produced_warning"),
    NonNumericArgumentWarning = warning_entry("dataexcept_non_numeric_argument_warning")
  )
}

registry_entry <- function(type) {
  class_registry()[[type]]
}

# The R class vector for a registered type, most specific first, without the
# base "error"/"warning"/"condition" classes.
type_classes <- function(type) {
  registry <- class_registry()
  classes <- character()
  while (!is.null(type)) {
    entry <- registry[[type]]
    if (is.null(entry)) {
      stop(sprintf("Unknown dataexcept type '%s'.", type), call. = FALSE) # nocov
    }
    classes <- c(classes, entry$class)
    type <- entry$parent
  }
  classes
}

#' The dataexcept condition classes
#'
#' Lists every condition type dataexcept defines: its envelope `type`, the R
#' class a handler catches it by, its parent, whether it is an error or a
#' warning, its default failure classification, and whether the same type
#' exists in the Python package.
#'
#' A handler can catch a whole family through a parent class: a
#' `tryCatch(dataexcept_data_frame_error = ...)` handler catches a missing
#' column, a type mismatch and a merge-key failure alike, and
#' `dataexcept_error` catches every error the package defines.
#'
#' @return A data frame with one row per type.
#' @export
#' @examples
#' dataexcept_classes()[, c("type", "class", "parent")]
dataexcept_classes <- function() {
  registry <- class_registry()
  data.frame(
    type = names(registry),
    class = vapply(registry, `[[`, character(1), "class"),
    parent = vapply(registry, function(e) e$parent %||% NA_character_, character(1)),
    kind = vapply(registry, `[[`, character(1), "kind"),
    failure_kind = vapply(registry, function(e) e$failure$kind, character(1)),
    retryable = vapply(registry, function(e) e$failure$retryable %||% NA, logical(1)),
    python = vapply(registry, `[[`, logical(1), "python"),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
}
