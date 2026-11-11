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

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.2.0] - 2026-11-11

### Added

- **See your Mac at a glance.** A new Overview shows storage categories,
  available and purgeable space, and the last scan, with a new visual style.
  Switch sections from the top bar or find actions with the command palette.
- **Find large files in Storage.** Explore your home folder by category,
  treemap or list, then review selected files before moving them to the Trash.
  Protected paths stay excluded, and cleanup folders link to Clean.
- **Review apps and their files together.** Find unused apps, inspect related
  files and background items, and remove apps or files after review.
  Protected and running apps stay blocked; Homebrew removal asks separately.
- **Restore items from History.** See cleanup actions from the app and CLI
  in one place, and restore items still in the Trash without replacing files.
  An uninstalled app and its files can be restored together.
- **Clean old system logs with explicit approval.** Review old crash reports
  and system logs, then authorize cleanup with the macOS password dialog.
  Erasing the unified log requires a separate confirmation.

### Changed

- **Smart Clean removes regenerable files directly by default.** Review and
  clean caches, logs and build output in one screen; other items use the Trash.
  Enable "Always use the Trash" to keep the previous behavior.
- **Clean more browser and developer data.** The expanded catalog covers
  browser profiles, developer tools, app caches, crash reports, device firmware,
  iOS backups and Mail downloads, with review required for sensitive items.
- **Navigate with the keyboard and VoiceOver.** Use section shortcuts and
  the command palette to reach actions. Animations respect Reduce Motion.

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
