#!/usr/bin/env bash
# Commit the working tree to a new branch, push it, start the checks on it and
# open a pull request into main. Used by the prepare-release and release
# workflows, which set GH_TOKEN, COMMIT_NAME and COMMIT_EMAIL.
#
#   bash tools/open-release-pr.sh <branch> <commit message> <title> <body file>
#
# A pull request opened with a workflow's own token does not start other
# workflows, so the checks are started here, on the branch; their results show
# on the pull request. Opening the pull request needs "Allow GitHub Actions to
# create and approve pull requests" in the repository's Settings > Actions >
# General. Without it, the branch is still pushed and the run's summary links
# to the page that opens the pull request.
set -euo pipefail

branch="$1"
message="$2"
title="$3"
body="$4"

git config user.name "$COMMIT_NAME"
git config user.email "$COMMIT_EMAIL"
git switch -c "$branch"
git commit -am "$message"
git push origin "$branch"

for workflow in R-CMD-check.yml lint.yml test-coverage.yml envelope-contract.yml docs.yml; do
  gh workflow run "$workflow" --ref "$branch"
done

compare="https://github.com/$GITHUB_REPOSITORY/compare/main...$branch"
if url="$(gh pr create --base main --head "$branch" --title "$title" --body-file "$body")"; then
  echo "Opened $url" >> "$GITHUB_STEP_SUMMARY"
else
  echo "::warning::Could not open the pull request. Open it at $compare"
  echo "Pushed \`$branch\`. Open the pull request at $compare" >> "$GITHUB_STEP_SUMMARY"
fi
