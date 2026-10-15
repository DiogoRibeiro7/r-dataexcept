# CRAN candidate verification

The package already runs R CMD check on Linux, macOS and Windows in CI.
Before submitting a release to CRAN, also test the **exact source tarball**
against Windows R-devel using win-builder.

## Prepare a candidate

1. For a real release, prepare and review a three-part version (for example,
   `0.4.0`) using the existing release procedure.
2. Open **Actions > CRAN candidate > Run workflow** on the candidate branch.
3. Confirm that the workflow completed without warnings or errors.
4. Download the `cran-candidate-<version>` artifact. It contains the checked
   `dataexcept_<version>.tar.gz` and a SHA-256 checksum.
5. Verify the checksum locally before forwarding the tarball:

   ```bash
   sha256sum -c dataexcept_<version>.tar.gz.sha256
   ```

   On Windows PowerShell, use
   `Get-FileHash dataexcept_<version>.tar.gz -Algorithm SHA256` and compare
   the result with the accompanying checksum file.

The workflow also verifies the same source archive and SHA-256 checksum on
Windows R-devel, then runs `R CMD check --as-cran` there. Both checks must pass
for the manual workflow to succeed. This is an additional CI check, not an
external win-builder result.

The workflow can run against a development version for early diagnostics;
a `.9000` development build is **not** the final release candidate.

The manual workflow retains the Linux and Windows R-devel check directories
as separate diagnostic artifacts, including their check logs when generated.
Review both alongside the source tarball and checksum. A missing diagnostic
artifact does not count as a successful check.

## Windows R-devel

Upload **the extracted `.tar.gz`**, not the downloaded GitHub artifact ZIP,
to [win-builder](https://win-builder.r-project.org/upload.aspx).
Use the R-devel test and review the report sent by win-builder. Save the
date, version, checksum and any diagnostics in `cran-comments.md`.

A successful Windows-release CI job is useful, but is not a substitute for
the external Windows R-devel check. This workflow does not upload packages to
win-builder, publish releases or submit anything to CRAN.

## Submission record

The repository includes a draft `cran-comments.md` with results explicitly
marked as unverified. Complete it for the actual release candidate. Record:
- the source version, SHA-256 checksum and Git commit;
- the operating systems and R versions checked by CI;
- the date and outcome of win-builder R-devel;
- any remaining notes for CRAN reviewers.

`cran-comments.md` is excluded from the built package by `.Rbuildignore`.
Do not record a check as successful until the actual report has been reviewed.
