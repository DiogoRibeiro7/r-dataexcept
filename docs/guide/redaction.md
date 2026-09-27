# Redaction

Failures are raised with credentials in hand: a database URL carrying a
password, an API endpoint with a token in its query string, a webhook URL whose
path is the secret. Without redaction, the failure writes the credential into
whatever log receives it.

dataexcept removes credentials from URLs at two points:

1. **At construction.** The message and every character field of a dataexcept
   condition are redacted when it is created, keeping the path.
2. **On export.** Everything written into an envelope is redacted again,
   this time removing the path too, as the Python package does.

```r
err <- database_connection_error("postgresql://analyst:s3cret@db.internal:5432/sales")
err$db_url
#> [1] "postgresql://***:***@db.internal:5432/sales"
```

## The rules

`redact_url()` applies them to a single URL, and `redact_urls_in_text()` to
every URL found in free text.

- **Kept:** scheme, host and port. They are what makes an error actionable.
- **Replaced:** userinfo (`user:password@`) becomes `***:***@`.
- **Replaced:** the values of credential-bearing query and fragment parameters
  become `***`.
- **Optionally replaced:** the path, with `keep_path = FALSE`, for URLs whose
  path is itself the secret.

```r
redact_url("https://api.example.com/v1/orders?page=2&api_key=abc123")
#> [1] "https://api.example.com/v1/orders?page=2&api_key=***"

redact_url("https://hooks.example.com/services/T000/B000/XXXX", keep_path = FALSE)
#> [1] "https://hooks.example.com/***"

redact_urls_in_text("GET https://user:pw@example.com/data failed: timeout")
#> [1] "GET https://***:***@example.com/data failed: timeout"
```

A URL that carries no credential is returned exactly as given.

## Which parameters are credentials

A parameter name is split into tokens, on separators and at camelCase
boundaries, and matched token by token against a fixed list: `api_key`,
`accessToken`, `X-Amz-Signature`, `password`, `sig`, `jwt` and similar all
match. Substring matching is deliberately not used: it would redact `keyword`,
`monkey` and `authors` while still missing `passphrase`.

`code`, `state`, `nonce` and `client_id` are not on the list. An OAuth
authorisation code is a secret, but a parameter called `code` is far more often
a country code or a status, and redacting those would remove more debugging
information than it protects.

## Same output as Python

The rules are a port of the Python package's `dataexcept.redaction` module,
including its tokenisation, its handling of text around a URL (a trailing full
stop or colon stays outside the URL), and how it rebuilds a query string after
redacting it. The test suite runs a set of awkward inputs through both
implementations and requires the same output character for character.

## Limits

Redaction finds credentials in URLs. A bare secret pasted into free text, with
no URL around it, cannot be recognised and is not removed. Keep secrets out of
messages you write yourself.
