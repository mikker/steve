import Foundation

func parseGlobalOptions(_ args: inout [String]) -> (GlobalOptions, String?) {
    var options = GlobalOptions()
    var i = 0
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--app":
            guard i + 1 < args.count else { return (options, "Missing value for --app") }
            options.appName = args[i + 1]
            args.removeSubrange(i...i + 1)
            continue
        case "--pid":
            guard i + 1 < args.count else { return (options, "Missing value for --pid") }
            if let pid = Int32(args[i + 1]) {
                options.pid = pid
                args.removeSubrange(i...i + 1)
                continue
            }
            return (options, "Invalid pid")
        case "--bundle":
            guard i + 1 < args.count else { return (options, "Missing value for --bundle") }
            options.bundleId = args[i + 1]
            args.removeSubrange(i...i + 1)
            continue
        case "--app-path":
            guard i + 1 < args.count else { return (options, "Missing value for --app-path") }
            options.appPath = args[i + 1]
            args.removeSubrange(i...i + 1)
            continue
        case "--exec-path":
            guard i + 1 < args.count else { return (options, "Missing value for --exec-path") }
            options.executablePath = args[i + 1]
            args.removeSubrange(i...i + 1)
            continue
        case "--target":
            guard i + 1 < args.count else { return (options, "Missing value for --target") }
            guard parseTargetHandle(args[i + 1], into: &options) else {
                return (options, "Invalid target handle")
            }
            args.removeSubrange(i...i + 1)
            continue
        case "--timeout":
            guard i + 1 < args.count else { return (options, "Missing value for --timeout") }
            if let t = Double(args[i + 1]) {
                options.timeout = t
                args.removeSubrange(i...i + 1)
                continue
            }
            return (options, "Invalid timeout")
        case "--verbose":
            options.verbose = true
            args.remove(at: i)
            continue
        case "--quiet":
            options.quiet = true
            args.remove(at: i)
            continue
        case "--format":
            guard i + 1 < args.count else { return (options, "Missing value for --format") }
            let value = args[i + 1]
            guard let format = parseOutputFormat(value) else { return (options, "Invalid format") }
            options.format = format
            args.removeSubrange(i...i + 1)
            continue
        case "-j":
            options.format = .json
            args.remove(at: i)
            continue
        case "--jsonl-trace":
            options.traceJSONL = true
            if i + 1 < args.count, looksLikeTracePath(args[i + 1]) {
                options.tracePath = args[i + 1]
                args.removeSubrange(i...i + 1)
            } else {
                args.remove(at: i)
            }
            continue
        default:
            if arg.hasPrefix("--format=") {
                let value = String(arg.dropFirst("--format=".count))
                guard let format = parseOutputFormat(value) else { return (options, "Invalid format") }
                options.format = format
                args.remove(at: i)
                continue
            }
            if arg.hasPrefix("--app-path=") {
                options.appPath = String(arg.dropFirst("--app-path=".count))
                args.remove(at: i)
                continue
            }
            if arg.hasPrefix("--exec-path=") {
                options.executablePath = String(arg.dropFirst("--exec-path=".count))
                args.remove(at: i)
                continue
            }
            if arg.hasPrefix("--jsonl-trace=") {
                let value = String(arg.dropFirst("--jsonl-trace=".count))
                options.traceJSONL = true
                options.tracePath = value.isEmpty ? nil : value
                args.remove(at: i)
                continue
            }
            if arg.hasPrefix("--target=") {
                let value = String(arg.dropFirst("--target=".count))
                guard parseTargetHandle(value, into: &options) else {
                    return (options, "Invalid target handle")
                }
                args.remove(at: i)
                continue
            }
            i += 1
        }
    }
    return (options, nil)
}

func usage() -> String {
    """
    steve - Mac UI Automation CLI

    Commands: apps, resolve, attach, focus, launch, quit, elements, outline-rows, find, element-at,
              click, click-at, type, key, keys, set-value, scroll, exists, wait, wait-for, assert,
              focused, selection, windows, window, menus, menu, statusbar, snapshot, diff, screenshot

    Global options: --app, --pid, --bundle, --app-path, --exec-path, --target,
                    --timeout, --verbose, --quiet, --format <text|json>, -j,
                    --jsonl-trace[=<path>]
    """
}

func commandUsage(_ command: String) -> String? {
    switch command {
    case "key":
        return """
        steve key <shortcut>
        steve key --raw <keycode>
        steve key --list

        Examples:
          steve key f12
          steve key fn+f12
          steve key cmd+shift+p
          steve key --raw 122
        """
    case "keys":
        return "steve keys"
    case "menu":
        return """
        steve menu [--contains] [--case-insensitive] [--normalize-ellipsis] <path...>
        steve menu --list [--contains] [--case-insensitive] [--normalize-ellipsis] <path...>

        Examples:
          steve menu \"File\" \"New\"
          steve menu --contains --case-insensitive \"settings...\"
          steve menu --list \"File\"
        """
    case "statusbar":
        return """
        steve statusbar --list
        steve statusbar [--contains] [--case-insensitive] [--normalize-ellipsis] <item>
        steve statusbar --menu [--contains] [--case-insensitive] [--normalize-ellipsis] <item>

        Examples:
          steve statusbar --list
          steve statusbar \"Wi-Fi\"
          steve statusbar --menu --contains \"Battery\"
        """
    case "find":
        return """
        steve find [--role <role>] [--title <title>] [--text <text>] [--identifier <id>]
                   [--window <title>] [--ancestor-role <role>] [--descendants|--desc] [--click]
        """
    case "resolve", "attach":
        return "steve resolve [--app|--pid|--bundle|--app-path|--exec-path]"
    case "focused":
        return "steve focused [--app|--pid|--bundle|--app-path|--exec-path]"
    case "selection":
        return "steve selection [--app|--pid|--bundle|--app-path|--exec-path]"
    case "outline-rows":
        return """
        steve outline-rows [--outline <title>] [--window <title>]
        """
    case "exists":
        return "steve exists [--role <role>] [--title <title>] [--text <text>] [--identifier <id>] [--window <title>]"
    case "wait":
        return "steve wait [--role <role>] [--title <title>] [--text <text>] [--identifier <id>] [--window <title>] [--element-id <id>] [--window-count <n>] [--gone] [--timeout <sec>]"
    case "wait-for":
        return "steve wait-for [--role <role>] [--title <title>] [--text <text>] [--identifier <id>] [--window <title>] [--element-id <id>] [--window-count <n>] [--gone] [--timeout <sec>]"
    case "assert":
        return "steve assert [--role <role>] [--title <title>] [--text <text>] [--identifier <id>] [--window <title>] [--enabled] [--checked] [--value <value>]"
    case "snapshot":
        return "steve snapshot [--depth <n>] [--output <path>]"
    case "diff":
        return "steve diff <before.json> <after.json>"
    default:
        return nil
    }
}

func hasHelpFlag(_ args: [String]) -> Bool {
    args.contains("--help") || args.contains("-h") || args.contains("help")
}

func runCLI(args: [String]) -> Int32 {
    var args = args
    if args.isEmpty {
        print(usage())
        return UitoolExit.success.rawValue
    }

    if hasHelpFlag([args.first!]) {
        print(usage())
        return UitoolExit.success.rawValue
    }

    let command = args.removeFirst()
    let (options, error) = parseGlobalOptions(&args)
    Output.configure(format: options.format)
    Trace.configure(enabled: options.traceJSONL, path: options.tracePath)
    if let error {
        Output.error(error, quiet: options.quiet)
        return UitoolExit.invalidArguments.rawValue
    }

    if hasHelpFlag(args), let help = commandUsage(command) {
        print(help)
        return UitoolExit.success.rawValue
    }

    let ctx = CommandContext(options: options)
    Trace.log(["event": "command.start", "command": command, "args": args])
    switch command {
    case "apps":
        return Commands.apps(ctx: ctx)
    case "resolve", "attach":
        return Commands.resolve(ctx: ctx, args: args)
    case "focus":
        return Commands.focus(ctx: ctx, args: args)
    case "launch":
        return Commands.launch(ctx: ctx, args: args)
    case "quit":
        return Commands.quit(ctx: ctx, args: args)
    case "elements":
        return Commands.elements(ctx: ctx, args: args)
    case "outline-rows":
        return Commands.outlineRows(ctx: ctx, args: args)
    case "find":
        return Commands.find(ctx: ctx, args: args)
    case "element-at":
        return Commands.elementAt(ctx: ctx, args: args)
    case "click":
        return Commands.click(ctx: ctx, args: args)
    case "click-at":
        return Commands.clickAt(ctx: ctx, args: args)
    case "type":
        return Commands.typeText(ctx: ctx, args: args)
    case "key":
        return Commands.key(ctx: ctx, args: args)
    case "keys":
        return Commands.keys(ctx: ctx)
    case "set-value":
        return Commands.setValue(ctx: ctx, args: args)
    case "scroll":
        return Commands.scroll(ctx: ctx, args: args)
    case "exists":
        return Commands.exists(ctx: ctx, args: args)
    case "wait":
        return Commands.wait(ctx: ctx, args: args)
    case "wait-for":
        return Commands.wait(ctx: ctx, args: args)
    case "assert":
        return Commands.assert(ctx: ctx, args: args)
    case "focused":
        return Commands.focused(ctx: ctx, args: args)
    case "selection":
        return Commands.selection(ctx: ctx, args: args)
    case "windows":
        return Commands.windows(ctx: ctx, args: args)
    case "window":
        return Commands.windowCommand(ctx: ctx, args: args)
    case "menus":
        return Commands.menus(ctx: ctx, args: args)
    case "menu":
        return Commands.menu(ctx: ctx, args: args)
    case "statusbar":
        return Commands.statusbar(ctx: ctx, args: args)
    case "snapshot":
        return Commands.snapshot(ctx: ctx, args: args)
    case "diff":
        return Commands.diff(ctx: ctx, args: args)
    case "screenshot":
        return Commands.screenshot(ctx: ctx, args: args)
    case "--help", "help", "-h":
        print(usage())
        return UitoolExit.success.rawValue
    default:
        Output.error("Unknown command", quiet: options.quiet)
        return UitoolExit.invalidArguments.rawValue
    }
}

private func parseOutputFormat(_ value: String) -> OutputFormat? {
    switch value.lowercased() {
    case "text":
        return .text
    case "json":
        return .json
    default:
        return nil
    }
}

private func parseTargetHandle(_ value: String, into options: inout GlobalOptions) -> Bool {
    if let pid = Int32(value) {
        options.pid = pid
        return true
    }
    if value.hasPrefix("app://") {
        let pidString = String(value.dropFirst("app://".count))
        if let pid = Int32(pidString) {
            options.pid = pid
            return true
        }
        return false
    }
    return false
}

private func looksLikeTracePath(_ value: String) -> Bool {
    value.hasPrefix("/") || value.hasPrefix("./") || value.hasPrefix("../") || value.hasPrefix("~") || value.hasSuffix(".jsonl")
}
