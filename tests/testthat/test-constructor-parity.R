# The R constructors against the Python classes of the same name: each case in
# constructor-parity.json was built by the Python package with the arguments
# it lists, and the R constructor given the same arguments must produce the
# same type, message, failure metadata, attributes and cause.

constructor_cases <- function() {
  path <- testthat::test_path("fixtures", "constructor-parity.json")
  jsonlite::read_json(path, simplifyVector = FALSE)
}

# The R constructor for a type: its snake_case name.
constructor_for <- function(type) {
  name <- gsub("([A-Z]+)([A-Z][a-z])", "\\1_\\2", type)
  name <- tolower(gsub("([a-z0-9])([A-Z])", "\\1_\\2", name))
  get(name, envir = asNamespace("dataexcept"))
}

# Python arguments whose R name differs: a string detail is `details` in R,
# where `cause` means the chained condition.
renamed <- list(CrossValidationError = c(cause = "details"))

r_arguments <- function(case) {
  arguments <- lapply(case$arguments, function(value) {
    if (is.list(value) && !is.null(value$exception)) {
      return(simpleError(value$exception))
    }
    if (is.list(value) && !is.null(value$float)) {
      return(as.double(value$float))
    }
    if (is.list(value)) {
      return(unlist(value))
    }
    value
  })
  is_parent <- vapply(arguments, inherits, logical(1), "condition")
  names(arguments)[is_parent] <- "parent"
  rename <- renamed[[case$type]]
  hit <- names(arguments) %in% names(rename)
  names(arguments)[hit] <- rename[names(arguments)[hit]]
  arguments
}

# Attributes as JSON would read them back, so that 3600 and 3600.0 agree and
# key order does not matter.
normalise <- function(x) {
  if (length(x) == 0L) {
    return(list())
  }
  x <- jsonlite::fromJSON(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA),
    simplifyVector = FALSE
  )
  x[order(names(x))]
}

test_that("every new Python type has a parity case", {
  types <- unique(vapply(constructor_cases(), `[[`, character(1), "type"))
  registered <- dataexcept_classes()
  expect_true(all(types %in% registered$type))
  expect_true(all(registered$python[registered$type %in% types]))
})

for (case in constructor_cases()) {
  test_that(sprintf("R agrees with Python: %s", case$name), {
    cnd <- do.call(constructor_for(case$type), r_arguments(case))
    expected <- case$expected
    envelope <- condition_to_envelope(cnd)

    expect_identical(condition_type(cnd), expected$type)
    expect_s3_class(cnd, dataexcept_classes()$class[dataexcept_classes()$type == case$type])
    expect_identical(conditionMessage(cnd), expected$message)
    expect_identical(envelope$failure, expected$failure)
    expect_identical(normalise(envelope$attributes), normalise(expected$attributes))
    if (is.null(expected$cause)) {
      expect_null(envelope$cause)
    } else {
      expect_identical(envelope$cause$message, expected$cause)
    }
  })
}
