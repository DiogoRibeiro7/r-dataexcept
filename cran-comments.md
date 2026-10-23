# dataexcept 0.4.1: first CRAN submission

## Source candidate

- Source commit: `1462103629e8ac63db3f85057cdf96930ddada8d`
- Archive: `dataexcept_0.4.1.tar.gz` (114,380 bytes)
- SHA-256: `3c771d93121c15855896d3a2a864bb9a26f90ba29169e4a679d892e88e93aeff`
- Built with R 4.6.1 on Ubuntu 24.04.5 LTS.
- [Candidate workflow and retained check reports](https://github.com/DiogoRibeiro7/r-dataexcept/actions/runs/39924803263)

The checks below used this exact archive, with its checksum verified before
the Windows checks. Changes to this file are excluded from the source package.

## Test environments and results

Checked on 23 October 2026:

- Ubuntu 24.04.5 LTS, R 4.6.1: `R CMD check --as-cran --no-manual`;
  0 errors, 0 warnings, 1 NOTE.
- Windows Server 2022, R-devel (2026-10-22 r90748 ucrt):
  `R CMD check --as-cran --no-manual`; 0 errors, 0 warnings, 1 NOTE.
- Windows 11, R 4.5.1: full `R CMD check --as-cran`, including PDF and
  HTML manuals and rebuilding the vignette; 0 errors, 0 warnings, 2 NOTEs.

All three checks report the expected incoming-feasibility NOTE:

    Maintainer: 'Diogo Ribeiro <dfr@esmad.ipp.pt>'
    New submission

The local Windows check additionally reports `unable to verify current time`
because the external time check was unavailable. It reports no future-dated
files. This NOTE did not occur in the CI checks.

The local installed-package suite passed all 1,432 expectations without
warnings or skips. Coverage was 100%; lint, formatting, spelling and URL
checks passed.

## Package scope

This package provides classed R conditions, structured recovery metadata,
and JSON failure envelopes compatible with the Python DataExcept format.
Python is not required to install or use the R package. Tests and examples
use local fixtures and do not require live external services or credentials.
The only non-base hard dependency is jsonlite, available on CRAN.

## External win-builder result: pending

The exact archive above was uploaded to win-builder's R-devel service on
23 October 2026. The upload receipt records the same filename and 114,380-byte
size. The result is sent to `dfr@esmad.ipp.pt` and has not yet been reviewed.

Complete this section from the actual report before CRAN submission, as
required by the repository's [candidate verification procedure](docs/cran-readiness.md).
The package has not yet been submitted to CRAN.
