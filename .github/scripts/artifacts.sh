#!/bin/bash

# Generates contract artifacts for the given tag (or `main` branch) and creates a new tagged commit with the newly
# generated artifacts.

set -o nounset
set -o pipefail
set -o errexit

main_branch="main"

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <refs/tags/tag-name or 'refs/heads/$main_branch'>"
  exit 1
fi

target_ref="$1"
if [[ "$target_ref" != "refs/heads/$main_branch" ]] && ! [[ "$target_ref" =~ ^refs/tags/.* ]]; then
  echo "Invalid git ref $target_ref" >&2
  exit 1
fi
target_ref_short="${target_ref#refs/*/}"

git_username="GitHub Actions"
git_useremail="GitHub-Actions@cow.fi"

if ! git config --get user.name &>/dev/null; then
  git config user.name "$git_username"
  git config user.email "$git_useremail"
fi

artifacts_tag="$target_ref_short-artifacts"

git fetch origin "$target_ref"
git checkout --detach "$target_ref"

forge build -o artifacts

git add artifacts
git commit -m "Add artifacts for $target_ref"
git tag -m "Artifacts for $target_ref" --end-of-options "$artifacts_tag"

if [ "$target_ref" = "refs/heads/$main_branch" ]; then
  # --force is used to overwrite the remote tag, if it exists.
  # This is done to keep the artifacts always consistent with the main branch, history is not important.
  git push --force origin "refs/tags/$artifacts_tag"
else
  # Check if artifact branch already exists. Don't delete old tagged artifacts to make sure that deleting tag history is
  # intentional.
  if git ls-remote --exit-code origin "refs/tags/$artifacts_tag" >/dev/null; then
    echo "Error: the artifacts tag $artifacts_tag already exists on remote." >&2
    echo "Existing artifacts will be preserved." >&2
    echo "If deleting existing artifacts is intended, please delete both remote tags $target_ref and refs/tags/$artifacts_tag and then push again the same tag $target_ref to remote." >&2
    exit 1
  fi

  git push origin "refs/tags/$artifacts_tag"
fi
