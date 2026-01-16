---
name: steve
description: Use the steve CLI to automate macOS apps via Accessibility APIs. Use when you need to drive Mac UI (apps, windows, menus, elements), run UI smoke tests, or script interactions using steve commands and JSON output.
---

# Steve

## Overview

Use the `steve` CLI to automate macOS applications through the Accessibility API. Prefer steve when you need deterministic, scriptable UI control with JSON responses.

## Quick Start

1. Assume the CLI is installed and available on `PATH`. If not, download it from the GitHub releases page: https://github.com/mikker/steve/releases
2. Ensure Accessibility permissions are granted for the terminal running steve.

```bash
steve apps
```

## Core Tasks

### Target an app or window

Use `--app`, `--bundle`, or `--pid` to select the app, and `--window` to scope to a window title.

```bash
steve elements --app "System Settings" --window "Settings"
```

### Find text reliably

Use `--text` to match visible text via `AXValue`, `AXDescription`, or `AXStaticText` title (case-insensitive substring).

```bash
steve find --text "Dictation Mode" --window "Settings"
```

### Click the right ancestor

After a text match, use `--ancestor-role` and `--click` to press a nearby container row/cell/button.

```bash
steve find --text "Dictation Mode" --window "Settings" --ancestor-role AXRow --click
```

### Common interactions

```bash
steve click --title "OK"
steve type "hello world"
steve key cmd+shift+p
steve menu "File" "New"
```

## Reliability Tips

- Prefer `--window` and `--text` over raw coordinates.
- Use `wait` for UI state changes before clicking:

```bash
steve wait --title "Results" --timeout 5
```
