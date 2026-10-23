# dataexcept roadmap

Updated: 23 October 2026.

The priority is to make structured failures dependable in real R and mixed
R/Python workflows. The Python DataExcept package owns the envelope contract;
the R package follows it and keeps its native condition semantics.

The milestones below are ordered by priority. Unchecked items are planned
work, with scope and release numbers to be agreed as evidence arrives. They
are not promises of a release date. Completed changes belong in [NEWS.md](NEWS.md).

## Current baseline

[dataexcept 0.4.1](https://github.com/DiogoRibeiro7/r-dataexcept/releases/tag/v0.4.1)
is published on GitHub. Development has resumed at `0.4.1.9000`. The first CRAN
submission is confirmed and awaiting review as of the date above; submission
does not mean acceptance. [cran-comments.md](cran-comments.md) records the
candidate, checks and submission evidence.

The package already provides:

- Classed conditions, failure metadata, cause chains, groups and wrapping.
- R/Python envelope reading and writing, schema validation, URL credential
  redaction and parity checks against Python-generated fixtures.
- Localised warning classification for base R, stats, survival and lme4.
- Operation context, failure events, optional OpenTelemetry recording and
  Pino projections, including optional rlang backtraces outside the envelope.
- An installed vignette, generated reference documentation, checks across
  operating systems and R versions, and automated GitHub releases.

## 1. Complete the first CRAN release

- [x] Publish the GitHub `v0.4.1` tag, release notes and source archive.
- [x] Check the submitted archive on Linux and Windows R-devel, including
  external win-builder: zero errors, zero warnings and the expected
  `New submission` NOTE.
- [x] Submit the checked archive and confirm the maintainer email.
- [ ] Address any CRAN review feedback, preserving a record of each candidate
  and its check results if a resubmission is needed.
- [ ] Record acceptance and verify that the published CRAN package installs
  and provides its examples and vignette.
- [ ] Once available on CRAN, update installation instructions and badges.
  Refresh [CHECKLIST.md](CHECKLIST.md), the supported-version table in
  [SECURITY.md](SECURITY.md), and [CRAN readiness](docs/cran-readiness.md) so
  they reflect the released package and completed checks.

**Done when:** CRAN lists the package, its published source corresponds to a
GitHub release, and the installation guidance and release records agree.

## 2. Make the release process repeatable

Future CRAN submissions should follow this order: check the candidate,
publish the matching GitHub release, submit to CRAN, confirm the submission,
then record CRAN's decision.

- [ ] Add a pre-submission check for the published GitHub tag, release asset
  and archive checksum, and document it in [CONTRIBUTING.md](CONTRIBUTING.md)
  and the CRAN readiness guide.
- [ ] Build the candidate once and promote that same checked archive to the
  GitHub release and CRAN. Preserve its SHA-256, source commit, R versions
  and check reports with the release record.
- [ ] Make post-release housekeeping safe to retry when a runner fails or
  dependency downloads stall. Handle an existing development branch or pull
  request, and document use of the local release helper to recover.
- [ ] Include release metadata, supported versions, installation links and
  archive contents in the release checklist.

**Done when:** the release procedure has been exercised with one archive
through validation and publication, and an interrupted housekeeping step can
be completed without recreating the release.

## 3. Prove the API in a downstream package

- [ ] Pilot adoption in **heteroTests or attest**, choosing one concrete
  workflow whose errors would benefit from structured fields and recovery
  metadata.
- [ ] Replace that workflow's error handling, with regression checks for
  class-based handlers, preserved causes and conservative retry decisions.
- [ ] Document a complete mixed R/Python example: a failure crosses a process
  boundary, is caught by class in R, and retains its fields and operation
  context in a log or trace.
- [ ] Turn gaps found during the pilot into small, reproducible issues before
  expanding the public API. Add condition types and warning rules only when
  a real producer and consumer need them.

**Done when:** a downstream project uses dataexcept in a maintained workflow,
its regression checks pass, and the integration is documented well enough
for another package to repeat.

## 4. Strengthen compatibility and robustness

- [ ] Publish a compatibility table connecting R package releases to envelope
  and Pino schema versions and the Python revision used to generate fixtures.
  Keep the existing upstream drift check as an early warning of changes.
- [ ] Extend the existing fixture suite with generated valid and invalid
  payloads, covering wide groups, deep nesting, Unicode, unusual numbers and
  malformed structures. Save discovered failures as regression cases.
- [ ] Benchmark envelope reading, writing and redaction on representative
  payloads. Record reproducible time and allocation baselines before choosing
  optimisations or additional input limits.
- [ ] Extend warning coverage where downstream use exposes gaps, including
  translated templates and values. Each new rule must be tested against the
  function that actually emits the warning.

**Done when:** supported combinations are documented, new edge cases have
regression coverage, and performance decisions have a reproducible baseline.

## 5. Decide readiness for 1.0

A 1.0 release should follow evidence from the preceding milestones. Its
readiness criteria are:

- [ ] Downstream adoption has exercised the public constructors, class
  hierarchy, recovery metadata and envelope round trips.
- [ ] Public API and schema compatibility policies are documented, including
  how deprecations and changes to Python's contract are handled.
- [ ] Supported R versions, dependency requirements and maintenance policy
  are explicit and covered by the release checks.
- [ ] Known correctness and credential-redaction regressions are resolved,
  with no unexplained errors, warnings or notes in release checks.
- [ ] Release, submission and recovery procedures have been exercised and
  the user documentation reflects the stable API.

## Later distribution work

- [ ] Archive a published release with Zenodo and add its DOI to the citation
  metadata.
- [ ] Evaluate an R-universe listing for development builds after the CRAN
  installation path is established.

These are separate from CRAN acceptance and do not block the first release.

## Design decisions still open

- **Producer identity:** should the shared envelope identify its source
  language explicitly, beyond the current `module` convention? Propose any
  schema change upstream and define compatibility before adding it in R.
- **Input budgets:** do measured workloads justify limits on payload bytes
  or total nodes in addition to the existing depth limit? Establish the need,
  defaults and failure behaviour before changing the reader API.

Keep the package focused on representing and exchanging failures. Retry
execution, workflow scheduling and log transport remain application concerns.
Retain minimal hard dependencies and optional observability integrations.

Review this roadmap after CRAN feedback, a release or a downstream pilot.
When an item is selected, give it a concrete issue, scope and acceptance
criteria; check it off only after the result has been verified.
