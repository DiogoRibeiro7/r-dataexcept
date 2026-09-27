"""Validate every envelope in a directory against envelope-1.0.0.json.

    python tools/validate-envelopes.py <envelope-directory>

Uses an independent JSON Schema (draft 2020-12) validator, and parses in strict
mode: NaN, Infinity and -Infinity are rejected rather than accepted as the
Python json module accepts them by default.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]


def reject_constant(name: str) -> None:
    raise ValueError(f"non-strict JSON constant {name}")


def main(directory: str) -> int:
    schema = json.loads((ROOT / "inst" / "schema" / "envelope-1.0.0.json").read_text())
    validator = Draft202012Validator(schema)
    files = sorted(Path(directory).glob("*.json"))
    if not files:
        print(f"no envelopes found in {directory}")
        return 1
    failures = 0
    for path in files:
        document = json.loads(path.read_text(encoding="utf-8"), parse_constant=reject_constant)
        errors = sorted(validator.iter_errors(document), key=lambda e: list(e.path))
        if errors:
            failures += 1
            print(f"INVALID {path.name}")
            for error in errors[:5]:
                print(f"  {list(error.path)}: {error.message}")
    print(f"{len(files)} envelopes checked, {failures} invalid")
    return 1 if failures else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: python tools/validate-envelopes.py <envelope-directory>")
    sys.exit(main(sys.argv[1]))
