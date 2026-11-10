# Changelog

All notable changes to the Handbyte macOS app are documented in this file.
The Go CLI in the repository root has its own release notes on GitHub.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Before 1.0, a breaking change bumps the minor version. Releases are dated.

The release workflow publishes the section of the released version as the
GitHub Release body and as the "What's New" notes in the in-app updater.

## [Unreleased]

### Added

- An Overview screen with the free space, one main action and the result of
  the last scan.
- A top bar with the sections Overview, Clean, Apps, Storage and History.
- A Storage section: a scan of the home folder that shows running totals,
  then a treemap and a list of the opened folder, and the largest files.
  It is read-only. A folder that a cleanup rule covers is marked, and
  "Review in Clean" opens Clean.
- Storage sums the home folder by categories (Apps, Developer, Documents,
  Media, Caches and logs, Other) and keeps the last result. The next scan
  shows the last sizes until each folder is measured again, and the
  Overview splits the used space by these categories.
- Storage can pick files and folders for the Trash. The picked items are
  reviewed in one sheet and moved to the Trash; each move is recorded in
  the operations log. Standard folders, private data such as
  `~/Library/Keychains`, excluded paths and symbolic links cannot be picked,
  and a folder that a cleanup rule covers points to Clean.
- The Overview names the purgeable part of the free space.
- Smart Clean names the old system logs (crash reports older than 30 days,
  rotated logs older than 7 days). Clean with Password runs fixed commands
  as root after the macOS password dialog; they are the same as
  `handbyte clean --system`.
- Apps lists the installed apps with size, last use, source, version and
  architectures, with the filters All, Unused, Largest and Leftovers. The
  inspector shows the files each app keeps in ~/Library with how sure the
  match is; caches, logs and state are selected, the app's data only on
  request. Uninstall moves the app and the selected files to the Trash;
  Remove Files Only keeps the app. Apps of macOS, apps from Homebrew and
  running apps are refused with the reason. Leftovers lists data of removed
  apps for review; nothing in it is selected.
- A command palette (⌘K) finds sections and actions by typing. ⌘1 to ⌘5
  open the sections and ⌘R runs Clean Now.
- On the first run the Overview explains in three lines what Clean Now
  takes, what goes to the Trash and where History is.
- History lists each item that was removed or moved to the Trash, newest
  first, by the app and by the CLI. An item in the Trash can be put back
  with Restore; it never replaces anything at the original place and checks
  that the Trash item is the one that was moved. One Restore puts back an
  uninstalled app with its files.

### Changed

- Clean opens Smart Clean: one screen that scans, shows what is safe to
  clean area by area, cleans after one click and shows the freed space.
  "Choose items" opens the full list with the safe items selected.
- Caches, logs and build output are removed directly, because they rebuild
  by themselves; other items go to the Trash. The setting "Always use the
  Trash" keeps the old behavior.
- The rule catalog has 50 more rules: browser caches for each profile, more
  developer tools, VS Code and Electron app caches, crash reports, device
  firmware, iOS backups and Mail downloads.

- A new app icon and a new visual style: ink on paper with one green.
- The cleanup rules come from a catalog file shared with the CLI. The
  cleanup scope is the same.
- The app and the CLI write one journal,
  `~/Library/Application Support/handbyte/actions.jsonl`. The old
  `~/Library/Logs/handbyte/operations.log` is still shown in History.

### Deprecated

### Removed

### Fixed

### Security

## [0.1.0] - 2026-11-09

### Added

- **Review and clean caches and build output in a native window.** Handbyte
  scans the same locations as the `handbyte` CLI, groups what it finds by
  application and project, and explains what each item is before you act.
- **Nothing is removed without a confirmation.** Items move to the Trash with
  Finder "Put Back" information by default. Permanent deletion is a separate
  setting and asks again before every cleanup.
- **Safety tiers tell apart what can be cleaned at once and what needs a
  look.** Items that a running app still uses or that are not regenerable are
  held back and shown with the reason.
- **Settings for the minimum size, project roots and exclusions.** Mark any
  item "Never Clean This" from its detail pane.
- **In-app updates.** Handbyte checks for new versions and installs them with
  Sparkle.
