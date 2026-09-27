# Security Policy

## Supported versions

Security fixes are applied to the latest released minor series only.

| Version | Supported |
| --- | --- |
| 0.1.x | ✅ |

## Reporting a vulnerability

**Please do not report security issues through public GitHub issues.**

Use GitHub's private vulnerability reporting instead:

1. Go to the [Security tab](https://github.com/DiogoRibeiro7/r-dataexcept/security).
2. Choose **Report a vulnerability**.

That opens a private advisory visible only to you and the maintainers. If you
cannot use it, email <dfr@esmad.ipp.pt> instead.

Please include enough detail to reproduce the issue: the affected version, a
minimal example, and what an attacker could achieve.

## What to expect

- An acknowledgement within **5 working days**.
- An assessment, and a fix or an explanation of why it is not a vulnerability,
  within **30 days**.
- Credit in the advisory and in `NEWS.md`, unless you would rather stay
  anonymous.

This is a volunteer-maintained project, so please treat those as good-faith
targets rather than a contractual SLA.

## Scope

dataexcept builds R conditions, serialises them to JSON, and parses JSON back
into conditions. It performs no network or filesystem I/O of its own, never
evaluates code taken from an envelope, and imports only jsonlite beyond base R.

Two kinds of issue are realistic, and both are in scope:

- **Information disclosure** through condition messages, fields or envelopes.
  Conditions embed the values that caused a failure, and envelopes exist to be
  written to logs.
- **Resource exhaustion or misbehaviour when reading an untrusted envelope**
  with `envelope_to_condition()`, `validate_envelope()` or `is_envelope()`.

### What is redacted

URLs lose their userinfo and credential-bearing query and fragment parameters
(`api_key`, `accessToken`, `X-Amz-Signature`, `password`, `token` and similar,
matched token by token). Scheme, host and port are kept, because they are what
makes an error actionable. The rules are those of the Python DataExcept
package, and the test suite checks that both give identical output.

Redaction happens at two points:

1. **At construction**, on the message and on the top-level character fields
   of every dataexcept condition. The URL path is kept.
2. **On export**, on every string written into an envelope, at any depth: the
   message, every attribute value and name, and every condition in the cause
   chain, whichever package created it. The URL path is removed too, because
   for webhook-style URLs the path is itself the secret.

### What is not redacted in memory

The envelope is the boundary dataexcept guarantees. Inside the R session, some
values are left as you gave them:

- **Values nested in a field**, such as a URL inside a list passed as `value`.
- **Fields added after construction**, such as `cnd$endpoint <- url`.
- **The parent condition.** A dataexcept message that quotes its parent is
  redacted, but the parent object itself is not rewritten. Printing the chain
  with rlang, or reading `conditionMessage(cnd$parent)`, shows the parent's own
  text.

All three are redacted when the condition is written to an envelope. If you
log conditions some other way (`print()`, `format()`, `conditionMessage()` on a
parent), review what they carry, or pass the text through
`redact_urls_in_text()` first.

### What is never redacted

- **A bare secret that is not part of a URL.** If you write
  `message = "the key is AKIAIOSFODNN7"`, there is no way to know that string
  is a credential, and it will be logged.
- **`query_execution_error()` embeds the SQL you give it**, including literal
  values. A normalised query is often useless for debugging, so it is not
  rewritten. If your queries carry personal data in literals, pass a
  parameterised statement.
- **Field values generally.** `prediction_error(inputs = ...)` stores the inputs
  you pass. A data frame or matrix is written to an envelope as a description of
  its shape, but a short vector is written as values.

### Reading untrusted envelopes

`envelope_to_condition()` and the validators are designed to be safe on input
from outside the process:

- JSON text nested deeper than the envelope could legitimately need is rejected
  before it is parsed, and a chain of records deeper than `max_depth` (default
  32) is rejected before it is walked. A 100,000-level payload is refused in
  well under a second with a `dataexcept_envelope_error`.
- Nothing in an envelope is evaluated.
- R classes come only from dataexcept's own registry. An envelope's `type` and
  `module` are kept as strings and cannot add arbitrary classes to the
  condition. An envelope that claims a dataexcept type *will* be caught by a
  handler for that type, which is the purpose of the reader: treat a remote
  condition as a claim made by whoever wrote the envelope.

A report of an envelope that crashes R, consumes unbounded time or memory, or
leads dataexcept to disclose something a caller could not reasonably expect is
in scope.
