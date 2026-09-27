check_orders <- function(df) {
  collect_errors(
    customer = if (!"customer_id" %in% names(df)) {
      stop(missing_column_error("customer_id", dataframe = "orders"))
    },
    amount = if (!is.numeric(df$amount)) {
      stop(dtype_mismatch_error("amount", "numeric", class(df$amount)[1]))
    },
    rows = if (nrow(df) == 0L) stop("no rows")
  )
}

test_that("condition_group() builds a dataexcept error holding its members", {
  members <- list(
    missing_column_error("customer_id"),
    dtype_mismatch_error("amount", "numeric", "character")
  )
  group <- condition_group(members, "orders failed validation", table = "orders")
  expect_s3_class(group, c(
    "dataexcept_condition_group", "dataexcept_error", "error", "condition"
  ), exact = TRUE)
  expect_identical(condition_type(group), "ConditionGroup")
  expect_identical(group$message, "orders failed validation (2 failures)")
  expect_identical(group$table, "orders")
  expect_identical(group_members(group), members)

  caught <- tryCatch(stop(group), dataexcept_condition_group = function(e) "group")
  expect_identical(caught, "group")
  caught <- tryCatch(stop(group), dataexcept_error = function(e) "dataexcept")
  expect_identical(caught, "dataexcept")
})

test_that("the count is the whole message when none is given", {
  expect_identical(condition_group(list(simpleError("a")))$message, "1 failure")
  expect_identical(
    condition_group(list(simpleError("a"), simpleError("b")))$message,
    "2 failures"
  )
})

test_that("member names are dropped: the envelope's members are an array", {
  group <- condition_group(list(a = simpleError("a"), b = simpleError("b")))
  expect_null(names(group_members(group)))
})

test_that("the message lists the members, one line each", {
  group <- condition_group(list(
    missing_column_error("customer_id", dataframe = "orders"),
    simpleError("first line\nsecond line"),
    simpleWarning("a warning member")
  ), "orders failed validation")
  expect_identical(
    conditionMessage(group),
    paste(
      "orders failed validation (3 failures)",
      "* Missing required column 'customer_id' in data frame 'orders'",
      "* first line",
      "* a warning member",
      sep = "\n"
    )
  )
  expect_error(stop(group), "\\* first line")
})

test_that("a long group lists ten members and counts the rest", {
  members <- lapply(1:13, function(i) simpleError(sprintf("failure %d", i)))
  lines <- strsplit(conditionMessage(condition_group(members)), "\n")[[1]]
  expect_length(lines, 12L)
  expect_identical(lines[[11]], "* failure 10")
  expect_identical(lines[[12]], "* ... and 3 more")
})

test_that("member lines are redacted like every other dataexcept message", {
  leaky <- simpleError("GET https://user:secret@api.example.com/v1?token=abc failed")
  message <- conditionMessage(condition_group(list(leaky)))
  expect_no_match(message, "secret|abc")
  expect_match(message, "api.example.com", fixed = TRUE)
})

test_that("condition_group() checks its arguments", {
  expect_error(condition_group(list()), "non-empty list")
  expect_error(condition_group(simpleError("a")), "non-empty list")
  expect_error(condition_group("a"), "non-empty list")
  expect_error(condition_group(list(simpleError("a"), "b")), "must be a condition")
  expect_error(condition_group(list(simpleError("a")), c("x", "y")), "single string")
  expect_error(condition_group(list(simpleError("a")), failure = "transient"), "failure_metadata")
  expect_error(condition_group(list(simpleError("a")), parent = "cause"), "condition object")
})

test_that("a group's failure metadata is its members' when they agree", {
  permanent_group <- condition_group(list(
    validation_error("age", -1),
    validation_error("income", NA)
  ))
  expect_identical(condition_failure(permanent_group)$kind, "permanent")
  expect_false(is_retryable(permanent_group))

  transient <- function(seconds = NULL) {
    with_failure_metadata(
      api_error("https://api.example.com/v1", status_code = 503L),
      failure_metadata("transient", retryable = TRUE, retry_after_seconds = seconds)
    )
  }
  group <- condition_group(list(transient(2), transient(), transient(30)))
  expect_identical(condition_failure(group)$kind, "transient")
  expect_true(is_retryable(group))
  expect_identical(condition_failure(group)$retry_after_seconds, 30)

  group <- condition_group(list(transient(), transient()))
  expect_null(condition_failure(group)$retry_after_seconds)
})

test_that("a group with disagreeing or unclassified members is unclassified", {
  transient <- with_failure_metadata(
    api_error("https://api.example.com/v1", status_code = 503L),
    failure_metadata("transient", retryable = TRUE)
  )
  mixed <- condition_group(list(transient, validation_error("age", -1)))
  expect_identical(condition_failure(mixed)$kind, "unknown")
  expect_true(is.na(is_retryable(mixed)))

  same_kind <- condition_group(list(
    transient,
    with_failure_metadata(
      api_error("https://api.example.com/v1"),
      failure_metadata("transient", retryable = FALSE)
    )
  ))
  expect_identical(condition_failure(same_kind)$kind, "unknown")

  foreign <- condition_group(list(validation_error("age", -1), simpleError("boom")))
  expect_identical(condition_failure(foreign)$kind, "unknown")
})

test_that("explicit failure metadata overrides the members'", {
  group <- condition_group(
    list(validation_error("age", -1)),
    failure = failure_metadata("transient", retryable = TRUE)
  )
  expect_true(is_retryable(group))
})

test_that("group_members() is empty for a condition that is not a group", {
  expect_identical(group_members(simpleError("a")), list())
  expect_identical(group_members(validation_error("age", -1)), list())
  expect_error(group_members("a"), "condition object")
})

test_that("collect_errors() evaluates every argument and keeps the errors", {
  orders <- data.frame(id = 1:2, amount = c("10", "20"))
  errors <- check_orders(orders)
  expect_named(errors, c("customer", "amount"))
  expect_s3_class(errors$customer, "dataexcept_missing_column_error")
  expect_s3_class(errors$amount, "dataexcept_dtype_mismatch_error")

  expect_identical(check_orders(data.frame(customer_id = 1, amount = 10)), list())
})

test_that("collect_errors() names only the errors whose arguments were named", {
  errors <- collect_errors(stop("a"), second = stop("b"), 1)
  expect_named(errors, c("", "second"))

  errors <- collect_errors(stop("a"), 1, stop("b"))
  expect_null(names(errors))
  expect_identical(vapply(errors, conditionMessage, character(1)), c("a", "b"))

  expect_identical(collect_errors(), list())
})

test_that("collect_errors() evaluates in the caller's environment, lazily", {
  seen <- character()
  record <- function(x) seen <<- c(seen, x)
  errors <- collect_errors(record("a"), stop("b"), record("c"))
  expect_identical(seen, c("a", "c"))
  expect_length(errors, 1L)

  limit <- 3
  errors <- collect_errors(if (limit > 2) stop("too high"))
  expect_identical(conditionMessage(errors[[1]]), "too high")
})

test_that("collect_errors() works when its arguments are passed on as `...`", {
  run_checks <- function(...) collect_errors(...)
  threshold <- 10
  errors <- run_checks(value = if (threshold > 5) stop("threshold too high"))
  expect_named(errors, "value")
  expect_identical(conditionMessage(errors$value), "threshold too high")
})

test_that("collect_errors() lets warnings and messages through", {
  expect_warning(
    errors <- collect_errors(warning("careful"), stop("broken")),
    "careful"
  )
  expect_length(errors, 1L)
  expect_message(collect_errors(message("note")), "note")
})

test_that("a group is written as the envelope's exception group", {
  root <- simpleError("disk unavailable")
  group <- condition_group(
    list(
      missing_column_error("customer_id"),
      file_read_error("orders.csv", parent = root)
    ),
    "orders failed validation",
    parent = simpleError("batch 7")
  )
  envelope <- condition_to_envelope(group)
  expect_identical(envelope$type, "ConditionGroup")
  expect_identical(envelope$message, "orders failed validation (2 failures)")
  expect_length(envelope$exceptions, 2L)
  expect_identical(envelope$exceptions[[1]]$type, "MissingColumnError")
  expect_identical(envelope$exceptions[[2]]$cause$message, "disk unavailable")
  expect_identical(envelope$cause$message, "batch 7")
  expect_null(envelope$attributes)
  expect_true(is_envelope(condition_to_json(group)))

  # The keys come in the schema's order, with the members before the cause.
  expect_identical(
    names(envelope),
    c("type", "module", "message", "failure", "exceptions", "cause")
  )
})

test_that("a group's members count toward max_depth", {
  inner <- condition_group(list(simpleError("deep")))
  outer <- condition_group(list(inner))
  envelope <- condition_to_envelope(outer, max_depth = 1L)
  expect_identical(envelope$exceptions[[1]]$exceptions[[1]], list(truncated = TRUE))
})

test_that("a group survives a round trip through the envelope", {
  group <- condition_group(
    list(validation_error("age", -1), simpleError("boom")),
    "import failed"
  )
  json <- condition_to_json(group)
  back <- envelope_to_condition(json)
  expect_s3_class(back, "dataexcept_condition_group")
  expect_s3_class(back, "dataexcept_error")
  expect_identical(condition_type(back), "ConditionGroup")
  expect_length(group_members(back), 2L)
  expect_s3_class(group_members(back)[[1]], "dataexcept_validation_error")
  expect_identical(conditionMessage(back), conditionMessage(group))
  expect_identical(condition_to_json(back), json)
})

test_that("a Python ExceptionGroup is read as a group", {
  cnd <- envelope_to_condition(fixture("nested-exception-group.json"))
  expect_s3_class(cnd, "dataexcept_condition_group")
  expect_identical(condition_type(cnd), "ExceptionGroup")
  expect_length(group_members(cnd), 2L)
  expect_s3_class(group_members(cnd)[[1]], "dataexcept_condition_group")
  expect_false(inherits(group_members(cnd)[[2]], "dataexcept_condition_group"))
  expect_identical(
    conditionMessage(cnd),
    paste(
      "parallel failures (2 sub-exceptions)",
      "* row failures (2 sub-exceptions)",
      "* disk unavailable",
      sep = "\n"
    )
  )
  caught <- tryCatch(stop(cnd), dataexcept_condition_group = function(e) "group")
  expect_identical(caught, "group")
})

test_that("an empty exception group in an envelope is still a group", {
  json <- '{"type": "ExceptionGroup", "module": "builtins", "message": "none", "exceptions": []}'
  cnd <- envelope_to_condition(json)
  expect_s3_class(cnd, "dataexcept_condition_group")
  expect_identical(group_members(cnd), list())
  expect_identical(conditionMessage(cnd), "none")
  expect_identical(condition_to_envelope(cnd)$exceptions, list())
})

test_that("wrap_errors() re-signals an error as the constructor's, with the cause", {
  err <- tryCatch(
    wrap_errors(stop("disk unavailable"), file_read_error, path = "orders.csv"),
    error = identity
  )
  expect_s3_class(err, "dataexcept_file_read_error")
  expect_identical(err$path, "orders.csv")
  expect_s3_class(err$parent, "simpleError")
  expect_identical(conditionMessage(err$parent), "disk unavailable")
  expect_identical(condition_to_envelope(err)$cause$message, "disk unavailable")
})

test_that("wrap_errors() returns the value when nothing fails", {
  expect_identical(wrap_errors(1 + 1, file_read_error, path = "x"), 2)
  expect_null(wrap_errors(NULL, file_read_error, path = "x"))
})

test_that("wrap_errors() passes warnings through unless asked to wrap them", {
  expect_warning(
    value <- wrap_errors(
      {
        warning("careful")
        "done"
      },
      file_read_error,
      path = "x"
    ),
    "careful"
  )
  expect_identical(value, "done")

  err <- tryCatch(
    wrap_errors(warning("careful"), file_read_error, path = "x", on = c("error", "warning")),
    error = identity
  )
  expect_s3_class(err, "dataexcept_file_read_error")
  expect_s3_class(err$parent, "simpleWarning")
})

test_that("wrap_errors() wraps the warning read.csv() gives for a missing file", {
  path <- tempfile(fileext = ".csv")
  err <- tryCatch(
    wrap_errors(utils::read.csv(path), file_read_error, path = path, on = c("error", "warning")),
    error = identity
  )
  expect_s3_class(err, "dataexcept_file_read_error")
  expect_s3_class(err$parent, "warning")
})

test_that("wrap_errors() matches the classes in `on`, including a family", {
  inner <- function() stop(missing_column_error("id"))
  err <- tryCatch(
    wrap_errors(inner(), data_loading_error, source = "orders", on = "dataexcept_data_frame_error"),
    error = identity
  )
  expect_s3_class(err, "dataexcept_data_loading_error")
  expect_s3_class(err$parent, "dataexcept_missing_column_error")

  err <- tryCatch(
    wrap_errors(stop("other"), data_loading_error, source = "orders", on = "dataexcept_error"),
    error = identity
  )
  expect_s3_class(err, "simpleError")
})

test_that("wrap_errors() sets the failure metadata it is given", {
  err <- tryCatch(
    wrap_errors(
      stop("connection reset by peer"),
      api_error,
      endpoint = "https://api.example.com/v1",
      failure = failure_metadata("transient", retryable = TRUE, retry_after_seconds = 5)
    ),
    error = identity
  )
  expect_true(is_retryable(err))
  expect_identical(condition_failure(err)$retry_after_seconds, 5)
})

test_that("wrap_errors() takes any constructor that returns a condition", {
  own <- function(parent) {
    new_dataexcept_error("import step failed",
      type = "ImportError", class = "myapp_import_error", parent = parent
    )
  }
  err <- tryCatch(wrap_errors(stop("boom"), own), error = identity)
  expect_s3_class(err, "myapp_import_error")
  expect_identical(conditionMessage(err$parent), "boom")

  plain <- function(parent) errorCondition("plain", class = "myapp_plain", parent = parent)
  err <- tryCatch(wrap_errors(stop("boom"), plain), error = identity)
  expect_s3_class(err, "myapp_plain")
})

test_that("wrap_errors() does not wrap an error twice", {
  err <- tryCatch(
    wrap_errors(stop("root"), file_read_error, path = "x"),
    error = identity
  )
  expect_s3_class(err$parent, "simpleError")
  expect_null(err$parent$parent)
})

test_that("nested wrap_errors() calls build a chain", {
  err <- tryCatch(
    wrap_errors(
      wrap_errors(stop("root"), file_read_error, path = "orders.csv"),
      data_loading_error,
      source = "orders"
    ),
    error = identity
  )
  expect_s3_class(err, "dataexcept_data_loading_error")
  expect_s3_class(err$parent, "dataexcept_file_read_error")
  expect_identical(conditionMessage(err$parent$parent), "root")
})

test_that("wrap_errors() leaves interrupts alone", {
  interrupt <- structure(class = c("interrupt", "condition"), list(message = "", call = NULL))
  seen <- withCallingHandlers(
    tryCatch(
      wrap_errors(signalCondition(interrupt), file_read_error, path = "x", on = "condition"),
      error = function(e) "wrapped"
    ),
    interrupt = function(cnd) NULL
  )
  expect_null(seen)
})

test_that("wrap_errors() checks its arguments", {
  expect_error(wrap_errors(1, "file_read_error"), "must be a function")
  expect_error(wrap_errors(1, file_read_error, on = character()), "at least one")
  expect_error(wrap_errors(1, file_read_error, on = NA_character_), "without NA")
  expect_error(wrap_errors(1, file_read_error, failure = "transient"), "failure_metadata")
  expect_error(
    wrap_errors(stop("boom"), function(parent) "not a condition"),
    "must return a condition"
  )
})
