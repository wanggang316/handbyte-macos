# Handbyte for macOS

Handbyte.app is a native SwiftUI app that reviews caches and build output on a
Mac before cleanup. It groups candidates by application or project, explains
the rebuild cost, and checks eligibility again before each action. Native
macOS Trash is the default.

The app applies the same cleanup rules as the
[`handbyte` CLI](https://github.com/wanggang316/handbyte). The two are separate
implementations; [`SYNC.md`](SYNC.md) records how they stay aligned.

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
make sync-check     # shared catalog matches the CLI (HANDBYTE_CLI_SRC=../handbyte to use a checkout)
make test-scripts   # tests for the release scripts
make icon           # redraw the app icon set from scripts/render-app-icon.swift
```

`scripts/parity.sh` compares the `hbscan` scanner with the CLI's `--scan-only`
output on this machine; it is a manual tool, not a CI gate.

## Release

A release is a release PR, then a tag push. The runbook is
[`.claude/skills/release/SKILL.md`](.claude/skills/release/SKILL.md).

1. Write the release notes into [`CHANGELOG.md`](CHANGELOG.md) and run
   `make bump-version VERSION=X.Y.Z`, which updates `project.yml`.
2. Merge the release PR, then tag the merged commit `vX.Y.Z`.
3. `release.yml` signs, notarizes, builds the DMG and the Sparkle appcast, and
   opens a draft GitHub Release.
4. Publish the draft. `publish.yml` then commits the appcast to `docs/` of
   [wanggang316/handbyte](https://github.com/wanggang316/handbyte), which
   GitHub Pages serves at <https://handbyte.gumpw.com/appcast.xml>, and updates
   the Homebrew cask in `wanggang316/homebrew-tap`.

The release workflows read these repository secrets:
`DEVELOPER_ID_CERT_P12_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`, `AC_API_KEY_ID`,
`AC_API_ISSUER_ID`, `AC_API_KEY_P8`, `SPARKLE_PRIVATE_KEY` and `PUBLISH_TOKEN`.
The header of each workflow file says how to obtain them.

## License

[MIT](LICENSE)
