#' dataexcept: structured, classed failures that cross language boundaries
#'
#' dataexcept gives data and modelling code three things base R conditions do
#' not have on their own:
#'
#' * **A shared vocabulary of classed errors** with structured fields --
#'   [missing_column_error()], [convergence_error()], [api_error()] and the
#'   rest (see [dataexcept_classes()]) -- each carrying failure metadata that
#'   says whether a retry can succeed ([failure_metadata()]).
#' * **One failure format across R and Python.** [condition_to_json()] writes
#'   any R condition as the envelope the Python DataExcept package publishes as
#'   a JSON Schema, and [envelope_to_condition()] reads an envelope from either
#'   language back into an R condition that ordinary handlers catch.
#' * **Classes for base R's text-only warnings.** [with_classed_warnings()]
#'   turns warnings such as `glm.fit`'s non-convergence into classed warnings,
#'   recognised in any session language.
#'
#' Credentials in URLs are removed before they reach a condition or an
#' envelope ([redact_url()]).
#'
#' @keywords internal
"_PACKAGE"
