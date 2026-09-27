#' The envelope JSON Schema
#'
#' dataexcept writes and reads envelopes that follow the JSON Schema published
#' by the Python DataExcept package, `envelope-1.0.0.json` (JSON Schema draft
#' 2020-12). The schema is versioned independently of either package: it
#' describes the payload, and within 1.x a later version may add fields but
#' does not change what an established field means. Consumers must ignore
#' fields they do not recognise.
#'
#' A copy of the schema ships with this package, together with the reference
#' fixtures the Python package generates from its own serializer; the test
#' suite reads every fixture and writes it back unchanged.
#'
#' @return `envelope_schema()` returns the schema as a list.
#'   `envelope_schema_version()` returns the schema version, and
#'   `envelope_schema_id()` its `$id`, each a single string.
#' @export
#' @examples
#' envelope_schema_version()
#' envelope_schema_id()
#' names(envelope_schema()$`$defs`)
#'
#' # The file itself, for a JSON Schema validator:
#' system.file("schema", "envelope-1.0.0.json", package = "dataexcept")
envelope_schema <- function() {
  jsonlite::read_json(schema_path(), simplifyVector = FALSE)
}

#' @rdname envelope_schema
#' @export
envelope_schema_version <- function() {
  "1.0.0"
}

#' @rdname envelope_schema
#' @export
envelope_schema_id <- function() {
  "https://diogoribeiro7.github.io/DataExcept/schema/envelope-1.0.0.json"
}

schema_path <- function() {
  system.file("schema", "envelope-1.0.0.json", package = "dataexcept", mustWork = TRUE)
}
