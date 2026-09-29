# Release helper. Runs anywhere R does, including PowerShell on Windows.
#
#   Rscript tools/release.R prepare 0.3.0   # set every version field for 0.3.0
#   Rscript tools/release.R check v0.3.0    # the release workflow's check, run locally
#   Rscript tools/release.R dev             # begin development after a release
#
# `prepare` sets DESCRIPTION, CITATION.cff (version and release date), the
# NEWS.md heading and the pinned install lines in the README and the getting
# started page, then regenerates the help pages and the site's reference.
# `check` is the test .github/workflows/release.yml applies to a tag; it exits
# non-zero if the tag, DESCRIPTION, CITATION.cff and NEWS.md disagree.

dev_heading <- "# dataexcept (development version)"
pinned_files <- c("README.md", "docs/getting-started.md")

fail <- function(...) {
  message("Error: ", ...)
  quit(save = "no", status = 1L)
}

read <- function(path) readLines(path, encoding = "UTF-8", warn = FALSE)

write <- function(lines, path) {
  # Evaluate the lines before the file is opened: opening truncates it, and
  # the lines may have been read from the same file.
  force(lines)
  con <- file(path, open = "wb")
  on.exit(close(con))
  writeLines(enc2utf8(lines), con, sep = "\n", useBytes = TRUE)
}

field <- function(lines, pattern) {
  hit <- grep(pattern, lines, value = TRUE)
  if (length(hit) != 1L) fail("expected exactly one line matching ", pattern)
  trimws(gsub('"', "", sub(pattern, "", hit)))
}

versions <- function() {
  list(
    description = field(read("DESCRIPTION"), "^Version:"),
    citation = field(read("CITATION.cff"), "^version:"),
    news = read("NEWS.md")
  )
}

check_release_version <- function(version) {
  if (!grepl("^[0-9]+\\.[0-9]+\\.[0-9]+$", version)) {
    fail("a release version has three parts, such as 0.3.0; got '", version, "'")
  }
  version
}

prepare <- function(version) {
  check_release_version(version)
  news <- read("NEWS.md")
  dev <- which(news == dev_heading)
  if (length(dev) != 1L) fail("NEWS.md has no '", dev_heading, "' heading to release")
  following <- news[-seq_len(dev)]
  next_heading <- which(grepl("^# ", following))[1L]
  body <- if (is.na(next_heading)) following else following[seq_len(next_heading - 1L)]
  if (!any(nzchar(trimws(body)))) fail("the development section of NEWS.md is empty")
  news[dev] <- paste("# dataexcept", version)
  write(news, "NEWS.md")

  description <- read("DESCRIPTION")
  description <- sub("^Version:.*$", paste("Version:", version), description)
  write(description, "DESCRIPTION")

  citation <- read("CITATION.cff")
  citation <- sub("^version:.*$", paste("version:", version), citation)
  citation <- sub(
    "^date-released:.*$",
    sprintf('date-released: "%s"', format(Sys.Date(), "%Y-%m-%d")),
    citation
  )
  write(citation, "CITATION.cff")

  for (path in pinned_files) {
    lines <- read(path)
    lines <- gsub("r-dataexcept@v[0-9]+\\.[0-9]+\\.[0-9]+", paste0("r-dataexcept@v", version), lines)
    write(lines, path)
  }

  regenerate()
  check(paste0("v", version))
  message("\nNext: commit, open a pull request, merge it, then tag the merge commit:")
  message("  git checkout main")
  message("  git pull")
  message("  Rscript tools/release.R check v", version)
  message("  git tag v", version)
  message("  git push origin v", version)
}

check <- function(tag) {
  version <- check_release_version(sub("^v", "", tag))
  found <- versions()
  problems <- character()
  if (!identical(found$description, version)) {
    problems <- c(problems, sprintf("DESCRIPTION has version %s", found$description))
  }
  if (!identical(found$citation, version)) {
    problems <- c(problems, sprintf("CITATION.cff has version %s", found$citation))
  }
  if (!any(found$news == paste("# dataexcept", version))) {
    problems <- c(problems, sprintf("NEWS.md has no '# dataexcept %s' section", version))
  }
  if (length(problems) > 0L) {
    if (grepl("\\.9000$", found$description)) {
      problems <- c(problems, paste0(
        "DESCRIPTION is still a development version, so the tag was probably pushed before ",
        "the release pull request was merged. Delete the tag (git push origin :refs/tags/v",
        version, " and git tag -d v", version, "), merge the release pull request, ",
        "then tag its merge commit."
      ))
    }
    fail("tag v", version, " does not match the package:\n  ", paste(problems, collapse = "\n  "))
  }
  message("v", version, ": DESCRIPTION, CITATION.cff and NEWS.md agree.")
}

dev <- function() {
  found <- versions()
  if (grepl("\\.9000$", found$description)) {
    fail("DESCRIPTION is already a development version (", found$description, ")")
  }
  version <- check_release_version(found$description)
  description <- read("DESCRIPTION")
  write(sub("^Version:.*$", paste0("Version: ", version, ".9000"), description), "DESCRIPTION")
  news <- read("NEWS.md")
  if (!identical(news[1L], dev_heading)) {
    write(c(dev_heading, "", news), "NEWS.md")
  }
  regenerate()
  message("DESCRIPTION is now ", version, ".9000 and NEWS.md has a development heading.")
}

regenerate <- function() {
  if (!requireNamespace("roxygen2", quietly = TRUE)) {
    fail("roxygen2 is needed to regenerate the help pages: install.packages(\"roxygen2\")")
  }
  roxygen2::roxygenise()
  status <- system2(file.path(R.home("bin"), "Rscript"), "tools/build-docs.R")
  if (!identical(status, 0L)) fail("tools/build-docs.R failed")
}

if (!file.exists("DESCRIPTION") || !file.exists("tools/release.R")) {
  fail("run this from the root of the repository")
}
args <- commandArgs(trailingOnly = TRUE)
command <- if (length(args) > 0L) args[[1L]] else ""
switch(command,
  prepare = if (length(args) == 2L) prepare(args[[2L]]) else fail("usage: Rscript tools/release.R prepare 0.3.0"),
  check = if (length(args) == 2L) check(args[[2L]]) else fail("usage: Rscript tools/release.R check v0.3.0"),
  dev = dev(),
  fail("usage: Rscript tools/release.R prepare <version> | check <tag> | dev")
)
