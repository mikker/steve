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
        guard let app = AXHelper.runningApp(options: ctx.options) else {
            JSON.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let root = AXHelper.appElement(for: app)
        let info = AXHelper.elementInfo(element: root, pid: app.processIdentifier, path: [0], depth: depth)
        JSON.ok([info], quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func find(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            JSON.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        var role = parseStringFlag(args, "--role")
        let title = parseStringFlag(args, "--title")
        let identifier = parseStringFlag(args, "--identifier")
        if role == nil, title == nil, identifier == nil {
            role = args.first
        }
        guard let app = AXHelper.runningApp(options: ctx.options) else {
            JSON.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let root = AXHelper.appElement(for: app)
        let matches = AXHelper.findElements(root: root, role: role, title: title, identifier: identifier)
        let data = matches.map { element, path in
            AXHelper.elementInfo(element: element, pid: app.processIdentifier, path: path, depth: 0)
        }
        JSON.ok(data, quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
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
        let identifier = parseStringFlag(args, "--identifier")
        guard let app = AXHelper.runningApp(options: ctx.options) else {
            JSON.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let root = AXHelper.appElement(for: app)
        let matches = AXHelper.findElements(root: root, role: role, title: title, identifier: identifier)
        guard let target = matches.first?.0 else {
            JSON.error("Element not found", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        if press(element: target) {
            JSON.ok(quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        if let frame = AXHelper.frame(of: target) {
            EventHelper.click(at: CGPoint(x: frame.midX, y: frame.midY))
            JSON.ok(quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        JSON.error("Failed to click element", quiet: ctx.options.quiet)
        return UitoolExit.notFound.rawValue
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
        let role = parseStringFlag(args, "--role")
        let title = parseStringFlag(args, "--title")
        let identifier = parseStringFlag(args, "--identifier")
        guard let app = AXHelper.runningApp(options: ctx.options) else {
            JSON.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let root = AXHelper.appElement(for: app)
        let matches = AXHelper.findElements(root: root, role: role, title: title, identifier: identifier)
        if matches.isEmpty {
            JSON.error("Element not found", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        JSON.ok(quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func wait(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            JSON.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let role = parseStringFlag(args, "--role")
        let title = parseStringFlag(args, "--title")
        let identifier = parseStringFlag(args, "--identifier")
        let gone = args.contains("--gone")
        let timeout = TimeInterval(parseIntFlag(args, "--timeout") ?? Int(ctx.options.timeout))
        guard let app = AXHelper.runningApp(options: ctx.options) else {
            JSON.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let root = AXHelper.appElement(for: app)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let matches = AXHelper.findElements(root: root, role: role, title: title, identifier: identifier)
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
        let role = parseStringFlag(args, "--role")
        let title = parseStringFlag(args, "--title")
        let identifier = parseStringFlag(args, "--identifier")
        let checkEnabled = args.contains("--enabled")
        let checkChecked = args.contains("--checked")
        let expectedValue = parseStringFlag(args, "--value")
        guard let app = AXHelper.runningApp(options: ctx.options) else {
            JSON.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let root = AXHelper.appElement(for: app)
        guard let element = AXHelper.findElements(root: root, role: role, title: title, identifier: identifier).first?.0 else {
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
        guard !args.isEmpty else {
            JSON.error("Usage: menu <path...>", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        let appElement = AXHelper.appElement(for: app)
        guard let menuBar: AXUIElement = AXHelper.attribute(appElement, AXConst.Attr.menuBar) else {
            JSON.error("Menu bar not found", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        if let target = findMenuItem(menuBar: menuBar, path: args) {
            if press(element: target) {
                JSON.ok(quiet: ctx.options.quiet)
                return UitoolExit.success.rawValue
            }
        }
        JSON.error("Menu item not found", quiet: ctx.options.quiet)
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
            default: keyPart = String(part)
            }
        }
        guard let keyPart, let keyCode = KeyCodes.keyCode(for: keyPart) else { return false }
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

func parseStringFlag(_ args: [String], _ flag: String) -> String? {
    guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
    return args[idx + 1]
}

func parseIntFlag(_ args: [String], _ flag: String) -> Int? {
    guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
    return Int(args[idx + 1])
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

func findMenuItem(menuBar: AXUIElement, path: [String]) -> AXUIElement? {
    var currentElements = AXHelper.children(of: menuBar)
    for (index, name) in path.enumerated() {
        guard let match = currentElements.first(where: { (AXHelper.title(of: $0) ?? "") == name }) else { return nil }
        if index == path.count - 1 { return match }
        if let menu: AXUIElement = AXHelper.attribute(match, AXConst.Attr.menu) {
            currentElements = AXHelper.children(of: menu)
        } else {
            currentElements = AXHelper.children(of: match)
        }
    }
    return nil
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
