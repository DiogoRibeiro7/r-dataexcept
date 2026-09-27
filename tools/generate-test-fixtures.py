"""Generate the cross-language test fixtures for the R package.

Run from the repository root, with a checkout of the Python DataExcept
package and `jsonschema` installed:

    python tools/generate-test-fixtures.py /path/to/DataExcept

It writes two files under tests/testthat/fixtures/:

* redaction-parity.json -- inputs and the Python package's output for
  redact_url() and redact_urls_in_text(), with and without the path. The R
  tests require identical output.
* validation-cases.json -- envelope payloads, valid and invalid, each with the
  verdict of a JSON Schema draft 2020-12 validator against
  envelope-1.0.0.json. The R tests require validate_envelope() to agree.

It also copies the schema and the reference envelope fixtures into
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


def main(python_repo: str) -> None:
    python_root = Path(python_repo).resolve()
    sys.path.insert(0, str(python_root))
    from dataexcept.redaction import redact_url, redact_urls_in_text

    schema_dir = python_root / "docs" / "schema"
    shutil.copy(schema_dir / "envelope-1.0.0.json", ROOT / "inst" / "schema")
    for fixture in sorted((schema_dir / "fixtures").glob("*.json")):
        shutil.copy(fixture, ROOT / "inst" / "schema" / "fixtures")

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


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: python tools/generate-test-fixtures.py /path/to/DataExcept")
    main(sys.argv[1])
