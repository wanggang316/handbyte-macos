#!/usr/bin/env bash
# Validate the checked-out merge commit before creating an annotated release tag.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/release-lib.sh"
BRANCH=${1:?release branch is required}
SHA=${2:?merge commit is required}
if [[ ! "$BRANCH" =~ ^release/v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid release branch: $BRANCH" >&2
  exit 1
fi
TAG=${BRANCH#release/}
VERSION=${TAG#v}
if [[ "$(git rev-parse HEAD)" != "$SHA" ]]; then
  echo "HEAD does not match the merge commit: $SHA" >&2
  exit 1
fi
if [[ "$(release_marketing_version project.yml)" != "$VERSION" ]]; then
  echo "Tag version does not match project.yml: $VERSION" >&2
  exit 1
fi
release_changelog_section CHANGELOG.md "$VERSION" >/dev/null
# Prefer the peeled commit for annotated tags; accept lightweight tags on retries.
EXISTING=$(git ls-remote origin "refs/tags/$TAG" "refs/tags/$TAG^{}" | tail -1 | awk '{print $1}')
if [[ -n "$EXISTING" ]]; then
  if [[ "$EXISTING" != "$SHA" ]]; then
    echo "Tag $TAG already points at $EXISTING, not $SHA" >&2
    exit 1
  fi
  echo "Tag $TAG already points at the merge commit"
  exit 0
fi
git tag -a "$TAG" -m "Handbyte $VERSION" "$SHA"
git push origin "refs/tags/$TAG"
