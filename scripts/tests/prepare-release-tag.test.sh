#!/usr/bin/env bash
# Exercise release tag validation and retry behavior against a local remote.
set -euo pipefail
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/prepare-release-tag.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git init -q --bare "$TMP/remote.git"
git init -q "$TMP/work"
cd "$TMP/work"
git config user.name "Release test"
git config user.email "release@example.com"
git remote add origin "$TMP/remote.git"
printf 'MARKETING_VERSION: "1.2.3"\n' > project.yml
printf '## [1.2.3] - 2026-11-10\n\n- A release.\n' > CHANGELOG.md
git add project.yml CHANGELOG.md
git commit -qm 'Prepare release'
SHA=$(git rev-parse HEAD)

reject() {
  if bash "$SCRIPT" "$1" "$2" >/dev/null 2>&1; then
    echo "FAIL: accepted $1 at $2" >&2
    exit 1
  fi
}
reject release/v1.2.4 "$SHA"
reject release/v1.2.3-beta "$SHA"
reject feature/v1.2.3 "$SHA"
reject release/v1.2.3 deadbeef
if git ls-remote --tags origin | grep -q .; then
  echo 'FAIL: invalid input pushed a tag' >&2
  exit 1
fi
bash "$SCRIPT" release/v1.2.3 "$SHA"
TAG_SHA=$(git --git-dir="$TMP/remote.git" rev-parse 'v1.2.3^{}')
[[ "$TAG_SHA" == "$SHA" ]]
[[ $(git --git-dir="$TMP/remote.git" cat-file -t v1.2.3) == tag ]]
BEFORE=$(git --git-dir="$TMP/remote.git" rev-parse v1.2.3)
bash "$SCRIPT" release/v1.2.3 "$SHA"
[[ $(git --git-dir="$TMP/remote.git" rev-parse v1.2.3) == "$BEFORE" ]]
git commit -qm 'Another commit' --allow-empty
reject release/v1.2.3 "$(git rev-parse HEAD)"
[[ $(git --git-dir="$TMP/remote.git" rev-parse v1.2.3) == "$BEFORE" ]]
printf 'MARKETING_VERSION: "1.2.4"\n' > project.yml
printf '## [1.2.4] - 2026-11-10\n' > CHANGELOG.md
git add project.yml CHANGELOG.md
git commit -qm 'Empty notes'
reject release/v1.2.4 "$(git rev-parse HEAD)"
echo 'prepare-release-tag tests passed'
