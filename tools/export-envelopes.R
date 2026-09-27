library(dataexcept)

# Write a spread of R conditions as envelopes, for validation against the
# published JSON Schema by an independent validator (see
# .github/workflows/envelope-contract.yml).
#
#   Rscript tools/export-envelopes.R <output-directory>

args <- commandArgs(trailingOnly = TRUE)
out <- if (length(args) >= 1L) args[[1L]] else "envelopes"
dir.create(out, showWarnings = FALSE, recursive = TRUE)

write_envelope <- function(name, cnd, ...) {
  writeLines(condition_to_json(cnd, ...), file.path(out, paste0(name, ".json")))
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

for (path in list.files(system.file("schema", "fixtures", package = "dataexcept"), full.names = TRUE)) {
  json <- paste(readLines(path, warn = FALSE), collapse = "\n")
  write_envelope(paste0("reread-", sub("\\.json$", "", basename(path))), envelope_to_condition(json))
}

if (requireNamespace("rlang", quietly = TRUE)) {
  write_envelope("rlang-error", tryCatch(
    rlang::abort("rlang failure", class = "export_error", detail = 1L, parent = root),
    error = identity
  ))
}

cat(length(list.files(out, pattern = "\\.json$")), "envelopes written to", out, "\n")
