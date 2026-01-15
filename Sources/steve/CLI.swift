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
              type, key, set-value, scroll, exists, wait, assert, windows, window,
              menus, menu, screenshot

    Global options: --app, --pid, --bundle, --timeout, --verbose, --quiet
    """
}

func runCLI(args: [String]) -> Int32 {
    var args = args
    if args.isEmpty {
        JSON.error(usage())
        return UitoolExit.invalidArguments.rawValue
    }

    let command = args.removeFirst()
    let (options, error) = parseGlobalOptions(&args)
    if let error {
        JSON.error(error, quiet: options.quiet)
        return UitoolExit.invalidArguments.rawValue
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
