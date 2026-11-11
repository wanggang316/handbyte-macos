# Optional CLI comparison

The macOS app owns its rule catalog and fixtures. Build, test, release, and
website deployment run from this repository without the Go CLI repository
or an installed Go CLI. Edit the local files and validate them with
`make test`.

| Local path | Content |
|---|---|
| `Sources/HandbyteCore/Resources/catalog/` | Cleanup, storage, app matching, and system cleanup rules bundled with the app. |
| `Tests/HandbyteCoreTests/Conformance/` | Regression cases executed by `swift test`. |

The Go CLI is an optional companion. For a deliberate comparison, point
`HANDBYTE_CLI_SRC` at a local checkout and run `make sync-check`.
This command reports differences without downloading or overwriting files.
`make parity` is a separate manual scanner comparison. Neither command is a
CI or release gate, and differences do not require changes in the CLI first.

The table below records the previous comparison with the CLI. Its CLI
column is a historical reference, not a claim about the current upstream
version. Journal compatibility lets existing app and CLI history remain
readable without requiring the CLI to be installed.

States:

- **Pending**: planned on this side, not implemented yet.
- **Implemented**: present on this side with the same scope as the other side.
- **Intentional difference**: present on both sides but behaving differently on
  purpose, or deliberately absent on one side; the note says why.
- **Not applicable**: the rule cannot exist on this side.

Any state other than Implemented on both sides needs a note. Add a row when a
rule is added to either side; remove the row when it is removed from both.

| Rule id | CLI | App | Note |
|---|---|---|---|
| `xcode-derived` | Implemented | Implemented | |
| `xcode-devicesupport` | Implemented | Implemented | |
| `xcode-archives` | Implemented | Implemented | |
| `coresim-cache` | Implemented | Implemented | |
| `go-build` | Implemented | Implemented | |
| `go-mod-cache` | Implemented | Implemented | |
| `cargo-registry` | Implemented | Implemented | |
| `cargo-git` | Implemented | Implemented | |
| `rustup` | Implemented | Implemented | |
| `npm-cache` | Implemented | Implemented | |
| `pnpm-store` | Implemented | Implemented | |
| `yarn-cache` | Implemented | Implemented | |
| `gradle-cache` | Implemented | Implemented | |
| `maven-cache` | Implemented | Implemented | |
| `swiftpm-cache` | Implemented | Implemented | |
| `playwright` | Implemented | Implemented | |
| `cypress` | Implemented | Implemented | |
| `brew-cache` | Implemented | Implemented | |
| `jetbrains` | Implemented | Implemented | |
| `codex` | Implemented | Implemented | |
| `xdg-cache` | Implemented | Implemented | |
| `library-caches` | Implemented | Implemented | |
| `library-logs` | Implemented | Implemented | |
| `containers` | Implemented | Implemented | |
| `orbstack` | Implemented | Implemented | |
| `apple-container` | Implemented | Implemented | |
| `claude-vm` | Implemented | Implemented | |
| `docker` | Implemented | Implemented | |
| `trash` | Implemented | Implemented | |
| `downloads` | Implemented | Implemented | |
| `artifact:node_modules` | Implemented | Implemented | |
| `artifact:target` | Implemented | Implemented | |
| `artifact:build` | Implemented | Implemented | |
| `artifact:.build` | Implemented | Implemented | |
| `artifact:dist` | Implemented | Implemented | |
| `artifact:.next` | Implemented | Implemented | |
| `artifact:.nuxt` | Implemented | Implemented | |
| `artifact:.turbo` | Implemented | Implemented | |
| `artifact:.parcel-cache` | Implemented | Implemented | |
| `artifact:.gradle` | Implemented | Implemented | |
| `artifact:.dart_tool` | Implemented | Implemented | |
| `artifact:DerivedData` | Implemented | Implemented | |
| `artifact:Pods` | Implemented | Implemented | |
| `artifact:__pycache__` | Implemented | Implemented | |
| `artifact:.pytest_cache` | Implemented | Implemented | |
| `artifact:.mypy_cache` | Implemented | Implemented | |
| `artifact:.ruff_cache` | Implemented | Implemented | |
| `artifact:.venv` | Implemented | Implemented | |
| `artifact:venv` | Implemented | Implemented | |

Scan-wide differences that belong to no single rule:

| Behaviour | CLI | App | Note |
|---|---|---|---|
| Project evidence | Implemented | Pending | The CLI reports build output only when a marker file of the matching ecosystem (for example `package.json` for `node_modules`) is at the nearest project boundary. The app reports each directory with a matching name. The conformance cases contain only projects with a marker. |
| Storage engine | Implemented | Implemented | `internal/usage` and `HandbyteCore/Usage.swift`. The `usage` and `categories` conformance cases keep them equal. Both read each directory with `getattrlistbulk` (`lstat` for mount points, firmlinks and failed entries). Both count a full APFS clone once for each device and clone ID, and count a partial clone in full with the may-share mark. |
| Storage collector | Implemented | Implemented | Trash only, with the same lists of private and standard folders (`internal/cleaner/collect.go`, `HandbyteCore/Collector.swift`). Change both lists together. |
| Purgeable space | Not applicable | Implemented | `statfs` has no purgeable value; the app reads it from the volume resource values. |
| Owner check | Intentional difference | Intentional difference | The CLI checks the `processes` of a rule against `ps`; a rule without processes is shown only (inspection). The app checks the `owners` bundle IDs against the running apps; a rule without owners has no owner check. |
| Smart Clean | Implemented | Implemented | Safe tier and eligible only, one item inside another counts once, removal by data class (`rebuildable` removed, other data to the Trash), `--trash` / "Always use the Trash". |
| Apps | Implemented | Implemented | Inventory, file matching (`apps` conformance cases) and removal. The CLI moves through the Finder and journals one group for `handbyte restore <group>`; the app moves with the file manager. Both journal one group with the rule ID `app:<bundle ID>`, restored together. The app also asks LaunchServices whether a leftover's bundle ID is installed elsewhere. Both find launchd jobs by `AssociatedBundleIdentifiers` or a program in the bundle, group containers of the signing team when no other app has it, and files in `/Library` (listed, never removed). Both refuse an app with a system extension and can run `brew uninstall --cask` after a confirmation. The CLI reads the team with `codesign -dv`, the app with `SecStaticCode`. |
| System rules | Implemented | Implemented | The same fixed commands: `find` for the safe rules, and `log erase --all` for the review rule `system-unified-log`, which needs its own confirmation and is never part of Smart Clean or `--yes`. The CLI runs them through `sudo`; the app through the macOS administrator dialog. |
| Mouse support | Implemented | Not applicable | `handbyte config mouse off` turns it off in the terminal. |
| Hard links | Intentional difference | Implemented | The CLI counts every hard link to a file, so a file with two links is counted twice. The app counts an inode once per scan, so the sum over all candidates equals the bytes a cleanup can free. `scripts/parity.sh` reports both effects as expected size differences. |
| Operations journal | Implemented | Implemented | One shared file, `~/Library/Application Support/handbyte/actions.jsonl`, one JSON record per line, the last line of an ID is its state (`journal` conformance case). The CLI writes an intent line before each action; the app writes the outcome only. Both restore by ID and by group, and check the Trash identity. The app shows its old `operations.log` in History, without Restore. |
| Settings file | Intentional difference | Intentional difference | The CLI stores roots and exclusions in its own `config.json`. The app stores deletion mode, minimum size, roots and exclusions in `~/Library/Application Support/Handbyte/settings.json`. Neither side reads the other file. |
