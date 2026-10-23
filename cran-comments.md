# dataexcept 0.4.1: first CRAN submission

## Source candidate

- Source commit: `2545586d9fb8b714a378afbe6471ea8345f80dc0`
- Archive: `dataexcept_0.4.1.tar.gz` (114,414 bytes)
- SHA-256: `7796594d504fcd254a6835e944ca0f056553583e0d11633d9a35408f9c365846`
- Built with R 4.6.1 on Ubuntu 24.04.5 LTS.
- [Candidate workflow and retained check reports](https://github.com/DiogoRibeiro7/r-dataexcept/actions/runs/39930938939)

The checks below used this exact archive, with its checksum verified before
the Windows checks. Changes to this file are excluded from the source package.

## Test environments and results

Checked on 23 October 2026:

- Ubuntu 24.04.5 LTS, R 4.6.1: `R CMD check --as-cran --no-manual`;
  0 errors, 0 warnings, 1 NOTE.
- Windows Server 2022, R-devel (2026-10-22 r90748 ucrt):
  `R CMD check --as-cran --no-manual`; 0 errors, 0 warnings, 1 NOTE.
- External win-builder, Windows Server 2022, R-devel
  (2026-10-22 r90748 ucrt): full check including PDF and HTML manuals;
  0 errors, 0 warnings, 1 NOTE.

All three checks report only the expected incoming-feasibility NOTE:

    Maintainer: 'Diogo Ribeiro <dfr@esmad.ipp.pt>'
    New submission

The package suite passed all 1,432 expectations. Coverage was 100%; lint,
formatting, spelling and URL checks passed. Spelling and URL checks were
also run on the extracted final source archive, including its README links.

## Package scope

This package provides classed R conditions, structured recovery metadata,
and JSON failure envelopes compatible with the Python DataExcept format.
Python is not required to install or use the R package. Tests and examples
use local fixtures and do not require live external services or credentials.
The only non-base hard dependency is jsonlite, available on CRAN.

## External win-builder result

The exact archive above was uploaded to win-builder's R-devel service on
23 October 2026 at 09:23 UTC. The upload receipt records the same filename
and 114,414-byte size. The [check report](https://win-builder.r-project.org/E6w1FL9U5T2p/00check.log)
and installation report were reviewed and saved locally before their expiry.
The check started at 09:35 UTC and passed installation, examples, tests,
vignette rebuilding, and PDF and HTML manuals. Its only NOTE is
`New submission`; no invalid file URIs remain.

## Submission status

The exact source archive above was uploaded and its submission requested
through CRAN's web form on 23 October 2026 at 09:41 UTC (record 359950).
CRAN acknowledged the request and reported sending a confirmation email
to `dfr@esmad.ipp.pt`. Maintainer email confirmation is still required before
CRAN review; the package has not yet been accepted or published on CRAN.
