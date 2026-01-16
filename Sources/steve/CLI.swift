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
        default:
            i += 1
        }
    }
    return (options, nil)
}

func usage() -> String {
    """
    steve — Mac UI Automation CLI

    Commands: apps, focus, launch, quit, elements, find, element-at, click, click-at,
              type, key, keys, set-value, scroll, exists, wait, assert, windows, window,
              menus, menu, statusbar, screenshot

    Global options: --app, --pid, --bundle, --timeout, --verbose, --quiet
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
                   [--window <title>] [--ancestor-role <role>] [--click]
        """
    case "exists":
        return "steve exists [--role <role>] [--title <title>] [--text <text>] [--identifier <id>] [--window <title>]"
    case "wait":
        return "steve wait [--role <role>] [--title <title>] [--text <text>] [--identifier <id>] [--window <title>] [--gone] [--timeout <sec>]"
    case "assert":
        return "steve assert [--role <role>] [--title <title>] [--text <text>] [--identifier <id>] [--window <title>] [--enabled] [--checked] [--value <value>]"
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
    if let error {
        JSON.error(error, quiet: options.quiet)
        return UitoolExit.invalidArguments.rawValue
    }

    if hasHelpFlag(args), let help = commandUsage(command) {
        print(help)
        return UitoolExit.success.rawValue
    }

    let ctx = CommandContext(options: options)
    switch command {
    case "apps":
        return Commands.apps(ctx: ctx)
    case "focus":
        return Commands.focus(ctx: ctx, args: args)
    case "launch":
        return Commands.launch(ctx: ctx, args: args)
    case "quit":
        return Commands.quit(ctx: ctx, args: args)
    case "elements":
        return Commands.elements(ctx: ctx, args: args)
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
    case "assert":
        return Commands.assert(ctx: ctx, args: args)
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
    case "screenshot":
        return Commands.screenshot(ctx: ctx, args: args)
    case "--help", "help", "-h":
        JSON.ok(["usage": usage()], quiet: options.quiet)
        return UitoolExit.success.rawValue
    default:
        JSON.error("Unknown command", quiet: options.quiet)
        return UitoolExit.invalidArguments.rawValue
    }
}
