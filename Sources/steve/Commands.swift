import AppKit
import ApplicationServices
import Foundation

struct CommandContext {
    var options: GlobalOptions
}

struct Commands {
    static func apps(ctx: CommandContext) -> Int32 {
        let apps = NSWorkspace.shared.runningApplications
        let data = apps.map { app in
            [
                "name": app.localizedName ?? "",
                "pid": Int(app.processIdentifier),
                "bundleId": app.bundleIdentifier ?? ""
            ]
        }
        JSON.ok(data, quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func focus(ctx: CommandContext, args: [String]) -> Int32 {
        var options = ctx.options
        if !hasTarget(options), let name = firstPositionalArg(args) {
            options.appName = name
        }
        guard let app = AXHelper.runningApp(options: options) else {
            JSON.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let ok = app.activate(options: [.activateIgnoringOtherApps])
        if ok {
            JSON.ok(["pid": Int(app.processIdentifier)], quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        JSON.error("Failed to focus app", quiet: ctx.options.quiet)
        return UitoolExit.appNotFound.rawValue
    }

    static func launch(ctx: CommandContext, args: [String]) -> Int32 {
        guard let bundleId = firstPositionalArg(args) else {
            JSON.error("Missing bundle identifier", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        let wait = args.contains("--wait")
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            JSON.error("Failed to launch app", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        var launched: NSRunningApplication?
        var launchError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
            launched = app
            launchError = error
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + ctx.options.timeout)
        if launched == nil, launchError == nil {
            launched = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
        }
        guard let app = launched else {
            JSON.error("Failed to launch app", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        if wait {
            let deadline = Date().addingTimeInterval(ctx.options.timeout)
            while Date() < deadline {
                if AXHelper.ensureTrusted() {
                    let element = AXHelper.appElement(for: app)
                    if AXHelper.attribute(element, AXConst.Attr.windows) as [AXUIElement]? != nil {
                        JSON.ok(["pid": Int(app.processIdentifier)], quiet: ctx.options.quiet)
                        return UitoolExit.success.rawValue
                    }
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            JSON.error("Timeout waiting for app", quiet: ctx.options.quiet)
            return UitoolExit.timeout.rawValue
        }
        JSON.ok(["pid": Int(app.processIdentifier)], quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func quit(ctx: CommandContext, args: [String]) -> Int32 {
        let force = args.contains("--force")
        var options = ctx.options
        if !hasTarget(options), let name = firstPositionalArg(args) {
            options.appName = name
        }
        guard let app = AXHelper.runningApp(options: options) else {
            JSON.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let ok = force ? app.forceTerminate() : app.terminate()
        if ok {
            JSON.ok(["pid": Int(app.processIdentifier)], quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        JSON.error("Failed to quit app", quiet: ctx.options.quiet)
        return UitoolExit.appNotFound.rawValue
    }

    static func elements(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            JSON.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let depth = parseIntFlag(args, "--depth") ?? 3
        let windowTitle = parseStringFlag(args, "--window")
        return withResolvedRoot(options: ctx.options, windowTitle: windowTitle, quiet: ctx.options.quiet) { app, root, path in
            let info = AXHelper.elementInfo(element: root, pid: app.processIdentifier, path: path, depth: depth)
            JSON.ok([info], quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
    }

    static func find(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            JSON.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let options = parseFindOptions(args)
        return withResolvedRoot(options: ctx.options, windowTitle: options.windowTitle, quiet: ctx.options.quiet) { app, root, path in
            let matches = AXHelper.findElements(root: root, rootPath: path, role: options.role, title: options.title, identifier: options.identifier, text: options.text)
            if matches.isEmpty {
                JSON.error("Element not found", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            if options.shouldClick {
                let targetPath = matches[0].1
                var target = matches[0].0
                if let ancestorRole = options.ancestorRole {
                    if let ancestor = AXHelper.ancestor(forPath: targetPath, in: AXHelper.appElement(for: app), role: ancestorRole) {
                        target = ancestor
                    } else {
                        JSON.error("Ancestor not found", quiet: ctx.options.quiet)
                        return UitoolExit.notFound.rawValue
                    }
                }
                if !tryClick(target) {
                    JSON.error("Failed to click element", quiet: ctx.options.quiet)
                    return UitoolExit.notFound.rawValue
                }
            }
            let data = matches.map { element, matchPath in
                AXHelper.elementInfo(element: element, pid: app.processIdentifier, path: matchPath, depth: 0)
            }
            JSON.ok(data, quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
    }

    static func elementAt(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            JSON.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        guard args.count >= 2, let x = Double(args[0]), let y = Double(args[1]) else {
            JSON.error("Usage: element-at <x> <y>", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        let system = AXHelper.systemWideElement()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(system, Float(x), Float(y), &element)
        guard result == .success, let found = element else {
            JSON.error("Element not found", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        var pid: pid_t = 0
        AXUIElementGetPid(found, &pid)
        let appElement = AXUIElementCreateApplication(pid)
        let path = AXHelper.findPath(to: found, in: appElement) ?? [0]
        let info = AXHelper.elementInfo(element: found, pid: pid, path: path, depth: 0)
        JSON.ok([info], quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func click(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            JSON.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        if let id = args.first, id.hasPrefix("ax://") {
            guard let element = AXHelper.elementFromId(id) else {
                JSON.error("Element not found", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            if press(element: element) {
                JSON.ok(quiet: ctx.options.quiet)
                return UitoolExit.success.rawValue
            }
            if let frame = AXHelper.frame(of: element) {
                EventHelper.click(at: CGPoint(x: frame.midX, y: frame.midY))
                JSON.ok(quiet: ctx.options.quiet)
                return UitoolExit.success.rawValue
            }
            JSON.error("Failed to click element", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        let role = parseStringFlag(args, "--role")
        let title = parseStringFlag(args, "--title")
        let text = parseStringFlag(args, "--text")
        let identifier = parseStringFlag(args, "--identifier")
        let windowTitle = parseStringFlag(args, "--window")
        return withResolvedRoot(options: ctx.options, windowTitle: windowTitle, quiet: ctx.options.quiet) { _, root, path in
            let matches = AXHelper.findElements(root: root, rootPath: path, role: role, title: title, identifier: identifier, text: text)
            guard let target = matches.first?.0 else {
                JSON.error("Element not found", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            if tryClick(target) {
                JSON.ok(quiet: ctx.options.quiet)
                return UitoolExit.success.rawValue
            }
            JSON.error("Failed to click element", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
    }

    static func clickAt(ctx: CommandContext, args: [String]) -> Int32 {
        guard args.count >= 2, let x = Double(args[0]), let y = Double(args[1]) else {
            JSON.error("Usage: click-at <x> <y>", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        let doubleClick = args.contains("--double")
        let right = args.contains("--right")
        EventHelper.click(at: CGPoint(x: x, y: y), button: right ? .right : .left, clickCount: doubleClick ? 2 : 1)
        JSON.ok(quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func typeText(ctx: CommandContext, args: [String]) -> Int32 {
        guard let text = args.first else {
            JSON.error("Usage: type <text>", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        let delay = parseIntFlag(args, "--delay") ?? 0
        EventHelper.type(text: text, delayMs: delay)
        JSON.ok(quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func key(ctx: CommandContext, args: [String]) -> Int32 {
        if args.contains("--list") {
            JSON.ok(["keys": KeyCodes.supportedKeys()], quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        if let rawIndex = args.firstIndex(of: "--raw") {
            guard rawIndex + 1 < args.count, let raw = Int(args[rawIndex + 1]) else {
                JSON.error("Usage: key --raw <keycode>", quiet: ctx.options.quiet)
                return UitoolExit.invalidArguments.rawValue
            }
            let shortcut = "raw:\(raw)"
            if EventHelper.keyShortcut(shortcut) {
                JSON.ok(quiet: ctx.options.quiet)
                return UitoolExit.success.rawValue
            }
            JSON.error("Unknown key", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        guard let keyString = args.first else {
            JSON.error("Usage: key <shortcut>", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        if EventHelper.keyShortcut(keyString) {
            JSON.ok(quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        JSON.error("Unknown key", quiet: ctx.options.quiet)
        return UitoolExit.invalidArguments.rawValue
    }

    static func keys(ctx: CommandContext) -> Int32 {
        JSON.ok(["keys": KeyCodes.supportedKeys()], quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func setValue(ctx: CommandContext, args: [String]) -> Int32 {
        guard args.count >= 2 else {
            JSON.error("Usage: set-value <id> <value>", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        let id = args[0]
        let value = args[1]
        guard let element = AXHelper.elementFromId(id) else {
            JSON.error("Element not found", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        let result = AXUIElementSetAttributeValue(element, AXConst.Attr.value, value as CFTypeRef)
        if result == .success {
            JSON.ok(quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        JSON.error("Failed to set value", quiet: ctx.options.quiet)
        return UitoolExit.notFound.rawValue
    }

    static func scroll(ctx: CommandContext, args: [String]) -> Int32 {
        let direction = args.first ?? "down"
        let amount = parseIntFlag(args, "--amount") ?? 1
        let delta = direction == "up" ? amount * 10 : -amount * 10
        if let elementId = parseStringFlag(args, "--element"), let element = AXHelper.elementFromId(elementId) {
            let action: CFString = direction == "up" ? AXConst.Action.scrollUp : AXConst.Action.scrollDown
            let result = AXUIElementPerformAction(element, action)
            if result == .success {
                JSON.ok(quiet: ctx.options.quiet)
                return UitoolExit.success.rawValue
            }
        }
        EventHelper.scroll(deltaY: delta)
        JSON.ok(quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func exists(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            JSON.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let query = parseQueryOptions(args)
        return withResolvedRoot(options: ctx.options, windowTitle: query.windowTitle, quiet: ctx.options.quiet) { _, root, path in
            let matches = AXHelper.findElements(root: root, rootPath: path, role: query.role, title: query.title, identifier: query.identifier, text: query.text)
            if matches.isEmpty {
                JSON.error("Element not found", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            JSON.ok(quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
    }

    static func wait(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            JSON.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let query = parseQueryOptions(args)
        let gone = args.contains("--gone")
        let timeout = TimeInterval(parseIntFlag(args, "--timeout") ?? Int(ctx.options.timeout))
        guard let app = AXHelper.runningApp(options: ctx.options) else {
            JSON.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let matches: [(AXUIElement, [Int])]
            let appElement = AXHelper.appElement(for: app)
            if let windowTitle = query.windowTitle {
                if let (root, path) = findWindowRoot(in: appElement, windowTitle: windowTitle) {
                    matches = AXHelper.findElements(root: root, rootPath: path, role: query.role, title: query.title, identifier: query.identifier, text: query.text)
                } else {
                    matches = []
                }
            } else {
                matches = AXHelper.findElements(root: appElement, rootPath: [0], role: query.role, title: query.title, identifier: query.identifier, text: query.text)
            }
            let found = !matches.isEmpty
            if gone {
                if !found {
                    JSON.ok(quiet: ctx.options.quiet)
                    return UitoolExit.success.rawValue
                }
            } else {
                if found {
                    JSON.ok(quiet: ctx.options.quiet)
                    return UitoolExit.success.rawValue
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        JSON.error("Timeout", quiet: ctx.options.quiet)
        return UitoolExit.timeout.rawValue
    }

    static func assert(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            JSON.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let query = parseQueryOptions(args)
        let checkEnabled = args.contains("--enabled")
        let checkChecked = args.contains("--checked")
        let expectedValue = parseStringFlag(args, "--value")
        return withResolvedRoot(options: ctx.options, windowTitle: query.windowTitle, quiet: ctx.options.quiet) { _, root, path in
            guard let element = AXHelper.findElements(root: root, rootPath: path, role: query.role, title: query.title, identifier: query.identifier, text: query.text).first?.0 else {
                JSON.error("Element not found", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            if checkEnabled {
                if AXHelper.boolAttribute(element, AXConst.Attr.enabled) != true {
                    JSON.error("Expected enabled", quiet: ctx.options.quiet)
                    return UitoolExit.notFound.rawValue
                }
            }
            if checkChecked {
                let checked = AXHelper.boolAttribute(element, AXConst.Attr.value) ?? AXHelper.boolAttribute(element, AXConst.Attr.selected)
                if checked != true {
                    JSON.error("Expected checked", quiet: ctx.options.quiet)
                    return UitoolExit.notFound.rawValue
                }
            }
            if let expectedValue {
                let actual: String? = AXHelper.attribute(element, AXConst.Attr.value)
                if actual != expectedValue {
                    JSON.error("Value mismatch", quiet: ctx.options.quiet)
                    return UitoolExit.notFound.rawValue
                }
            }
            JSON.ok(quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
    }

    static func windows(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            JSON.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        guard let app = AXHelper.runningApp(options: ctx.options) else {
            JSON.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let appElement = AXHelper.appElement(for: app)
        let windows: [AXUIElement] = AXHelper.attribute(appElement, AXConst.Attr.windows) ?? []
        let data = windows.map { window -> [String: Any] in
            var dict: [String: Any] = [:]
            if let title: String = AXHelper.attribute(window, AXConst.Attr.title) { dict["title"] = title }
            if let frame = AXHelper.frame(of: window) {
                dict["frame"] = ["x": frame.origin.x, "y": frame.origin.y, "width": frame.size.width, "height": frame.size.height]
            }
            if let number: NSNumber = AXHelper.attribute(window, AXConst.Attr.windowNumber) {
                dict["id"] = "ax://win/\(number.intValue)"
            }
            return dict
        }
        JSON.ok(data, quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func windowCommand(ctx: CommandContext, args: [String]) -> Int32 {
        guard args.count >= 2 else {
            JSON.error("Usage: window <action> <id> [args]", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        guard AXHelper.ensureTrusted() else {
            JSON.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let action = args[0]
        let id = args[1]
        guard let window = windowFromId(id, options: ctx.options) else {
            JSON.error("Window not found", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        switch action {
        case "focus":
            _ = AXUIElementSetAttributeValue(window, AXConst.Attr.main, kCFBooleanTrue)
            _ = AXUIElementSetAttributeValue(window, AXConst.Attr.focused, kCFBooleanTrue)
        case "minimize":
            _ = AXUIElementSetAttributeValue(window, AXConst.Attr.minimized, kCFBooleanTrue)
        case "fullscreen":
            _ = AXUIElementSetAttributeValue(window, AXConst.Attr.fullScreen, kCFBooleanTrue)
        case "resize":
            guard args.count >= 4, let w = Double(args[2]), let h = Double(args[3]) else {
                JSON.error("Usage: window resize <id> <width> <height>", quiet: ctx.options.quiet)
                return UitoolExit.invalidArguments.rawValue
            }
            var size = CGSize(width: w, height: h)
            let axValue = AXValueCreate(.cgSize, &size)!
            _ = AXUIElementSetAttributeValue(window, AXConst.Attr.size, axValue)
        case "move":
            guard args.count >= 4, let x = Double(args[2]), let y = Double(args[3]) else {
                JSON.error("Usage: window move <id> <x> <y>", quiet: ctx.options.quiet)
                return UitoolExit.invalidArguments.rawValue
            }
            var point = CGPoint(x: x, y: y)
            let axValue = AXValueCreate(.cgPoint, &point)!
            _ = AXUIElementSetAttributeValue(window, AXConst.Attr.position, axValue)
        default:
            JSON.error("Unknown window action", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        JSON.ok(quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func menus(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            JSON.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        guard let app = AXHelper.runningApp(options: ctx.options) else {
            JSON.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let appElement = AXHelper.appElement(for: app)
        guard let menuBar: AXUIElement = AXHelper.attribute(appElement, AXConst.Attr.menuBar) else {
            JSON.error("Menu bar not found", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        let data = menuTree(menuBar, depth: 3)
        JSON.ok(data, quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func menu(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            JSON.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        guard let app = AXHelper.runningApp(options: ctx.options) else {
            JSON.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let options = parseMenuOptions(args)
        if options.path.isEmpty, !options.listChildren {
            JSON.error("Usage: menu <path...>", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        let appElement = AXHelper.appElement(for: app)
        guard let menuBar: AXUIElement = AXHelper.attribute(appElement, AXConst.Attr.menuBar) else {
            JSON.error("Menu bar not found", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        if options.listChildren {
            guard let container = findMenuContainer(menuBar: menuBar, path: options.path, match: options.match) else {
                JSON.error("Menu item not found", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            let children = menuChildren(of: container).map { child -> [String: Any] in
                var dict: [String: Any] = [:]
                if let title = AXHelper.stringAttribute(child, AXConst.Attr.title) { dict["title"] = title }
                if let role = AXHelper.role(of: child) { dict["role"] = role }
                return dict
            }
            JSON.ok(children, quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        if let target = findMenuItem(menuBar: menuBar, path: options.path, match: options.match) {
            if press(element: target) {
                JSON.ok(quiet: ctx.options.quiet)
                return UitoolExit.success.rawValue
            }
        }
        JSON.error("Menu item not found", quiet: ctx.options.quiet)
        return UitoolExit.notFound.rawValue
    }

    static func statusbar(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            JSON.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let options = parseStatusBarOptions(args)
        guard let menuBar = systemMenuBar() else {
            JSON.error("Menu bar not found", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        let items = statusBarItems(in: menuBar)
        if options.listItems {
            let data = items.map { item -> [String: Any] in
                var dict: [String: Any] = [:]
                if let title = AXHelper.stringAttribute(item, AXConst.Attr.title) { dict["title"] = title }
                if let desc = AXHelper.stringAttribute(item, AXConst.Attr.description) { dict["description"] = desc }
                if let role = AXHelper.role(of: item) { dict["role"] = role }
                if let frame = AXHelper.frame(of: item) {
                    dict["frame"] = ["x": frame.origin.x, "y": frame.origin.y, "width": frame.size.width, "height": frame.size.height]
                }
                return dict
            }
            JSON.ok(data, quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        guard let name = options.name else {
            JSON.error("Usage: statusbar --list | statusbar <item> | statusbar --menu <item>", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        guard let target = findStatusBarItem(items, name: name, match: options.match) else {
            JSON.error("Status bar item not found", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        if options.listMenu {
            if AXHelper.attribute(target, AXConst.Attr.menu) as AXUIElement? == nil {
                _ = press(element: target)
                Thread.sleep(forTimeInterval: 0.1)
            }
            guard let menu: AXUIElement = AXHelper.attribute(target, AXConst.Attr.menu) else {
                JSON.error("Menu not found", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            let children = AXHelper.children(of: menu).map { child -> [String: Any] in
                var dict: [String: Any] = [:]
                if let title = AXHelper.stringAttribute(child, AXConst.Attr.title) { dict["title"] = title }
                if let role = AXHelper.role(of: child) { dict["role"] = role }
                return dict
            }
            JSON.ok(children, quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        if press(element: target) {
            JSON.ok(quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        JSON.error("Failed to click status bar item", quiet: ctx.options.quiet)
        return UitoolExit.notFound.rawValue
    }

    static func screenshot(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            JSON.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let output = parseStringFlag(args, "-o") ?? parseStringFlag(args, "--output")
        if let elementId = parseStringFlag(args, "--element") {
            guard let element = AXHelper.elementFromId(elementId) else {
                JSON.error("Element not found", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            guard let frame = AXHelper.frame(of: element) else {
                JSON.error("Element has no frame", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            guard let image = capture(rect: frame) else {
                JSON.error("Failed to capture", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            return writeImage(image, output: output, quiet: ctx.options.quiet)
        }
        guard let app = AXHelper.runningApp(options: ctx.options) else {
            JSON.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        if let window = focusedWindow(for: app), let number: NSNumber = AXHelper.attribute(window, AXConst.Attr.windowNumber) {
            if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(number.uint32Value), [.boundsIgnoreFraming]) {
                return writeCGImage(image, output: output, quiet: ctx.options.quiet)
            }
        }
        JSON.error("Failed to capture window", quiet: ctx.options.quiet)
        return UitoolExit.notFound.rawValue
    }
}

struct EventHelper {
    static func toCGEventPoint(_ point: CGPoint) -> CGPoint {
        guard let screen = NSScreen.main else { return point }
        return CGPoint(x: point.x, y: screen.frame.height - point.y)
    }

    static func click(at point: CGPoint, button: CGMouseButton = .left, clickCount: Int = 1) {
        let converted = toCGEventPoint(point)
        let down = CGEvent(mouseEventSource: nil, mouseType: button == .left ? .leftMouseDown : .rightMouseDown, mouseCursorPosition: converted, mouseButton: button)
        down?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        let up = CGEvent(mouseEventSource: nil, mouseType: button == .left ? .leftMouseUp : .rightMouseUp, mouseCursorPosition: converted, mouseButton: button)
        up?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static func type(text: String, delayMs: Int) {
        for codeUnit in text.utf16 {
            var c = codeUnit
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            if delayMs > 0 { Thread.sleep(forTimeInterval: Double(delayMs) / 1000.0) }
        }
    }

    static func keyShortcut(_ shortcut: String) -> Bool {
        let parts = shortcut.split(separator: "+").map { $0.lowercased() }
        var flags: CGEventFlags = []
        var keyPart: String?
        for part in parts {
            switch part {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "alt", "option": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            case "fn", "function": flags.insert(.maskSecondaryFn)
            default: keyPart = String(part)
            }
        }
        guard let keyPart else { return false }
        let keyCode: CGKeyCode?
        if keyPart.hasPrefix("raw:") {
            let rawString = String(keyPart.dropFirst(4))
            if let raw = Int(rawString) {
                keyCode = CGKeyCode(raw)
            } else {
                keyCode = nil
            }
        } else {
            keyCode = KeyCodes.keyCode(for: keyPart)
        }
        guard let keyCode else { return false }
        let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        return true
    }

    static func scroll(deltaY: Int) {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(deltaY), wheel2: 0, wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }
}

func press(element: AXUIElement) -> Bool {
    AXUIElementPerformAction(element, AXConst.Action.press) == .success
}

func tryClick(_ element: AXUIElement) -> Bool {
    if press(element: element) { return true }
    guard let frame = AXHelper.frame(of: element) else { return false }
    EventHelper.click(at: CGPoint(x: frame.midX, y: frame.midY))
    return true
}

func parseStringFlag(_ args: [String], _ flag: String) -> String? {
    guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
    return args[idx + 1]
}

func parseIntFlag(_ args: [String], _ flag: String) -> Int? {
    guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
    return Int(args[idx + 1])
}

struct FindOptions {
    var role: String?
    var title: String?
    var text: String?
    var identifier: String?
    var windowTitle: String?
    var ancestorRole: String?
    var shouldClick = false
}

struct QueryOptions {
    var role: String?
    var title: String?
    var text: String?
    var identifier: String?
    var windowTitle: String?
}

struct MenuMatchOptions {
    var contains = false
    var caseInsensitive = false
    var normalizeEllipsis = false
}

struct MenuOptions {
    var path: [String] = []
    var match = MenuMatchOptions()
    var listChildren = false
}

struct StatusBarOptions {
    var name: String?
    var match = MenuMatchOptions()
    var listItems = false
    var listMenu = false
}

func parseFindOptions(_ args: [String]) -> FindOptions {
    var options = FindOptions()
    var i = 0
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--role":
            if i + 1 < args.count { options.role = args[i + 1] }
            i += 2
        case "--title":
            if i + 1 < args.count { options.title = args[i + 1] }
            i += 2
        case "--text":
            if i + 1 < args.count { options.text = args[i + 1] }
            i += 2
        case "--identifier":
            if i + 1 < args.count { options.identifier = args[i + 1] }
            i += 2
        case "--window":
            if i + 1 < args.count { options.windowTitle = args[i + 1] }
            i += 2
        case "--ancestor-role":
            if i + 1 < args.count { options.ancestorRole = args[i + 1] }
            i += 2
        case "--click":
            options.shouldClick = true
            i += 1
        default:
            if !arg.hasPrefix("-"),
               options.role == nil, options.title == nil, options.identifier == nil, options.text == nil {
                options.role = arg
            }
            i += 1
        }
    }
    return options
}

func parseQueryOptions(_ args: [String]) -> QueryOptions {
    QueryOptions(
        role: parseStringFlag(args, "--role"),
        title: parseStringFlag(args, "--title"),
        text: parseStringFlag(args, "--text"),
        identifier: parseStringFlag(args, "--identifier"),
        windowTitle: parseStringFlag(args, "--window")
    )
}

func parseMenuOptions(_ args: [String]) -> MenuOptions {
    var options = MenuOptions()
    var i = 0
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--contains":
            options.match.contains = true
            i += 1
        case "--case-insensitive":
            options.match.caseInsensitive = true
            i += 1
        case "--normalize-ellipsis":
            options.match.normalizeEllipsis = true
            i += 1
        case "--list":
            options.listChildren = true
            i += 1
        default:
            options.path.append(arg)
            i += 1
        }
    }
    return options
}

func parseStatusBarOptions(_ args: [String]) -> StatusBarOptions {
    var options = StatusBarOptions()
    var parts: [String] = []
    var i = 0
    while i < args.count {
        let arg = args[i]
        switch arg {
        case "--contains":
            options.match.contains = true
        case "--case-insensitive":
            options.match.caseInsensitive = true
        case "--normalize-ellipsis":
            options.match.normalizeEllipsis = true
        case "--list":
            options.listItems = true
        case "--menu":
            options.listMenu = true
        default:
            parts.append(arg)
        }
        i += 1
    }
    if !parts.isEmpty {
        options.name = parts.joined(separator: " ")
    }
    return options
}

func firstPositionalArg(_ args: [String]) -> String? {
    args.first { !$0.hasPrefix("-") }
}

func hasTarget(_ options: GlobalOptions) -> Bool {
    options.appName != nil || options.bundleId != nil || options.pid != nil
}

func focusedWindow(for app: NSRunningApplication) -> AXUIElement? {
    let appElement = AXHelper.appElement(for: app)
    if let focused: AXUIElement = AXHelper.attribute(appElement, AXConst.Attr.focusedWindow) {
        return focused
    }
    let windows: [AXUIElement] = AXHelper.attribute(appElement, AXConst.Attr.windows) ?? []
    return windows.first
}

func windowFromId(_ id: String, options: GlobalOptions) -> AXUIElement? {
    if id.hasPrefix("ax://win/") {
        let numString = id.replacingOccurrences(of: "ax://win/", with: "")
        guard let target = Int(numString), let app = AXHelper.runningApp(options: options) else { return nil }
        let appElement = AXHelper.appElement(for: app)
        let windows: [AXUIElement] = AXHelper.attribute(appElement, AXConst.Attr.windows) ?? []
        for window in windows {
            if let number: NSNumber = AXHelper.attribute(window, AXConst.Attr.windowNumber), number.intValue == target {
                return window
            }
        }
        return nil
    }
    return AXHelper.elementFromId(id)
}

enum RootResolution {
    case ok(NSRunningApplication, AXUIElement, [Int])
    case appNotFound
    case windowNotFound
}

func resolveRoot(options: GlobalOptions, windowTitle: String?) -> RootResolution {
    guard let app = AXHelper.runningApp(options: options) else { return .appNotFound }
    let appElement = AXHelper.appElement(for: app)
    guard let windowTitle else { return .ok(app, appElement, [0]) }
    if let (window, path) = findWindowRoot(in: appElement, windowTitle: windowTitle) {
        return .ok(app, window, path)
    }
    return .windowNotFound
}

func withResolvedRoot(options: GlobalOptions, windowTitle: String?, quiet: Bool, _ body: (NSRunningApplication, AXUIElement, [Int]) -> Int32) -> Int32 {
    switch resolveRoot(options: options, windowTitle: windowTitle) {
    case .appNotFound:
        JSON.error("App not found", quiet: quiet)
        return UitoolExit.appNotFound.rawValue
    case .windowNotFound:
        JSON.error("Window not found", quiet: quiet)
        return UitoolExit.notFound.rawValue
    case .ok(let app, let root, let path):
        return body(app, root, path)
    }
}

func findWindowRoot(in appElement: AXUIElement, windowTitle: String) -> (AXUIElement, [Int])? {
    let windows: [AXUIElement] = AXHelper.attribute(appElement, AXConst.Attr.windows) ?? []
    for window in windows {
        if let title = AXHelper.stringAttribute(window, AXConst.Attr.title),
           title.localizedCaseInsensitiveContains(windowTitle) {
            let path = AXHelper.findPath(to: window, in: appElement) ?? [0]
            return (window, path)
        }
    }
    return nil
}

func menuTree(_ element: AXUIElement, depth: Int) -> [[String: Any]] {
    guard depth > 0 else { return [] }
    let children = AXHelper.children(of: element)
    return children.map { child in
        var dict: [String: Any] = [:]
        if let title: String = AXHelper.attribute(child, AXConst.Attr.title) { dict["title"] = title }
        if let role = AXHelper.role(of: child) { dict["role"] = role }
        let sub = menuTree(child, depth: depth - 1)
        if !sub.isEmpty { dict["children"] = sub }
        return dict
    }
}

func normalizeMenuTitle(_ title: String, options: MenuMatchOptions) -> String {
    var value = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if options.normalizeEllipsis {
        value = value.replacingOccurrences(of: "…", with: "...")
    }
    let parts = value.split(whereSeparator: { $0.isWhitespace })
    value = parts.joined(separator: " ")
    if options.caseInsensitive {
        value = value.lowercased()
    }
    return value
}

func menuTitleMatches(_ candidate: String, _ query: String, options: MenuMatchOptions) -> Bool {
    let lhs = normalizeMenuTitle(candidate, options: options)
    let rhs = normalizeMenuTitle(query, options: options)
    if options.contains {
        return lhs.contains(rhs)
    }
    return lhs == rhs
}

func menuChildren(of element: AXUIElement) -> [AXUIElement] {
    if let menu: AXUIElement = AXHelper.attribute(element, AXConst.Attr.menu) {
        return AXHelper.children(of: menu)
    }
    return AXHelper.children(of: element)
}

func systemMenuBar() -> AXUIElement? {
    let system = AXHelper.systemWideElement()
    if let menuBar: AXUIElement = AXHelper.attribute(system, AXConst.Attr.menuBar) {
        return menuBar
    }
    if let app = AXHelper.frontmostApp() {
        let appElement = AXHelper.appElement(for: app)
        return AXHelper.attribute(appElement, AXConst.Attr.menuBar)
    }
    return nil
}

func statusBarItems(in menuBar: AXUIElement) -> [AXUIElement] {
    AXHelper.children(of: menuBar).filter { AXHelper.role(of: $0) == "AXMenuBarItem" }
}

func findStatusBarItem(_ items: [AXUIElement], name: String, match: MenuMatchOptions) -> AXUIElement? {
    for item in items {
        var candidates: [String] = []
        if let title = AXHelper.stringAttribute(item, AXConst.Attr.title) { candidates.append(title) }
        if let desc = AXHelper.stringAttribute(item, AXConst.Attr.description) { candidates.append(desc) }
        if candidates.contains(where: { menuTitleMatches($0, name, options: match) }) {
            return item
        }
    }
    return nil
}

func findMenuContainer(menuBar: AXUIElement, path: [String], match: MenuMatchOptions) -> AXUIElement? {
    if path.isEmpty { return menuBar }
    var currentElements = AXHelper.children(of: menuBar)
    var current: AXUIElement?
    for (index, name) in path.enumerated() {
        guard let matchElement = currentElements.first(where: {
            guard let title = AXHelper.stringAttribute($0, AXConst.Attr.title) else { return false }
            return menuTitleMatches(title, name, options: match)
        }) else { return nil }
        current = matchElement
        if index == path.count - 1 {
            return matchElement
        }
        currentElements = menuChildren(of: matchElement)
    }
    return current
}

func findMenuItem(menuBar: AXUIElement, path: [String], match: MenuMatchOptions) -> AXUIElement? {
    guard let container = findMenuContainer(menuBar: menuBar, path: path, match: match) else { return nil }
    return container
}

func capture(rect: CGRect) -> CGImage? {
    CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.boundsIgnoreFraming])
}

func writeImage(_ image: CGImage, output: String?, quiet: Bool) -> Int32 {
    if let output {
        return writeCGImage(image, output: output, quiet: quiet)
    }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        JSON.error("Failed to encode image", quiet: quiet)
        return UitoolExit.notFound.rawValue
    }
    FileHandle.standardOutput.write(data)
    return UitoolExit.success.rawValue
}

func writeCGImage(_ image: CGImage, output: String?, quiet: Bool) -> Int32 {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        JSON.error("Failed to encode image", quiet: quiet)
        return UitoolExit.notFound.rawValue
    }
    if let output {
        do {
            try data.write(to: URL(fileURLWithPath: output))
        } catch {
            JSON.error("Failed to write file", quiet: quiet)
            return UitoolExit.notFound.rawValue
        }
        JSON.ok(["path": output], quiet: quiet)
        return UitoolExit.success.rawValue
    }
    FileHandle.standardOutput.write(data)
    return UitoolExit.success.rawValue
}
