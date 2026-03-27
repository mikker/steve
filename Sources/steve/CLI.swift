import Foundation

struct CommandHelp {
    var name: String
    var aliases: [String] = []
    var summary: String
    var usage: [String]
    var examples: [String] = []

    var visibleNames: [String] {
        [name] + aliases
    }
}

let globalOptionHelpLines = [
    "--app <name>               Target app by localized name or bundle id",
    "--pid <pid>                Target app by process id",
    "--bundle <bundle-id>       Target app by bundle identifier",
    "--app-path <path>          Target app by app bundle path",
    "--exec-path <path>         Target app by executable path",
    "--target app://<pid>       Target app by stable handle",
    "--timeout <seconds>        Timeout for wait and launch operations (default: 5)",
    "--verbose                  Enable verbose diagnostics",
    "--quiet                    Suppress normal output",
    "--format <text|json>       Select output format",
    "-j                         Alias for --format json",
    "--jsonl-trace[=<path>]     Emit JSONL trace events"
]

let commandHelpEntries = [
    CommandHelp(
        name: "apps",
        summary: "List running macOS applications.",
        usage: ["steve COMMAND"],
        examples: ["steve COMMAND"]
    ),
    CommandHelp(
        name: "resolve",
        aliases: ["attach"],
        summary: "Resolve a target app and print canonical identifiers.",
        usage: [
            "steve COMMAND [<app-name>]",
            "steve COMMAND [--app <name> | --pid <pid> | --bundle <bundle-id> | --app-path <path> | --exec-path <path> | --target app://<pid>]"
        ],
        examples: [
            "steve COMMAND --app \"Safari\"",
            "steve COMMAND --pid 1234"
        ]
    ),
    CommandHelp(
        name: "focus",
        summary: "Bring a target app to the front.",
        usage: [
            "steve COMMAND [<app-name>]",
            "steve COMMAND [--app <name> | --pid <pid> | --bundle <bundle-id>]"
        ],
        examples: [
            "steve COMMAND \"Finder\"",
            "steve COMMAND --bundle com.apple.Safari"
        ]
    ),
    CommandHelp(
        name: "launch",
        summary: "Launch an app by bundle identifier.",
        usage: ["steve COMMAND <bundle-id> [--wait]"],
        examples: ["steve COMMAND com.apple.Safari --wait"]
    ),
    CommandHelp(
        name: "quit",
        summary: "Quit a target app.",
        usage: [
            "steve COMMAND [<app-name>] [--force]",
            "steve COMMAND [--app <name> | --pid <pid> | --bundle <bundle-id>] [--force]"
        ],
        examples: [
            "steve COMMAND \"Safari\"",
            "steve COMMAND --pid 1234 --force"
        ]
    ),
    CommandHelp(
        name: "elements",
        summary: "Print the accessibility tree for a target app or window.",
        usage: ["steve COMMAND [--depth <n>] [--window <title>]"],
        examples: [
            "steve COMMAND --app \"System Settings\" --depth 5",
            "steve COMMAND --window \"Settings\""
        ]
    ),
    CommandHelp(
        name: "outline-rows",
        summary: "List rows from an outline view.",
        usage: ["steve COMMAND [--outline <title>] [--window <title>]"],
        examples: ["steve COMMAND --window \"Settings\" --outline Sidebar"]
    ),
    CommandHelp(
        name: "find",
        summary: "Find elements by role, title, text, or identifier.",
        usage: [
            "steve COMMAND [<query>]",
            "steve COMMAND [--role <role>] [--title <title>] [--text <text> | --query <text>] [--identifier <id>] [--window <title>] [--ancestor-role <role>] [--descendants|--desc] [--click]"
        ],
        examples: [
            "steve COMMAND \"Dictation Mode\"",
            "steve COMMAND --role AXButton --title OK",
            "steve COMMAND --text \"Loading\" --window \"Settings\" --click"
        ]
    ),
    CommandHelp(
        name: "element-at",
        summary: "Describe the element at screen coordinates.",
        usage: ["steve COMMAND <x> <y>"],
        examples: ["steve COMMAND 100 200"]
    ),
    CommandHelp(
        name: "click",
        summary: "Click an element by id or query.",
        usage: [
            "steve COMMAND <ax-element-id> [--activate] [--frontmost]",
            "steve COMMAND [--role <role>] [--title <title>] [--text <text>] [--identifier <id>] [--window <title>] [--activate] [--frontmost]"
        ],
        examples: [
            "steve COMMAND ax://1234/0.2.5",
            "steve COMMAND --title Submit",
            "steve COMMAND --window \"Settings\" --text \"Dictation Mode\""
        ]
    ),
    CommandHelp(
        name: "click-at",
        summary: "Click screen coordinates.",
        usage: ["steve COMMAND <x> <y> [--double] [--right]"],
        examples: [
            "steve COMMAND 100 200",
            "steve COMMAND 400 300 --double"
        ]
    ),
    CommandHelp(
        name: "type",
        summary: "Type text into the current input target.",
        usage: ["steve COMMAND <text> [--delay <ms>] [--activate] [--frontmost]"],
        examples: [
            "steve COMMAND \"hello world\"",
            "steve COMMAND \"cmd palette\" --delay 50 --activate"
        ]
    ),
    CommandHelp(
        name: "key",
        summary: "Send a key shortcut or raw keycode.",
        usage: [
            "steve COMMAND <shortcut> [--activate] [--frontmost]",
            "steve COMMAND --raw <keycode> [--activate] [--frontmost]",
            "steve COMMAND --list"
        ],
        examples: [
            "steve COMMAND cmd+shift+p",
            "steve COMMAND fn+f12",
            "steve COMMAND --raw 122"
        ]
    ),
    CommandHelp(
        name: "keys",
        summary: "List supported key names.",
        usage: ["steve COMMAND"],
        examples: ["steve COMMAND"]
    ),
    CommandHelp(
        name: "set-value",
        summary: "Set AXValue on an element.",
        usage: ["steve COMMAND <ax-element-id> <value>"],
        examples: ["steve COMMAND ax://1234/0.1 \"new text\""]
    ),
    CommandHelp(
        name: "scroll",
        summary: "Scroll the mouse wheel or a specific element.",
        usage: [
            "steve COMMAND [up|down] [--amount <n>]",
            "steve COMMAND [up|down] [--amount <n>] [--element <ax-element-id>]"
        ],
        examples: [
            "steve COMMAND down --amount 5",
            "steve COMMAND up --element ax://1234/0.4"
        ]
    ),
    CommandHelp(
        name: "exists",
        summary: "Exit successfully when an element exists.",
        usage: ["steve COMMAND [--role <role>] [--title <title>] [--text <text>] [--identifier <id>] [--window <title>]"],
        examples: [
            "steve COMMAND --title Welcome",
            "steve COMMAND --text Ready --window \"Settings\""
        ]
    ),
    CommandHelp(
        name: "wait",
        summary: "Wait for an element, element id, or window count condition.",
        usage: ["steve COMMAND [--role <role>] [--title <title>] [--text <text>] [--identifier <id>] [--window <title>] [--element-id <id>] [--window-count <n>] [--gone] [--timeout <seconds>]"],
        examples: [
            "steve COMMAND --title Results --timeout 5",
            "steve COMMAND --text Loading --gone --timeout 10"
        ]
    ),
    CommandHelp(
        name: "wait-for",
        summary: "Alias of wait with a clearer name for scripts.",
        usage: ["steve COMMAND [--role <role>] [--title <title>] [--text <text>] [--identifier <id>] [--window <title>] [--element-id <id>] [--window-count <n>] [--gone] [--timeout <seconds>]"],
        examples: [
            "steve COMMAND --window-count 2 --timeout 10",
            "steve COMMAND --element-id ax://1234/0.4 --timeout 10"
        ]
    ),
    CommandHelp(
        name: "assert",
        summary: "Assert element state and fail with a non-zero exit code when it does not match.",
        usage: ["steve COMMAND [--role <role>] [--title <title>] [--text <text>] [--identifier <id>] [--window <title>] [--enabled] [--checked] [--value <value>]"],
        examples: [
            "steve COMMAND --title Submit --enabled",
            "steve COMMAND --title Checkbox --checked"
        ]
    ),
    CommandHelp(
        name: "focused",
        summary: "Print the focused accessibility element.",
        usage: ["steve COMMAND [<app-name> | --app <name> | --pid <pid> | --bundle <bundle-id>]"],
        examples: [
            "steve COMMAND",
            "steve COMMAND --app Finder"
        ]
    ),
    CommandHelp(
        name: "selection",
        summary: "Print current selection details for the target app.",
        usage: ["steve COMMAND [<app-name> | --app <name> | --pid <pid> | --bundle <bundle-id>]"],
        examples: [
            "steve COMMAND",
            "steve COMMAND --app Finder"
        ]
    ),
    CommandHelp(
        name: "windows",
        summary: "List windows for a target app.",
        usage: ["steve COMMAND [<app-name> | --app <name> | --pid <pid> | --bundle <bundle-id>]"],
        examples: [
            "steve COMMAND --app Safari",
            "steve COMMAND --pid 1234"
        ]
    ),
    CommandHelp(
        name: "window",
        summary: "Operate on a window by id.",
        usage: [
            "steve COMMAND focus <ax-window-id>",
            "steve COMMAND minimize <ax-window-id>",
            "steve COMMAND fullscreen <ax-window-id>",
            "steve COMMAND resize <ax-window-id> <width> <height>",
            "steve COMMAND move <ax-window-id> <x> <y>"
        ],
        examples: [
            "steve COMMAND focus ax://win/123",
            "steve COMMAND resize ax://win/123 800 600",
            "steve COMMAND move ax://win/123 100 100"
        ]
    ),
    CommandHelp(
        name: "menus",
        summary: "Print the menu bar tree for a target app.",
        usage: ["steve COMMAND [<app-name> | --app <name> | --pid <pid> | --bundle <bundle-id>]"],
        examples: ["steve COMMAND --app \"System Settings\""]
    ),
    CommandHelp(
        name: "menu",
        summary: "Click a menu path or list menu children.",
        usage: [
            "steve COMMAND [--contains] [--case-insensitive] [--normalize-ellipsis] <path...>",
            "steve COMMAND --list [--contains] [--case-insensitive] [--normalize-ellipsis] <path...>"
        ],
        examples: [
            "steve COMMAND File New",
            "steve COMMAND --contains --case-insensitive \"settings...\"",
            "steve COMMAND --list File"
        ]
    ),
    CommandHelp(
        name: "statusbar",
        summary: "List, click, or inspect status bar items.",
        usage: [
            "steve COMMAND --list",
            "steve COMMAND [--contains] [--case-insensitive] [--normalize-ellipsis] <item>",
            "steve COMMAND --menu [--contains] [--case-insensitive] [--normalize-ellipsis] <item>"
        ],
        examples: [
            "steve COMMAND --list",
            "steve COMMAND \"Wi-Fi\"",
            "steve COMMAND --menu --contains Battery"
        ]
    ),
    CommandHelp(
        name: "snapshot",
        summary: "Capture an accessibility snapshot as structured data.",
        usage: ["steve COMMAND [--depth <n>] [-o <path> | --output <path>]"],
        examples: [
            "steve COMMAND --app \"System Settings\" --output before.json",
            "steve COMMAND --depth 3"
        ]
    ),
    CommandHelp(
        name: "diff",
        summary: "Diff two snapshot files.",
        usage: ["steve COMMAND <before.json> <after.json>"],
        examples: ["steve COMMAND before.json after.json"]
    ),
    CommandHelp(
        name: "screenshot",
        summary: "Capture the focused window or a specific element as PNG.",
        usage: [
            "steve COMMAND [<app-name> | --app <name> | --pid <pid> | --bundle <bundle-id>] [-o <path> | --output <path>]",
            "steve COMMAND --element <ax-element-id> [-o <path> | --output <path>]"
        ],
        examples: [
            "steve COMMAND --app Safari --output safari.png",
            "steve COMMAND --element ax://1234/0.2 --output element.png"
        ]
    )
]

let visibleCommands = commandHelpEntries.flatMap { entry in
    entry.visibleNames
}

func commandHelpEntry(named command: String) -> CommandHelp? {
    commandHelpEntries.first(where: { $0.visibleNames.contains(command) })
}

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
    let commandWidth = commandHelpEntries.map(\.name.count).max() ?? 0
    var lines = [
        "steve - Mac UI Automation CLI",
        "",
        "Usage:",
        "  steve <command> [options]",
        "  steve help <command>",
        "",
        "Commands:"
    ]
    for entry in commandHelpEntries {
        let paddedName = entry.name.padding(toLength: commandWidth, withPad: " ", startingAt: 0)
        let aliasSuffix = entry.aliases.isEmpty ? "" : " (aliases: \(entry.aliases.joined(separator: ", ")))"
        lines.append("  \(paddedName)  \(entry.summary)\(aliasSuffix)")
    }
    lines.append("")
    lines.append("Global options:")
    lines.append(contentsOf: globalOptionHelpLines.map { "  \($0)" })
    lines.append("")
    lines.append("Run `steve <command> --help` for command-specific usage.")
    return lines.joined(separator: "\n")
}

func commandUsage(_ command: String) -> String? {
    guard let entry = commandHelpEntry(named: command) else {
        return nil
    }
    let displayName = command
    var lines = [
        "steve \(displayName) - \(entry.summary)"
    ]
    if displayName != entry.name {
        lines.append("")
        lines.append("Alias of `\(entry.name)`.")
    } else if !entry.aliases.isEmpty {
        lines.append("")
        lines.append("Aliases: \(entry.aliases.joined(separator: ", "))")
    }
    lines.append("")
    lines.append("Usage:")
    lines.append(contentsOf: entry.usage.map { "  \($0.replacingOccurrences(of: "COMMAND", with: displayName))" })
    if !entry.examples.isEmpty {
        lines.append("")
        lines.append("Examples:")
        lines.append(contentsOf: entry.examples.map { "  \($0.replacingOccurrences(of: "COMMAND", with: displayName))" })
    }
    lines.append("")
    lines.append("Global options:")
    lines.append(contentsOf: globalOptionHelpLines.map { "  \($0)" })
    return lines.joined(separator: "\n")
}

func isHelpFlag(_ arg: String) -> Bool {
    arg == "--help" || arg == "-h"
}

func hasCommandHelpFlag(_ args: [String]) -> Bool {
    args.contains(where: isHelpFlag)
}

func runCLI(args: [String]) -> Int32 {
    var args = args
    if args.isEmpty {
        print(usage())
        return UitoolExit.success.rawValue
    }

    let first = args.removeFirst()
    if isHelpFlag(first) {
        print(usage())
        return UitoolExit.success.rawValue
    }

    if first == "help" {
        guard let requested = args.first, !isHelpFlag(requested) else {
            print(usage())
            return UitoolExit.success.rawValue
        }
        if let help = commandUsage(requested) {
            print(help)
            return UitoolExit.success.rawValue
        }
        Output.error("Unknown command: \(requested)")
        return UitoolExit.invalidArguments.rawValue
    }

    let command = first
    let (options, error) = parseGlobalOptions(&args)
    Output.configure(format: options.format)
    Trace.configure(enabled: options.traceJSONL, path: options.tracePath)
    if let error {
        Output.error(error, quiet: options.quiet)
        return UitoolExit.invalidArguments.rawValue
    }

    if hasCommandHelpFlag(args) {
        if let help = commandUsage(command) {
            print(help)
            return UitoolExit.success.rawValue
        }
        Output.error("Unknown command: \(command)", quiet: options.quiet)
        return UitoolExit.invalidArguments.rawValue
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
        Output.error("Unknown command: \(command)", quiet: options.quiet)
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
