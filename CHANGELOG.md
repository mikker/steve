# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Targeting by app or executable path with global `--app-path` and `--exec-path`.
- Target handle support via global `--target app://<pid>`.
- `resolve`/`attach` command for unambiguous target metadata (`pid`, `bundleId`, app path, executable path, window count, frontmost flag, and reusable target handle).
- Interaction preconditions `--activate` and `--frontmost` for `click`, `type`, and `key`.
- `focused` command to return the currently focused UI element for a target app.
- `selection` command to return current selection state (`selectedText`, `selectedRows`, `selectedChildren`, focused element context).
- `wait`/`wait-for` support for `--window-count` and `--element-id`.
- `snapshot` command to capture app tree state (including target metadata and window count) to stdout or JSON file.
- `diff` command to compare two snapshots and report added/removed/changed nodes.
- Global `--jsonl-trace[=<path>]` command tracing and a JSONL trace sink for resolved targets, matching, and interaction events.
- `find --query <text>` as an alias for text-based search.

### Changed
- `find <query>` now treats positional argument as text query instead of role.
- Text matching now searches `AXTitle`, `AXValue`, `AXDescription`, and `AXIdentifier` by default.
- `apps` output now includes `appPath`, `executablePath`, and `frontmost`.
- Element output now includes `value` and `description` where available.
- Global usage/help output now includes new commands and global options.

### Fixed
- `--jsonl-trace` now accepts an optional path without accidentally consuming the next command token.
- Interaction targeting with `--activate`/`--frontmost` now supports id-based clicks by deriving app context from `ax://...` element ids.

## [0.4.0] - 2026-01-19

### Added
- `--format json` (or `-j`) for compact JSON output.

### Changed
- Default output is structured text instead of JSON.
- Text output now emits only data (no ok/data labels).
- Frames are rendered inline in text output (x/y/w/h).
- Menu output flattens the AXMenu wrapper for children.

## [0.3.0] - 2026-01-16

### Added
- `outline-rows` to list outline rows with accessible labels and selection state.
- `find --descendants`/`--desc` to match `--text` against descendant content.

### Changed
- Text matching now considers headings for SwiftUI lists.

### Fixed
- Click coordinates now align with AX element frames (no y-axis flip).

## [0.2.0] - 2026-01-16

### Added
- Function key support (F1–F24), `fn` modifier, and `key --raw`.
- `key --list` and `keys` to list supported key names.
- `--text` and `--window` support for `exists`, `wait`, and `assert`.
- Menu matching options (`--contains`, `--case-insensitive`, `--normalize-ellipsis`) and `menu --list`.
- Per-command help output for key/menu/find/exist/wait/assert.
- Status bar interaction via `statusbar` (list, click, and menu listing).
- Plain-text help when running `steve` with no args or `-h`.

### Changed
- Help/usage output is plain text by default.

### Fixed
- Function keys send an explicit `fn` key event for better reliability across apps.

## [0.1.0] - 2026-01-16

### Added
- Initial `steve` CLI with macOS Accessibility automation.
- JSON output for commands, core UI interactions, and menu support.
- Release workflow and test suite (unit + optional integration).
