"""Generate the cross-language test fixtures for the R package.

Run from the repository root, with a checkout of the Python DataExcept
package and `jsonschema` installed:

    python tools/generate-test-fixtures.py /path/to/DataExcept

It writes these files under tests/testthat/fixtures/:

* redaction-parity.json -- inputs and the Python package's output for
  redact_url() and redact_urls_in_text(), with and without the path. The R
  tests require identical output.
* validation-cases.json -- envelope payloads, valid and invalid, each with the
  verdict of a JSON Schema draft 2020-12 validator against
  envelope-1.0.0.json. The R tests require validate_envelope() to agree.
* observability-parity.json -- failure events and OpenTelemetry attributes
  the Python package produces for a set of exceptions and operation
  contexts. The R tests read each envelope back and require
  condition_to_event() and condition_to_otel_attributes() to agree.
* constructor-parity.json -- exceptions built with the Python classes the R
  package also defines, with the arguments given and the envelope written.
  The R tests call the matching R constructor with the same arguments and
  require the same type, message, failure metadata and attributes.

It also copies the envelope and Pino schemas and the reference fixtures --
each envelope, and the Python package's Pino projection of it -- into
inst/schema/, so the R package tests against what the Python package emits.
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tests" / "testthat" / "fixtures"

REDACTION_CASES = [
    "https://user:pass@example.com/path?x=1",
    "https://api.example.com/v1/orders?page=2&api_key=abc123",
    "https://api.example.com/v1/orders?page=2&keyword=monkey&design=x",
    "https://api.example.com/cb#access_token=abc&state=xyz",
    "https://host/p?accessToken=abc&X-Amz-Signature=deadbeef&X-Amz-Date=2026",
    "https://host/p?code=123&client_id=abc&nonce=1",
    "postgresql://analyst:s3cret@db.internal:5432/sales",
    "sqlite:///tmp/db.sqlite",
    "file:///etc/passwd",
    "HTTPS://User:Pw@Example.com/Path?Token=1",
    "https://host/p?token=a%20b&q=hello+world&x=%E2%9C%93",
    "https://host/p?flag&token=zzz",
    "https://host/p?a=1&&token=2",
    "https://hooks.slack.com/services/T000/B000/XXXXXXXX",
    "https://example.com",
    "https://example.com/?",
    "see https://h/p?token=SECRET: retry",
    "feature_https://u:p@h/x done.",
    'urls: (https://a:b@h/x), [https://h/y?sig=1]; "https://h/z?password=p" end!',
    "no url here",
    "mailto:someone@example.com",
    "https://h/p?pass_phrase=1&passphrase=2&authors=3&my_session_id=4",
    "https://h/p?SAS=1&sig=2&Signature=3&jwt=4&bearer=5",
    "two: https://a:b@h1/x and https://h2/y?secret=s",
]

IDENTITY = {"type": "ValueError", "module": "builtins", "message": "bad row"}
FAILURE = {"kind": "unknown", "retryable": None, "retry_after_seconds": None}


def record(**extra):
    return {**IDENTITY, **extra}


VALIDATION_CASES = {
    "minimal record": record(),
    "record with unknown field": record(future_field=1),
    "record with failure": record(failure=FAILURE),
    "failure with delay": record(
        failure={"kind": "transient", "retryable": True, "retry_after_seconds": 2.5}
    ),
    "nested cause and context": record(cause=record(), context=record(cause=record())),
    "group": record(exceptions=[record(), record(exceptions=[record()])]),
    "empty group": record(exceptions=[]),
    "cycle record": {**IDENTITY, "cycle": True},
    "truncation marker": {"truncated": True},
    "cause is a marker": record(cause={"truncated": True}),
    "missing module": {"type": "ValueError", "message": "bad row"},
    "numeric type": {**IDENTITY, "type": 1},
    "null message": {**IDENTITY, "message": None},
    "truncated false": {"truncated": False},
    "marker with extra field": {"truncated": True, "type": "ValueError"},
    "cycle with attributes": {**IDENTITY, "cycle": True, "attributes": {}},
    "cycle false": {**IDENTITY, "cycle": False},
    "record with truncated": record(truncated=True),
    "failure missing field": record(failure={"kind": "unknown", "retryable": None}),
    "failure bad kind": record(failure={**FAILURE, "kind": "fatal"}),
    "failure string retryable": record(failure={**FAILURE, "retryable": "yes"}),
    "failure negative delay": record(failure={**FAILURE, "retry_after_seconds": -1}),
    "failure null": record(failure=None),
    "attributes array": record(attributes=[1, 2]),
    "cause not object": record(cause="boom"),
    "exceptions object": record(exceptions={"a": record()}),
    "bad group member": record(exceptions=[record(), {"type": "X"}]),
    "deep invalid cause": record(cause=record(cause=record(cause={"message": "x"}))),
    "top-level array": [record()],
}


# (exception factory, OperationContext arguments). Contexts carry URL-shaped
# values so that redaction is part of what is compared.
def observability_cases():
    from dataexcept import (
        ApiError,
        FailureMetadata,
        MissingColumnError,
        ServiceTimeoutError,
        ValidationError,
    )

    def raised(factory):
        try:
            raise factory()
        except BaseException as exc:  # noqa: BLE001 - any exception is a case
            return exc

    def chained():
        try:
            raise OSError("connection refused for https://user:pw@api.example.com/v1?token=t")
        except OSError as cause:
            try:
                raise ApiError("https://user:pw@api.example.com/v1?token=t", 502) from cause
            except ApiError as exc:
                return exc

    return {
        "validation with a full context": (
            raised(lambda: ValidationError("age", -1)),
            {
                "system": "api",
                "component": "accounts",
                "operation": "POST /users/{id}",
                "request_id": "req-42",
                "job_id": "job-7",
                "correlation_id": "corr-9",
                "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
                "span_id": "00f067aa0ba902b7",
            },
        ),
        "transient failure with a delay": (
            raised(
                lambda: ServiceTimeoutError("payments", timeout_seconds=30.0).with_failure_metadata(
                    FailureMetadata(
                        failure_kind="transient", retryable=True, retry_after_seconds=5.0
                    )
                )
            ),
            {"system": "worker", "operation": "billing.settle_invoice", "job_id": "job-42"},
        ),
        "third-party exception without failure metadata": (
            raised(lambda: KeyError("customer_id")),
            {},
        ),
        "credentials in the context and the chain": (
            chained(),
            {
                "system": "https://user:secret@example.com/private?token=hidden",
                "correlation_id": "corr-1",
            },
        ),
        "missing column with no context": (
            raised(lambda: MissingColumnError("customer_id", dataframe="orders")),
            None,
        ),
    }


# (name, class name, keyword arguments). An argument written as
# {"exception": text} is an exception with that message -- the R side passes a
# condition as `parent` -- and {"float": "nan"} is a float JSON cannot hold.
CONSTRUCTOR_CASES = [
    ("data format", "DataFormatError", {"expected_formats": ["csv", "parquet"], "found_format": "xlsx"}),
    ("data format, one expected", "DataFormatError", {"expected_formats": ["csv"], "found_format": "json"}),
    (
        "schema mismatch",
        "SchemaMismatchError",
        {"expected": "id: int, amount: float", "found": "id: int, amount: str"},
    ),
    ("data drift", "DataDriftError", {"feature": "income", "drift_score": 0.41726}),
    (
        "data drift, own message",
        "DataDriftError",
        {"feature": "age", "drift_score": 0.2, "message": "age drifted"},
    ),
    ("data leakage", "DataLeakageError", {"feature": "target_mean", "stage": "cross-validation"}),
    ("data imbalance", "DataImbalanceError", {"ratio": 0.0526, "threshold": 0.2}),
    ("outlier detection", "OutlierDetectionError", {"method": "iqr"}),
    (
        "outlier detection, details",
        "OutlierDetectionError",
        {"method": "isolation_forest", "details": "contamination must be in (0, 0.5]"},
    ),
    ("model evaluation", "ModelEvaluationError", {"metric": "auc", "value": 0.5}),
    ("model evaluation, nan", "ModelEvaluationError", {"metric": "rmse", "value": {"float": "nan"}}),
    ("cross-validation", "CrossValidationError", {"folds": 5}),
    (
        "cross-validation, detail",
        "CrossValidationError",
        {"folds": 10, "cause": "fold 3 had a single class"},
    ),
    ("hyperparameter, number", "HyperparameterError", {"param": "max_depth", "value": -1}),
    ("hyperparameter, string", "HyperparameterError", {"param": "booster", "value": "gbdt"}),
    ("training timeout", "TrainingTimeoutError", {"model_type": "xgboost", "timeout": 3600}),
    ("training timeout, fraction", "TrainingTimeoutError", {"model_type": "glm", "timeout": 90.5}),
    (
        "model serialization",
        "ModelSerializationError",
        {"path": "models/churn.rds", "original": {"exception": "disk full"}},
    ),
    ("overfitting", "OverfittingError", {"train_metric": 0.99, "val_metric": 0.71}),
    ("underfitting", "UnderfittingError", {"train_metric": 0.52, "threshold": 0.7}),
    ("resource limit, string", "ResourceLimitError", {"resource": "memory", "limit": "16GB"}),
    ("resource limit, number", "ResourceLimitError", {"resource": "cpu", "limit": 8}),
    ("external service", "ExternalServiceError", {"service_name": "rates-api", "status_code": 503}),
    (
        "external service, response",
        "ExternalServiceError",
        {
            "service_name": "rates-api",
            "status_code": 502,
            "response": "bad gateway",
            "message": "rates-api returned 502",
        },
    ),
    ("service timeout", "ServiceTimeoutError", {"service_name": "payments", "timeout_seconds": 30}),
    (
        "service timeout, fraction",
        "ServiceTimeoutError",
        {"service_name": "payments", "timeout_seconds": 2.5},
    ),
    ("service authentication", "ServiceAuthenticationError", {"service_name": "rates-api"}),
    ("service authorization", "ServiceAuthorizationError", {"service_name": "rates-api"}),
    ("retry limit", "RetryLimitExceededError", {"operation": "fetch_rates", "retries": 5}),
    ("storage", "StorageError", {"location": "s3://reports/q3.parquet", "operation": "write"}),
    (
        "storage, credentials in the location",
        "StorageError",
        {
            "location": "https://user:pw@storage.example.com/bucket/q3.parquet?sig=abc",
            "operation": "read",
        },
    ),
    ("authentication", "AuthenticationError", {"user": "analyst"}),
    ("authorization", "AuthorizationError", {"user": "analyst", "permission": "write:reports"}),
    ("configuration", "ConfigurationError", {"option": "timeout"}),
    (
        "configuration, own message",
        "ConfigurationError",
        {"option": "retries", "message": "retries must be positive"},
    ),
    (
        "resource not found",
        "ResourceNotFoundError",
        {"resource_type": "Dataset", "identifier": "sales-2026-q3"},
    ),
    ("operation timeout", "OperationTimeoutError", {"operation": "nightly_refresh", "timeout": 600}),
    (
        "operation timeout, cause",
        "OperationTimeoutError",
        {"operation": "export", "timeout": 1.5, "cause": {"exception": "socket closed"}},
    ),
    ("transaction", "TransactionError", {}),
    ("transaction, id", "TransactionError", {"transaction_id": "tx-42"}),
    (
        "transaction, cause",
        "TransactionError",
        {"transaction_id": "tx-43", "cause": {"exception": "deadlock detected"}},
    ),
    ("data transformation", "DataTransformationError", {"step": "normalise_amounts"}),
    (
        "data transformation, details",
        "DataTransformationError",
        {"step": "normalise_amounts", "details": "12 rows had no currency"},
    ),
    ("etl job", "ETLJobError", {"job_name": "daily_sales"}),
    ("batch processing", "BatchProcessingError", {"batch_id": "2026-09-27"}),
    (
        "batch processing, cause",
        "BatchProcessingError",
        {"batch_id": "b-7", "original": {"exception": "bad row"}},
    ),
]

# Attributes the Python classes keep that are not fields in R: the message,
# which the envelope already carries, and the cause, which it writes as the
# `cause` record.
PYTHON_ONLY_ATTRIBUTES = ("message", "original", "original_exception", "cause")


def constructor_cases():
    import dataexcept
    from dataexcept.serialization import exception_to_dict

    def argument(value):
        if isinstance(value, dict) and "exception" in value:
            return RuntimeError(value["exception"])
        if isinstance(value, dict) and "float" in value:
            return float(value["float"])
        return value

    cases = []
    for name, class_name, kwargs in CONSTRUCTOR_CASES:
        exc = getattr(dataexcept, class_name)(**{k: argument(v) for k, v in kwargs.items()})
        envelope = exception_to_dict(exc)
        attributes = {
            key: value
            for key, value in envelope.get("attributes", {}).items()
            if key not in PYTHON_ONLY_ATTRIBUTES
        }
        cases.append(
            {
                "name": name,
                "type": class_name,
                "arguments": kwargs,
                "expected": {
                    "type": envelope["type"],
                    # The envelope message is str(exc), which the Python
                    # classes prefix with "[Type:...]"; the message itself is
                    # the first argument.
                    "message": exc.args[0],
                    "failure": envelope["failure"],
                    "attributes": attributes,
                    "cause": envelope["cause"]["message"] if "cause" in envelope else None,
                },
            }
        )
    return cases


def main(python_repo: str) -> None:
    python_root = Path(python_repo).resolve()
    sys.path.insert(0, str(python_root))
    from dataexcept.redaction import redact_url, redact_urls_in_text

    schema_dir = python_root / "docs" / "schema"
    shutil.copy(schema_dir / "envelope-1.0.0.json", ROOT / "inst" / "schema")
    shutil.copy(schema_dir / "pino-1.0.0.json", ROOT / "inst" / "schema")
    for fixture in sorted((schema_dir / "fixtures").glob("*.json")):
        shutil.copy(fixture, ROOT / "inst" / "schema" / "fixtures")
    pino_fixtures = ROOT / "inst" / "schema" / "fixtures" / "pino"
    pino_fixtures.mkdir(exist_ok=True)
    for fixture in sorted((schema_dir / "fixtures" / "pino").glob("*.json")):
        shutil.copy(fixture, pino_fixtures)

    OUT.mkdir(parents=True, exist_ok=True)
    redaction = [
        {
            "case": case,
            "url": redact_url(case),
            "url_nopath": redact_url(case, keep_path=False),
            "text": redact_urls_in_text(case),
            "text_nopath": redact_urls_in_text(case, keep_path=False),
        }
        for case in REDACTION_CASES
    ]
    (OUT / "redaction-parity.json").write_text(
        json.dumps(redaction, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    schema = json.loads((schema_dir / "envelope-1.0.0.json").read_text())
    validator = Draft202012Validator(schema)
    validation = [
        {
            "name": name,
            "payload": json.dumps(payload),
            "valid": validator.is_valid(payload),
        }
        for name, payload in VALIDATION_CASES.items()
    ]
    (OUT / "validation-cases.json").write_text(
        json.dumps(validation, indent=2) + "\n", encoding="utf-8"
    )

    from dataexcept import OperationContext, exception_to_observability_event
    from dataexcept.opentelemetry import exception_to_otel_attributes

    observability = []
    for name, (exc, context_args) in observability_cases().items():
        context = None if context_args is None else OperationContext(**context_args)
        observability.append(
            {
                "name": name,
                "context": context_args,
                "event": exception_to_observability_event(exc, operation_context=context),
                # The stack trace is Python's own traceback, which R cannot and
                # should not reproduce; everything else must agree.
                "otel": exception_to_otel_attributes(
                    exc,
                    operation_context=context,
                    include_stacktrace=False,
                    include_envelope=True,
                ),
            }
        )
    (OUT / "observability-parity.json").write_text(
        json.dumps(observability, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    (OUT / "constructor-parity.json").write_text(
        json.dumps(constructor_cases(), indent=2, ensure_ascii=False, allow_nan=False) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: python tools/generate-test-fixtures.py /path/to/DataExcept")
    main(sys.argv[1])
