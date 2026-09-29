library(dataexcept)

# Write a spread of R conditions as envelopes, and each one's Pino
# projection, for validation against the published JSON Schemas by an
# independent validator (see .github/workflows/envelope-contract.yml).
#
#   Rscript tools/export-envelopes.R <output-directory>
#
# Envelopes go in the directory itself, projections in its pino/ folder.

args <- commandArgs(trailingOnly = TRUE)
out <- if (length(args) >= 1L) args[[1L]] else "envelopes"
dir.create(file.path(out, "pino"), showWarnings = FALSE, recursive = TRUE)

write_envelope <- function(name, cnd, ...) {
  file <- paste0(name, ".json")
  writeLines(condition_to_json(cnd, ...), file.path(out, file))
  writeLines(condition_to_pino_json(cnd, ..., include_stack = TRUE), file.path(out, "pino", file))
}

root <- simpleError("root cause at https://user:pw@example.com/data?token=t")
separated <- data.frame(y = c(0, 0, 1, 1), x = 1:4)

write_envelope("validation", validation_error("age", -1))
write_envelope("missing-column", missing_column_error("id", dataframe = "orders"))
write_envelope("dtype-mismatch", dtype_mismatch_error("amount", c("numeric", "integer"), "character"))
write_envelope("merge-key", merge_key_error(c("id", "date"), "id"))
write_envelope("data-loading", data_loading_error("s3://k:s@bucket/x.csv", parent = root))
write_envelope("missing-data", missing_data_error("income"))
write_envelope("model-training", model_training_error("xgboost", epoch = 3L))
write_envelope("convergence", convergence_error("glm", iterations = 25L))
write_envelope("prediction", prediction_error("lm", inputs = mtcars))
write_envelope("file-read", file_read_error("/data/x.csv", parent = simpleWarning("cannot open file")))
write_envelope("file-write", file_write_error("/data/y.csv"))
write_envelope("database-connection", database_connection_error("postgresql://a:b@db:5432/sales"))
write_envelope("query-execution", query_execution_error("SELECT 1", parent = root))
write_envelope("host-unreachable", host_unreachable_error("api.example.com"))
write_envelope("connection-timeout", connection_timeout_error("api.example.com", 30))
write_envelope("api-transient", with_failure_metadata(
  api_error("https://api.example.com/v1?api_key=x", status_code = 503L),
  failure_metadata("transient", retryable = TRUE, retry_after_seconds = 2.5)
))
write_envelope("data-format", data_format_error(c("csv", "parquet"), "xlsx"))
write_envelope("schema-mismatch", schema_mismatch_error("id: integer", "id: character"))
write_envelope("data-drift", data_drift_error("income", 0.41726))
write_envelope("data-leakage", data_leakage_error("target_mean", "cross-validation"))
write_envelope("data-imbalance", data_imbalance_error(0.05, 0.2))
write_envelope("outlier-detection", outlier_detection_error("iqr", details = "no variance"))
write_envelope("model-evaluation", model_evaluation_error("auc", NaN))
write_envelope("cross-validation", cross_validation_error(5L, details = "fold 3 had one class"))
write_envelope("hyperparameter", hyperparameter_error("layers", c(64, 32)))
write_envelope("training-timeout", training_timeout_error("xgboost", 3600))
write_envelope("model-serialization", model_serialization_error("m.rds", parent = root))
write_envelope("overfitting", overfitting_error(0.99, 0.71))
write_envelope("underfitting", underfitting_error(0.52, 0.7))
write_envelope("resource-limit", resource_limit_error("memory", "16GB"))
write_envelope("transaction", transaction_error("tx-42", parent = root))
write_envelope("external-service", external_service_error("rates", 502L, response = "bad"))
write_envelope("service-timeout", service_timeout_error("payments", 2.5))
write_envelope("service-authentication", service_authentication_error("rates"))
write_envelope("service-authorization", service_authorization_error("rates"))
write_envelope("retry-limit", retry_limit_exceeded_error("fetch", 5L))
write_envelope("storage", storage_error("https://u:p@store.example.com/b/k?sig=s", "write"))
write_envelope("authentication", authentication_error("analyst"))
write_envelope("authorization", authorization_error("analyst", "write:reports"))
write_envelope("configuration", configuration_error("timeout"))
write_envelope("resource-not-found", resource_not_found_error("Dataset", "sales"))
write_envelope("operation-timeout", operation_timeout_error("refresh", 600))
write_envelope("data-transformation", data_transformation_error("normalise"))
write_envelope("etl-job", etl_job_error("daily_sales"))
write_envelope("batch-processing", batch_processing_error("b-7", parent = root))
write_envelope("group", condition_group(list(
  missing_column_error("id"),
  condition_group(list(simpleError("bad row"), validation_error("age", -1)), "rows"),
  file_read_error("x.csv", parent = root)
), "import failed"))
write_envelope("wrapped", tryCatch(
  wrap_errors(stop("connection reset"), api_error, endpoint = "https://api.example.com/v1"),
  error = identity
))
write_envelope("base-error", simpleError("boom"))
write_envelope("base-warning", simpleWarning("careful"))
write_envelope("base-message", simpleMessage("hello\n"))
write_envelope("awkward-values", new_dataexcept_error(
  "awkward values",
  nan = NaN, inf = -Inf, na = NA, v = 1:3, long = seq_len(1000), df = iris,
  f = mean, nested = list(a = list(b = list(c = 1))), empty = character(),
  date = as.Date("2026-09-27"), named = c(a = 1, b = 2), dbl = 0.1 + 0.2,
  type = "AwkwardValuesError", class = "export_awkward_error"
))
write_envelope("truncated-chain", validation_error("a", 1,
  parent = validation_error("b", 2, parent = validation_error("c", 3, parent = root))
), max_depth = 1L)
write_envelope("no-attributes", validation_error("a", 1), include_attributes = FALSE)

classed <- NULL
withCallingHandlers(
  with_classed_warnings(glm(y ~ x, family = binomial, data = separated)),
  dataexcept_warning = function(w) {
    classed <<- w
    invokeRestart("muffleWarning")
  }
)
write_envelope("classed-warning", classed)

set.seed(1)
withCallingHandlers(
  with_classed_warnings(kmeans(matrix(rnorm(200), ncol = 2), 3, iter.max = 1)),
  dataexcept_warning = function(w) {
    classed <<- w
    invokeRestart("muffleWarning")
  }
)
write_envelope("classed-warning-with-values", classed)

fixtures <- system.file("schema", "fixtures", package = "dataexcept")
for (path in list.files(fixtures, pattern = "\\.json$", full.names = TRUE)) {
  json <- paste(readLines(path, warn = FALSE), collapse = "\n")
  write_envelope(paste0("reread-", sub("\\.json$", "", basename(path))), envelope_to_condition(json))
}

if (requireNamespace("rlang", quietly = TRUE)) {
  write_envelope("rlang-error", tryCatch(
    rlang::abort("rlang failure", class = "export_error", detail = 1L, parent = root),
    error = identity
  ))
}

cat(
  length(list.files(out, pattern = "\\.json$")), "envelopes and their Pino projections written to",
  out, "\n"
)
