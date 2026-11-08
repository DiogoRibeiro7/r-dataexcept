# dataexcept 0.4.2: resubmission

## Resubmission

This is a resubmission. dataexcept was first submitted as 0.4.1 on
23 October 2026. In this version I have:

- Replaced the commented-out code in the example for
  `operation_context_from_otel()` with runnable code. The traced part runs
  when the suggested package otelsdk is installed, records the trace in
  memory and checks the result. No example now contains commented-out
  code, and every example runs in well under 5 seconds.
- Updated one test for otelsdk 0.3.0 (5 November 2026), which leaves a span
  that ends without an error at the "unset" status instead of "ok". Without
  this change the tests fail with the current otelsdk.

## Source candidate

- Source commit: `0fc2b4bb048042864fb4aec5d3ea05363f043532`
- Archive: `dataexcept_0.4.2.tar.gz` (114,891 bytes)
- SHA-256: `b092866e2fcd074de27b94aba5ac1e502ae39b598aaf4998c78f78d38e9b8f4c`
- Built with R 4.6.2 on Ubuntu 24.04.5 LTS.
- [Candidate workflow and retained check reports](https://github.com/DiogoRibeiro7/r-dataexcept/actions/runs/42420762837)

The checks below used this exact archive, with its checksum verified before
the Windows checks. Changes to this file are excluded from the source package.

## Test environments and results

Checked on 7 November 2026:

- Ubuntu 24.04.5 LTS, R 4.6.2: `R CMD check --as-cran --no-manual`;
  0 errors, 0 warnings, 1 NOTE.
- Windows Server 2025, R-devel (2026-11-06 r90845 ucrt):
  `R CMD check --as-cran --no-manual`; 0 errors, 0 warnings, 1 NOTE.
- External win-builder, Windows Server 2022, R-devel
  (2026-11-06 r90845 ucrt): full check including PDF and HTML manuals;
  0 errors, 0 warnings, 1 NOTE.

All three checks report only the expected incoming-feasibility NOTE:

    Maintainer: 'Diogo Ribeiro <dfr@esmad.ipp.pt>'
    New submission

On the release branch, CI also passed `R CMD check` on macOS, Windows and
Ubuntu (R-devel, release, oldrel-1 and 4.1), coverage (100%), lint,
formatting, spelling, the envelope schema contract and the documentation
build. The test suite passes with otelsdk 0.2.4 and with otelsdk 0.3.0.

## Package scope

This package provides classed R conditions, structured recovery metadata,
and JSON failure envelopes compatible with the Python DataExcept format.
Python is not required to install or use the R package. Tests and examples
use local fixtures and do not require live external services or credentials.
The only non-base hard dependency is jsonlite, available on CRAN.

## External win-builder result

The exact archive above was uploaded to win-builder's R-devel service on
7 November 2026 at 22:33 UTC, after its checksum was verified again. The
[check report](https://win-builder.r-project.org/p1c3muYoD7mK/00check.log)
and installation report were reviewed and saved locally before their expiry.
The check started at 22:50 UTC and passed installation, examples, tests,
vignette rebuilding, and PDF and HTML manuals. Its only NOTE is
`New submission`.

## Submission status

The exact source archive above, with its checksum verified again, was
submitted through CRAN's submission service on 8 November 2026 at
09:55 UTC (record 361999), with the resubmission notes above as its
comment. The service acknowledged the submission; maintainer email
confirmation is pending. CRAN reviewed the 0.4.1 submission
(record 359950) and asked for the example change above before
resubmission.
