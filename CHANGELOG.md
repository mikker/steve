# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

## [0.1.0] - 2026-01-16

### Added
- Initial `steve` CLI with macOS Accessibility automation.
- JSON output for commands, core UI interactions, and menu support.
- Release workflow and test suite (unit + optional integration).
