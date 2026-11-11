---
name: release
description: Cut a Handbyte macOS app release. Write the release notes into CHANGELOG.md, pick the Semantic Versioning bump from them, bump project.yml, open a release PR; merging it starts CI to tag, build, publish, and distribute the release. Use when shipping a new app build.
---

# release: Cut a Handbyte app release

An app release is **a release PR** from `release/vX.Y.Z` to `main`.
Merging it starts `release-merge.yml`, which validates and tags the merged
commit, calls `release.yml` to build, sign, notarize and create a draft,
verifies all four assets, and publishes the release. It then calls
`publish.yml` to deploy this repository's website and appcast to GitHub Pages
and update the Homebrew cask. No Go CLI checkout is required.
**Merging the release PR ships the release.**

The contract CI enforces:

> tag `vX.Y.Z` ⇔ `MARKETING_VERSION: "X.Y.Z"` in `project.yml` ⇔
> `CHANGELOG.md` has `## [X.Y.Z] - YYYY-MM-DD` with entries.

CI publishes that CHANGELOG section verbatim as the GitHub Release body and
as the "What's New" notes inside the app, so it is prose for users.

Don't use this for fixing the release pipeline itself (no version bump).
Never push to `main` directly; every release change goes through a PR.

## Process

Run steps 1–6 without stopping: they write only to a release branch and an
open PR. After the user approves the merge in step 7, run steps 7–8 without
stopping, up to the published release.

### 1. Pre-flight

```bash
git status --porcelain                       # empty
git fetch origin --tags
scripts/bump-version.sh --print        # current version, next build, next patch / minor / major
```

Stop if the tree is dirty, a release PR is already open
(`gh pr list --search 'head:release/v'`), or the target tag exists.

### 2. Write the release notes

`[Unreleased]` in `CHANGELOG.md` is input, not output. Cross-check it
against the commits since the last app tag,
`git log --no-merges --pretty='%h %s' "$(git describe --tags --abbrev=0 --match 'v*' origin/main)..origin/main"`,
and keep only what a user can perceive.

- One entry per user-visible surface, three lines at most: a bold lead-in,
  then at most two sentences. A release reads as 3–8 entries.
- Lead with what the user gets or the symptom that is gone. Leave out
  refactors, CI, tests and dependency bumps, except a minimum-OS change and
  anything removed or breaking.
- No commit prefixes, issue numbers, hashes or type names.

Categories follow Keep a Changelog: `Added`, `Changed`, `Deprecated`,
`Removed`, `Fixed`, `Security`.

### 3. Choose the version

| The release contains | Bump |
|---|---|
| Anything under `Removed`, or a `Changed` entry that breaks settings, the catalog or how a cleanup behaves | **major**, but **minor** while the version is `0.y.z` |
| Anything under `Added`, `Changed`, or `Deprecated` | **minor** |
| Only `Fixed` and `Security` | **patch** |

Take the number from `bump-version.sh --print`. Never bump to `1.0.0` on
your own.

### 4. Branch, edit the changelog, bump

```bash
git switch --no-track -c release/vX.Y.Z origin/main
```

Put the notes under `## [X.Y.Z] - YYYY-MM-DD` (today), drop empty
categories, and reseed an empty `## [Unreleased]` with all six headers. Then:

```bash
make bump-version VERSION=X.Y.Z     # BUILD=N overrides the build number (rare)
make test-scripts
```

The script owns `project.yml`: it validates the version, takes the next
`YYYYMMDDNNN` build number above the published appcast, and rewrites the two
settings. Never hand-edit them.

### 5. Commit and push

```bash
git add CHANGELOG.md project.yml
git commit -m "Release Handbyte X.Y.Z"
git push -u origin release/vX.Y.Z
```

### 6. Open the release PR

```bash
gh pr create --base main --head release/vX.Y.Z \
  --title "Release Handbyte X.Y.Z" --body-file - <<'EOT'
Release X.Y.Z (build N): <bump> because <row of step 3>.

<the new CHANGELOG section, verbatim>

Merging this PR starts CI to tag, build, publish, and distribute the release.
EOT
```

Not a draft. Wait for `ci`: `gh pr checks <PR> --watch`.

### 7. Merge, the only gate

Report the PR URL, the version and the check result, then wait for the user
to approve the merge.

```bash
gh pr merge <PR> --rebase
git push origin --delete release/vX.Y.Z
```

### 8. Wait for automatic publication and distribution

Find the `release-merge.yml` run associated with this merged PR. A closed-PR
event can report the PR head SHA in the run metadata. Verify that the
annotated release tag points at the PR merge commit:

```bash
gh pr view <PR> --json mergeCommit --jq .mergeCommit.oid
gh run list --workflow=release-merge.yml --event=pull_request --limit 20 \
  --json databaseId,headSha,status,conclusion,url
git ls-remote origin 'refs/tags/vX.Y.Z^{}'
gh run watch <RUN_ID> --exit-status
gh release view vX.Y.Z --json isDraft,assets,url
```

Confirm the release is public and carries `Handbyte-X.Y.Z.dmg`,
`Handbyte-X.Y.Z.dmg.sha256`, `Handbyte.dmg`, and `appcast.xml`.
Confirm both distribution jobs passed, the website appcast at
<https://handbyte.gumpw.com/appcast.xml> carries the new build, and
`Casks/handbyte.rb` in `wanggang316/homebrew-tap` carries the new version.
Do not manually tag or publish during the normal flow. CI calls the reusable
workflows directly because `GITHUB_TOKEN` does not trigger downstream events.

## Recovery

Roll forward; never force-push `main`. Deleting a pushed tag needs explicit
user approval.

| Symptom | Fix |
|---|---|
| Merge validation fails | Fix the version or notes in a new release PR. Never move an existing release tag. |
| Build, notarization, or distribution fails | Inspect `gh run view <RUN_ID> --log-failed`, fix the cause, then rerun failed jobs. An existing tag is accepted only at the same merge commit. |
| Tap push returns 403 | Repair `HOMEBREW_TAP_TOKEN` access: Contents read/write on `wanggang316/homebrew-tap`, then rerun the failed job. |
| Website deployment fails | Check this repository's Pages configuration (GitHub Actions source), domain, and `github-pages` environment. Rerun the website job or dispatch `website.yml`. |
| Manual fallback is needed | Push the annotated tag on the merged commit, or dispatch `release.yml` with an existing tag. Verify the four assets, then publish the draft with a user token to trigger `publish.yml`. |
| Published release is broken | Mark its heading `[YANKED]` with a one-line reason and ship the fix as the next version. |

The website and feed are deployed from this repository by `website.yml`.
Its build reads the latest stable appcast from this repository's Release,
then uploads it with `site/` as a Pages artifact. Keep the existing domain
and feed path so installed clients continue to receive updates.

When a workflow fix lands after a release, dispatch `publish.yml` on `main`
with the published tag. Rerunning an old release run uses its old workflow
revision and cannot pick up the fix. Website and Homebrew results must both
pass before reporting the release as complete.
