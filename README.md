<img src="steve-logo.webp" alt="steve" width="400">

# steve

A CLI for driving Mac applications via the Accessibility API. Designed for automated testing and AI agent control.

[![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)

## Install

[Download latest from GitHub](https://github.com/mikker/steve/releases/latest)

Or with Homebrew:

```
brew tap mikker/tap
brew install steve
```

## Usage

All commands output structured text to stdout by default, except `screenshot` which outputs PNG to stdout unless `-o/--output` is provided.

Use `--format json` (or `-j`) for compact JSON output. Errors go to stderr and return a non-zero exit code.

Text:

```
...
```

Example:

```
- Extensions
  frame: x=837 y=157 w=885 h=814
```

JSON:

```
{"ok":true,"data":...}
{"ok":false,"error":"message"}
```

### Application Control

```
steve apps
steve resolve --app "Safari"
steve resolve --app-path "/Applications/Safari.app"
steve attach --pid 1234
steve focus "AppName"
steve focus --pid 1234
steve focus --bundle "com.example.app"
steve launch "com.example.app" --wait
steve quit "AppName" --force
```

### Element Discovery

```
steve elements
steve elements --depth 5
steve elements --window "Settings"
steve find "Dictation Mode"
steve find --title "Submit"
steve find --text "Dictation Mode"
steve find --text "Dictation Mode" --window "Settings" --ancestor-role AXRow --click
steve find --role AXButton --title "OK"
steve find --identifier "loginButton"
steve element-at 100 200
```

### Interactions

```
steve click "ax://1234/0.2.5"
steve click --activate --frontmost "ax://1234/0.2.5"
steve click --title "Submit"
steve click --text "Dictation Mode"
steve click --window "Settings" --text "Dictation Mode"
steve click-at 100 200 --double
steve type --activate "hello world" --delay 50
steve key --activate cmd+shift+p
steve key f12
steve key fn+f12
steve key --raw 122
steve key --list
steve set-value "ax://1234/0.1" "new text"
steve scroll down --amount 5
steve scroll --element "ax://1234/0.4" up
```

### Reliability Helpers

- `find --text` (and positional `find "query"`) matches across `AXTitle`, `AXValue`, `AXDescription`, and `AXIdentifier` (case-insensitive substring).
- `--window "Title"` scopes `find`, `elements`, and `click` to a specific window title.
- `--ancestor-role AXRow|AXCell|AXButton --click` clicks the nearest ancestor role after a text match.
- `--activate` and `--frontmost` can be used with `key`, `type`, and `click`.

### Assertions

```
steve exists --title "Welcome"
steve exists --text "Ready" --window "Settings"
steve wait --title "Results" --timeout 5
steve wait --title "Loading..." --gone --timeout 10
steve wait --text "Loading..." --window "Settings" --timeout 10
steve wait-for --window-count 2 --timeout 10
steve wait-for --element-id "ax://1234/0.4" --timeout 10
steve assert --title "Submit" --enabled
steve assert --title "Checkbox" --checked
steve assert --title "Input" --value "expected text"
```

### Focus And Selection

```
steve focused
steve selection
steve selection --app "Finder"
```

### Windows

```
steve windows
steve window focus "ax://win/123"
steve window resize "ax://win/123" 800 600
steve window move "ax://win/123" 100 100
```

### Menus

```
steve menus
steve menu "File" "New"
steve menu --contains --case-insensitive "settings..."
steve menu --list "File"
steve statusbar --list
steve statusbar "Wi-Fi"
steve statusbar --menu --contains "Battery"
```

### Screenshots

```
steve screenshot
steve screenshot --app "AppName" -o screenshot.png
steve screenshot --element "ax://1234/0.2" -o element.png
```

### Snapshots And Diff

```
steve snapshot --output before.json
steve snapshot --output after.json
steve diff before.json after.json
```

## Global Options

```
--app "Name"
--pid 1234
--bundle "id"
--app-path "/Applications/Safari.app"
--exec-path "/Applications/Safari.app/Contents/MacOS/Safari"
--target app://1234
--timeout 5
--verbose
--quiet
--format text|json
-j
--jsonl-trace
--jsonl-trace /tmp/steve-trace.jsonl
```

## Exit Codes

| Code | Meaning                           |
| ---- | --------------------------------- |
| 0    | Success                           |
| 1    | Element not found                 |
| 2    | App not found / not running       |
| 3    | Timeout                           |
| 4    | Permission denied (accessibility) |
| 5    | Invalid arguments                 |

## Notes

- Coordinates are in screen space (0,0 = top-left of main display). Multiple monitors extend rightward/downward.
- Element IDs are stable within a session but not across app restarts.

## Build

```
swift build -c release
```

## License

MIT
