# Handbyte for macOS

Handbyte.app is a native SwiftUI app that reviews caches and build output on a
Mac before cleanup. It groups candidates by application or project, explains
the rebuild cost, and checks eligibility again before each action. Regenerable files are removed directly by default; other files use macOS
Trash. "Always use the Trash" applies the Trash to all cleanup items.

The macOS app is maintained and released independently. Its rule catalog,
fixtures, website, and update feed are owned by this repository. The Go CLI
is an optional companion; [`SYNC.md`](SYNC.md) records comparison notes.

## Install

Requires macOS 14 or later. The app is signed with a Developer ID, notarized,
and updates itself with Sparkle.

- Download the DMG from [handbyte.gumpw.com](https://handbyte.gumpw.com) or
  from the [releases](https://github.com/wanggang316/handbyte-macos/releases),
  then drag Handbyte to Applications.
- Or with Homebrew: `brew install --cask wanggang316/tap/handbyte`.

The app keeps its settings in `~/Library/Application Support/Handbyte/`.

## Development

Requires Xcode 26 and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```sh
make build          # swift build of the HandbyteCore and HandbyteUI packages
make test           # swift test
make generate       # xcodegen: writes Handbyte.xcodeproj from project.yml
make app            # unsigned Debug build of Handbyte.app
make sync-check     # optional local CLI comparison (requires HANDBYTE_CLI_SRC)
make test-scripts   # tests for the release scripts
make icon           # redraw the app icon set from scripts/render-app-icon.swift
```

`scripts/parity.sh` compares the `hbscan` scanner with the CLI's `--scan-only`
output on this machine; it is a manual tool, not a CI gate.

## Release

Merging a release PR publishes the release. The runbook is
[`.claude/skills/release/SKILL.md`](.claude/skills/release/SKILL.md).

1. Write the release notes into [`CHANGELOG.md`](CHANGELOG.md) and run
   `make bump-version VERSION=X.Y.Z`, which updates `project.yml`.
2. Open a PR from `release/vX.Y.Z` to `main`. After approval, merge it.
3. `release-merge.yml` verifies the merged commit and creates the annotated
   tag. It calls `release.yml` to sign, notarize, and build the DMG and
   Sparkle appcast, then checks the assets and publishes the GitHub Release.
4. It calls `publish.yml` to deploy the website and appcast from this
   repository to GitHub Pages and update the Homebrew cask. The two jobs run
   independently. The feed stays at <https://handbyte.gumpw.com/appcast.xml>
   so installed clients can continue to update.

Retry failed jobs in `release-merge` after a transient failure. Manual tag
pushes and workflow dispatch remain available: they create a draft release,
which must be published separately to trigger distribution.

The release workflows read these repository secrets:
`DEVELOPER_ID_CERT_P12_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`, `AC_API_KEY_ID`,
`AC_API_ISSUER_ID`, `AC_API_KEY_P8`, `SPARKLE_PRIVATE_KEY` and `HOMEBREW_TAP_TOKEN`.
The header of each workflow file says how to obtain them.
`HOMEBREW_TAP_TOKEN` needs Contents read/write access only to
`wanggang316/homebrew-tap`. Website deployment uses this repository's
`GITHUB_TOKEN` with Pages and OIDC permissions.

## Website and update feed

`site/` contains the macOS website. `website.yml` builds it with the latest
stable release's signed `appcast.xml` and deploys a Pages artifact. It runs
when website files change, during publication, or through manual dispatch.
No workflow writes to the Go CLI repository.

The Pages site uses **GitHub Actions** as its source and owns the custom
domain `handbyte.gumpw.com`. Keep the domain and `/appcast.xml` path stable:
versions 0.1.0 and 0.2.0 already use them. The release feed is copied without
modification from this repository's GitHub Release.

The historical `/install.sh` endpoint remains available for existing Go CLI
installation commands. It is a compatibility file, excluded from macOS
builds and releases. The website offers the macOS DMG and Homebrew cask.

To preview the website with an existing release feed:

```sh
python3 scripts/build-site.py --tag v0.2.0 --appcast /tmp/appcast.xml --output /tmp/handbyte-site
python3 -m http.server 8080 --directory /tmp/handbyte-site
```

## License

[MIT](LICENSE)
