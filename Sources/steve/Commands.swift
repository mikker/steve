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
                "bundleId": app.bundleIdentifier ?? "",
                "appPath": AXHelper.resolvedPath(app.bundleURL?.path) ?? "",
                "executablePath": AXHelper.resolvedPath(app.executableURL?.path) ?? "",
                "frontmost": app.processIdentifier == AXHelper.frontmostApp()?.processIdentifier
            ]
        }
        Output.ok(data, quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func resolve(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let options = optionsWithPositionalTarget(ctx.options, args: args)
        guard let app = AXHelper.runningApp(options: options) else {
            Output.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let data = resolvedTargetData(app)
        Trace.log(["event": "target.resolved", "target": data])
        Output.ok(data, quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func focus(ctx: CommandContext, args: [String]) -> Int32 {
        let options = optionsWithPositionalTarget(ctx.options, args: args)
        guard let app = AXHelper.runningApp(options: options) else {
            Output.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let ok = app.activate(options: [.activateIgnoringOtherApps])
        if ok {
            Output.ok(["pid": Int(app.processIdentifier)], quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        Output.error("Failed to focus app", quiet: ctx.options.quiet)
        return UitoolExit.appNotFound.rawValue
    }

    static func focused(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let options = optionsWithPositionalTarget(ctx.options, args: args)
        guard let app = AXHelper.runningApp(options: options) else {
            Output.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let appElement = AXHelper.appElement(for: app)
        guard let focusedElement: AXUIElement = AXHelper.attribute(appElement, AXConst.Attr.focusedUIElement) else {
            Output.error("Focused element not found", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        let target = resolvedTargetData(app)
        var data = elementSummary(focusedElement, pid: app.processIdentifier, appElement: appElement)
        data["target"] = target
        Trace.log(["event": "focused.read", "target": target, "element": data])
        Output.ok(data, quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func selection(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let options = optionsWithPositionalTarget(ctx.options, args: args)
        guard let app = AXHelper.runningApp(options: options) else {
            Output.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let appElement = AXHelper.appElement(for: app)
        let focusedElement: AXUIElement? = AXHelper.attribute(appElement, AXConst.Attr.focusedUIElement)
        let scope = focusedElement ?? focusedWindow(for: app) ?? appElement

        let target = resolvedTargetData(app)
        var data: [String: Any] = ["target": target]
        if let focusedElement {
            data["focused"] = elementSummary(focusedElement, pid: app.processIdentifier, appElement: appElement)
        }
        if let selectedText: String = AXHelper.attribute(scope, AXConst.Attr.selectedText) {
            data["selectedText"] = selectedText
        }
        if let selected: Bool = AXHelper.boolAttribute(scope, AXConst.Attr.selected) {
            data["selected"] = selected
        }
        let selectedRows: [AXUIElement] = AXHelper.attribute(scope, AXConst.Attr.selectedRows) ?? []
        if !selectedRows.isEmpty {
            data["selectedRows"] = selectedRows.map { elementSummary($0, pid: app.processIdentifier, appElement: appElement) }
        }
        let selectedChildren: [AXUIElement] = AXHelper.attribute(scope, AXConst.Attr.selectedChildren) ?? []
        if !selectedChildren.isEmpty {
            data["selectedChildren"] = selectedChildren.map { elementSummary($0, pid: app.processIdentifier, appElement: appElement) }
        }
        Trace.log(["event": "selection.read", "target": target, "selection": data])
        Output.ok(data, quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func launch(ctx: CommandContext, args: [String]) -> Int32 {
        guard let bundleId = firstPositionalArg(args) else {
            Output.error("Missing bundle identifier", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        let wait = args.contains("--wait")
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            Output.error("Failed to launch app", quiet: ctx.options.quiet)
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
            Output.error("Failed to launch app", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        if wait {
            let deadline = Date().addingTimeInterval(ctx.options.timeout)
            while Date() < deadline {
                if AXHelper.ensureTrusted() {
                    let element = AXHelper.appElement(for: app)
                    if AXHelper.attribute(element, AXConst.Attr.windows) as [AXUIElement]? != nil {
                        Output.ok(["pid": Int(app.processIdentifier)], quiet: ctx.options.quiet)
                        return UitoolExit.success.rawValue
                    }
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
            Output.error("Timeout waiting for app", quiet: ctx.options.quiet)
            return UitoolExit.timeout.rawValue
        }
        Output.ok(["pid": Int(app.processIdentifier)], quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func quit(ctx: CommandContext, args: [String]) -> Int32 {
        let force = args.contains("--force")
        let options = optionsWithPositionalTarget(ctx.options, args: args)
        guard let app = AXHelper.runningApp(options: options) else {
            Output.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let ok = force ? app.forceTerminate() : app.terminate()
        if ok {
            Output.ok(["pid": Int(app.processIdentifier)], quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        Output.error("Failed to quit app", quiet: ctx.options.quiet)
        return UitoolExit.appNotFound.rawValue
    }

    static func elements(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let depth = parseIntFlag(args, "--depth") ?? 3
        let windowTitle = parseStringFlag(args, "--window")
        return withResolvedRoot(options: ctx.options, windowTitle: windowTitle, quiet: ctx.options.quiet) { app, root, path in
            let info = AXHelper.elementInfo(element: root, pid: app.processIdentifier, path: path, depth: depth)
            Output.ok([info], quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
    }

    static func outlineRows(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let outlineTitle = parseStringFlag(args, "--outline")
        let windowTitle = parseStringFlag(args, "--window")
        return withResolvedRoot(options: ctx.options, windowTitle: windowTitle, quiet: ctx.options.quiet) { app, root, _ in
            guard let outline = findOutline(in: root, title: outlineTitle) else {
                Output.error("Outline not found", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            let rows = outlineRowElements(in: outline)
            let selectedRows: [AXUIElement] = AXHelper.attribute(outline, AXConst.Attr.selectedRows) ?? []
            let selectedRowIds = Set(selectedRows.map { ObjectIdentifier($0) })
            let appElement = AXHelper.appElement(for: app)
            let data = rows.enumerated().map { index, row -> [String: Any] in
                var dict: [String: Any] = ["index": index]
                if let role = AXHelper.role(of: row) { dict["role"] = role }
                if let enabled = AXHelper.boolAttribute(row, AXConst.Attr.enabled) { dict["enabled"] = enabled }
                if !selectedRowIds.isEmpty {
                    let isSelected = selectedRowIds.contains(ObjectIdentifier(row))
                    dict["selected"] = isSelected
                } else if let selected = AXHelper.boolAttribute(row, AXConst.Attr.selected) {
                    dict["selected"] = selected
                }
                let labels = AXHelper.collectText(from: row)
                if !labels.isEmpty { dict["label"] = labels.joined(separator: " · ") }
                if let path = AXHelper.findPath(to: row, in: appElement) {
                    dict["id"] = AXHelper.elementId(pid: app.processIdentifier, path: path)
                }
                return dict
            }
            Output.ok(data, quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
    }

    static func find(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let options = parseFindOptions(args)
        return withResolvedRoot(options: ctx.options, windowTitle: options.windowTitle, quiet: ctx.options.quiet) { app, root, path in
            let matches = AXHelper.findElements(
                root: root,
                rootPath: path,
                role: options.role,
                title: options.title,
                identifier: options.identifier,
                text: options.text,
                textDescendants: options.textDescendants
            )
            if matches.isEmpty {
                Trace.log([
                    "event": "find",
                    "query": ["role": options.role ?? "", "title": options.title ?? "", "identifier": options.identifier ?? "", "text": options.text ?? ""],
                    "result": "not_found"
                ])
                Output.error("Element not found", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            if options.shouldClick {
                let targetPath = matches[0].1
                var target = matches[0].0
                if let ancestorRole = options.ancestorRole {
                    if let ancestor = AXHelper.ancestor(forPath: targetPath, in: AXHelper.appElement(for: app), role: ancestorRole) {
                        target = ancestor
                    } else {
                        Output.error("Ancestor not found", quiet: ctx.options.quiet)
                        return UitoolExit.notFound.rawValue
                    }
                }
                if !tryClick(target) {
                    Output.error("Failed to click element", quiet: ctx.options.quiet)
                    return UitoolExit.notFound.rawValue
                }
            }
            Trace.log([
                "event": "find",
                "query": ["role": options.role ?? "", "title": options.title ?? "", "identifier": options.identifier ?? "", "text": options.text ?? ""],
                "count": matches.count,
                "matchedElementId": AXHelper.elementId(pid: app.processIdentifier, path: matches[0].1)
            ])
            let data = matches.map { element, matchPath in
                AXHelper.elementInfo(element: element, pid: app.processIdentifier, path: matchPath, depth: 0)
            }
            Output.ok(data, quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
    }

    static func elementAt(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        guard args.count >= 2, let x = Double(args[0]), let y = Double(args[1]) else {
            Output.error("Usage: element-at <x> <y>", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        let system = AXHelper.systemWideElement()
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(system, Float(x), Float(y), &element)
        guard result == .success, let found = element else {
            Output.error("Element not found", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        var pid: pid_t = 0
        AXUIElementGetPid(found, &pid)
        let appElement = AXUIElementCreateApplication(pid)
        let path = AXHelper.findPath(to: found, in: appElement) ?? [0]
        let info = AXHelper.elementInfo(element: found, pid: pid, path: path, depth: 0)
        Output.ok([info], quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func click(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let interaction = parseInteractionOptions(args)
        let filteredArgs = removingFlags(args, ["--activate", "--frontmost"])
        if let id = filteredArgs.first, id.hasPrefix("ax://") {
            if let code = prepareInteraction(options: ctx.options, interaction: interaction, quiet: ctx.options.quiet, elementId: id) {
                return code
            }
            guard let element = AXHelper.elementFromId(id) else {
                Output.error("Element not found", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            if press(element: element) {
                Trace.log(["event": "click", "elementId": id, "action": "press", "result": "success"])
                Output.ok(quiet: ctx.options.quiet)
                return UitoolExit.success.rawValue
            }
            if let frame = AXHelper.frame(of: element) {
                EventHelper.click(at: CGPoint(x: frame.midX, y: frame.midY))
                Trace.log(["event": "click", "elementId": id, "action": "coord", "result": "success"])
                Output.ok(quiet: ctx.options.quiet)
                return UitoolExit.success.rawValue
            }
            Output.error("Failed to click element", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        if let code = prepareInteraction(options: ctx.options, interaction: interaction, quiet: ctx.options.quiet) {
            return code
        }
        let role = parseStringFlag(filteredArgs, "--role")
        let title = parseStringFlag(filteredArgs, "--title")
        let text = parseStringFlag(filteredArgs, "--text")
        let identifier = parseStringFlag(filteredArgs, "--identifier")
        let windowTitle = parseStringFlag(filteredArgs, "--window")
        return withResolvedRoot(options: ctx.options, windowTitle: windowTitle, quiet: ctx.options.quiet) { app, root, path in
            let matches = AXHelper.findElements(root: root, rootPath: path, role: role, title: title, identifier: identifier, text: text)
            guard let target = matches.first?.0 else {
                Output.error("Element not found", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            if tryClick(target) {
                Trace.log([
                    "event": "click",
                    "query": ["role": role ?? "", "title": title ?? "", "text": text ?? "", "identifier": identifier ?? ""],
                    "matchedElementId": AXHelper.elementId(pid: app.processIdentifier, path: matches.first?.1 ?? [0]),
                    "result": "success"
                ])
                Output.ok(quiet: ctx.options.quiet)
                return UitoolExit.success.rawValue
            }
            Output.error("Failed to click element", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
    }

    static func clickAt(ctx: CommandContext, args: [String]) -> Int32 {
        guard args.count >= 2, let x = Double(args[0]), let y = Double(args[1]) else {
            Output.error("Usage: click-at <x> <y>", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        let doubleClick = args.contains("--double")
        let right = args.contains("--right")
        EventHelper.click(at: CGPoint(x: x, y: y), button: right ? .right : .left, clickCount: doubleClick ? 2 : 1)
        Output.ok(quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func typeText(ctx: CommandContext, args: [String]) -> Int32 {
        let interaction = parseInteractionOptions(args)
        let filteredArgs = removingFlags(args, ["--activate", "--frontmost"])
        guard let text = positionalArgs(filteredArgs, valueFlags: ["--delay"]).first else {
            Output.error("Usage: type <text>", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        if let code = prepareInteraction(options: ctx.options, interaction: interaction, quiet: ctx.options.quiet) {
            return code
        }
        let delay = parseIntFlag(filteredArgs, "--delay") ?? 0
        EventHelper.type(text: text, delayMs: delay)
        Trace.log(["event": "type", "textLength": text.count, "delayMs": delay])
        Output.ok(quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func key(ctx: CommandContext, args: [String]) -> Int32 {
        let interaction = parseInteractionOptions(args)
        let filteredArgs = removingFlags(args, ["--activate", "--frontmost"])
        if filteredArgs.contains("--list") {
            Output.ok(["keys": KeyCodes.supportedKeys()], quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        if let code = prepareInteraction(options: ctx.options, interaction: interaction, quiet: ctx.options.quiet) {
            return code
        }
        if let rawIndex = filteredArgs.firstIndex(of: "--raw") {
            guard rawIndex + 1 < filteredArgs.count, let raw = Int(filteredArgs[rawIndex + 1]) else {
                Output.error("Usage: key --raw <keycode>", quiet: ctx.options.quiet)
                return UitoolExit.invalidArguments.rawValue
            }
            let shortcut = "raw:\(raw)"
            if EventHelper.keyShortcut(shortcut) {
                Trace.log(["event": "key", "shortcut": shortcut, "result": "success"])
                Output.ok(quiet: ctx.options.quiet)
                return UitoolExit.success.rawValue
            }
            Output.error("Unknown key", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        guard let keyString = positionalArgs(filteredArgs, valueFlags: ["--raw"]).first else {
            Output.error("Usage: key <shortcut>", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        if EventHelper.keyShortcut(keyString) {
            Trace.log(["event": "key", "shortcut": keyString, "result": "success"])
            Output.ok(quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        Output.error("Unknown key", quiet: ctx.options.quiet)
        return UitoolExit.invalidArguments.rawValue
    }

    static func keys(ctx: CommandContext) -> Int32 {
        Output.ok(["keys": KeyCodes.supportedKeys()], quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func setValue(ctx: CommandContext, args: [String]) -> Int32 {
        guard args.count >= 2 else {
            Output.error("Usage: set-value <id> <value>", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        let id = args[0]
        let value = args[1]
        guard let element = AXHelper.elementFromId(id) else {
            Output.error("Element not found", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        let result = AXUIElementSetAttributeValue(element, AXConst.Attr.value, value as CFTypeRef)
        if result == .success {
            Output.ok(quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        Output.error("Failed to set value", quiet: ctx.options.quiet)
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
                Output.ok(quiet: ctx.options.quiet)
                return UitoolExit.success.rawValue
            }
        }
        EventHelper.scroll(deltaY: delta)
        Output.ok(quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func exists(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let query = parseQueryOptions(args)
        return withResolvedRoot(options: ctx.options, windowTitle: query.windowTitle, quiet: ctx.options.quiet) { _, root, path in
            let matches = AXHelper.findElements(root: root, rootPath: path, role: query.role, title: query.title, identifier: query.identifier, text: query.text)
            if matches.isEmpty {
                Output.error("Element not found", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            Output.ok(quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
    }

    static func wait(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let query = parseQueryOptions(args)
        let elementId = parseStringFlag(args, "--element-id")
        let targetWindowCount = parseIntFlag(args, "--window-count")
        let gone = args.contains("--gone")
        let timeout = TimeInterval(parseIntFlag(args, "--timeout") ?? Int(ctx.options.timeout))
        guard let app = AXHelper.runningApp(options: ctx.options) else {
            Output.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let hasQuery = query.role != nil || query.title != nil || query.text != nil || query.identifier != nil
        if !hasQuery, elementId == nil, targetWindowCount == nil {
            Output.error("Usage: wait --text|--title|--identifier|--role|--element-id|--window-count ...", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }

        Trace.log([
            "event": "wait.start",
            "target": resolvedTargetData(app),
            "query": ["role": query.role ?? "", "title": query.title ?? "", "text": query.text ?? "", "identifier": query.identifier ?? "", "window": query.windowTitle ?? ""],
            "elementId": elementId ?? "",
            "windowCount": targetWindowCount ?? -1,
            "gone": gone,
            "timeoutSec": timeout
        ])

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let queryFound: Bool
            let appElement = AXHelper.appElement(for: app)
            if hasQuery {
                let matches: [(AXUIElement, [Int])]
                if let windowTitle = query.windowTitle {
                    if let (root, path) = findWindowRoot(in: appElement, windowTitle: windowTitle) {
                        matches = AXHelper.findElements(root: root, rootPath: path, role: query.role, title: query.title, identifier: query.identifier, text: query.text)
                    } else {
                        matches = []
                    }
                } else {
                    matches = AXHelper.findElements(root: appElement, rootPath: [0], role: query.role, title: query.title, identifier: query.identifier, text: query.text)
                }
                queryFound = !matches.isEmpty
            } else {
                queryFound = true
            }

            let elementFound: Bool
            if let elementId {
                elementFound = AXHelper.elementFromId(elementId) != nil
            } else {
                elementFound = true
            }
            let windowCountFound: Bool
            if let targetWindowCount {
                let windows: [AXUIElement] = AXHelper.attribute(appElement, AXConst.Attr.windows) ?? []
                windowCountFound = windows.count == targetWindowCount
            } else {
                windowCountFound = true
            }

            let found = queryFound && elementFound && windowCountFound
            if gone {
                if !found {
                    Trace.log(["event": "wait.success", "gone": true])
                    Output.ok(quiet: ctx.options.quiet)
                    return UitoolExit.success.rawValue
                }
            } else {
                if found {
                    Trace.log(["event": "wait.success", "gone": false])
                    Output.ok(quiet: ctx.options.quiet)
                    return UitoolExit.success.rawValue
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        Trace.log(["event": "wait.timeout"])
        Output.error("Timeout", quiet: ctx.options.quiet)
        return UitoolExit.timeout.rawValue
    }

    static func assert(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let query = parseQueryOptions(args)
        let checkEnabled = args.contains("--enabled")
        let checkChecked = args.contains("--checked")
        let expectedValue = parseStringFlag(args, "--value")
        return withResolvedRoot(options: ctx.options, windowTitle: query.windowTitle, quiet: ctx.options.quiet) { _, root, path in
            guard let element = AXHelper.findElements(root: root, rootPath: path, role: query.role, title: query.title, identifier: query.identifier, text: query.text).first?.0 else {
                Output.error("Element not found", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            if checkEnabled {
                if AXHelper.boolAttribute(element, AXConst.Attr.enabled) != true {
                    Output.error("Expected enabled", quiet: ctx.options.quiet)
                    return UitoolExit.notFound.rawValue
                }
            }
            if checkChecked {
                let checked = AXHelper.boolAttribute(element, AXConst.Attr.value) ?? AXHelper.boolAttribute(element, AXConst.Attr.selected)
                if checked != true {
                    Output.error("Expected checked", quiet: ctx.options.quiet)
                    return UitoolExit.notFound.rawValue
                }
            }
            if let expectedValue {
                let actual: String? = AXHelper.attribute(element, AXConst.Attr.value)
                if actual != expectedValue {
                    Output.error("Value mismatch", quiet: ctx.options.quiet)
                    return UitoolExit.notFound.rawValue
                }
            }
            Output.ok(quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
    }

    static func windows(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        guard let app = AXHelper.runningApp(options: ctx.options) else {
            Output.error("App not found", quiet: ctx.options.quiet)
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
        Output.ok(data, quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func windowCommand(ctx: CommandContext, args: [String]) -> Int32 {
        guard args.count >= 2 else {
            Output.error("Usage: window <action> <id> [args]", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let action = args[0]
        let id = args[1]
        guard let window = windowFromId(id, options: ctx.options) else {
            Output.error("Window not found", quiet: ctx.options.quiet)
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
                Output.error("Usage: window resize <id> <width> <height>", quiet: ctx.options.quiet)
                return UitoolExit.invalidArguments.rawValue
            }
            var size = CGSize(width: w, height: h)
            let axValue = AXValueCreate(.cgSize, &size)!
            _ = AXUIElementSetAttributeValue(window, AXConst.Attr.size, axValue)
        case "move":
            guard args.count >= 4, let x = Double(args[2]), let y = Double(args[3]) else {
                Output.error("Usage: window move <id> <x> <y>", quiet: ctx.options.quiet)
                return UitoolExit.invalidArguments.rawValue
            }
            var point = CGPoint(x: x, y: y)
            let axValue = AXValueCreate(.cgPoint, &point)!
            _ = AXUIElementSetAttributeValue(window, AXConst.Attr.position, axValue)
        default:
            Output.error("Unknown window action", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        Output.ok(quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func menus(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        guard let app = AXHelper.runningApp(options: ctx.options) else {
            Output.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let appElement = AXHelper.appElement(for: app)
        guard let menuBar: AXUIElement = AXHelper.attribute(appElement, AXConst.Attr.menuBar) else {
            Output.error("Menu bar not found", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        let data = menuTree(menuBar, depth: 3)
        Output.ok(data, quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func menu(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        guard let app = AXHelper.runningApp(options: ctx.options) else {
            Output.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let options = parseMenuOptions(args)
        if options.path.isEmpty, !options.listChildren {
            Output.error("Usage: menu <path...>", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        let appElement = AXHelper.appElement(for: app)
        guard let menuBar: AXUIElement = AXHelper.attribute(appElement, AXConst.Attr.menuBar) else {
            Output.error("Menu bar not found", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        if options.listChildren {
            guard let container = findMenuContainer(menuBar: menuBar, path: options.path, match: options.match) else {
                Output.error("Menu item not found", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            let children = menuChildren(of: container).map { child -> [String: Any] in
                var dict: [String: Any] = [:]
                if let title = AXHelper.stringAttribute(child, AXConst.Attr.title) { dict["title"] = title }
                if let role = AXHelper.role(of: child) { dict["role"] = role }
                return dict
            }
            Output.ok(children, quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        if let target = findMenuContainer(menuBar: menuBar, path: options.path, match: options.match) {
            if press(element: target) {
                Output.ok(quiet: ctx.options.quiet)
                return UitoolExit.success.rawValue
            }
        }
        Output.error("Menu item not found", quiet: ctx.options.quiet)
        return UitoolExit.notFound.rawValue
    }

    static func statusbar(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let options = parseStatusBarOptions(args)
        guard let menuBar = systemMenuBar() else {
            Output.error("Menu bar not found", quiet: ctx.options.quiet)
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
            Output.ok(data, quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        guard let name = options.name else {
            Output.error("Usage: statusbar --list | statusbar <item> | statusbar --menu <item>", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        guard let target = findStatusBarItem(items, name: name, match: options.match) else {
            Output.error("Status bar item not found", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        if options.listMenu {
            if AXHelper.attribute(target, AXConst.Attr.menu) as AXUIElement? == nil {
                _ = press(element: target)
                Thread.sleep(forTimeInterval: 0.1)
            }
            guard let menu: AXUIElement = AXHelper.attribute(target, AXConst.Attr.menu) else {
                Output.error("Menu not found", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            let children = AXHelper.children(of: menu).map { child -> [String: Any] in
                var dict: [String: Any] = [:]
                if let title = AXHelper.stringAttribute(child, AXConst.Attr.title) { dict["title"] = title }
                if let role = AXHelper.role(of: child) { dict["role"] = role }
                return dict
            }
            Output.ok(children, quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        if press(element: target) {
            Output.ok(quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        Output.error("Failed to click status bar item", quiet: ctx.options.quiet)
        return UitoolExit.notFound.rawValue
    }

    static func snapshot(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let options = optionsWithPositionalTarget(ctx.options, args: args)
        guard let app = AXHelper.runningApp(options: options) else {
            Output.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        let appElement = AXHelper.appElement(for: app)
        let depth = parseIntFlag(args, "--depth") ?? 5
        let outputPath = parseStringFlag(args, "--output") ?? parseStringFlag(args, "-o")
        let windows: [AXUIElement] = AXHelper.attribute(appElement, AXConst.Attr.windows) ?? []
        let target = resolvedTargetData(app)
        let data: [String: Any] = [
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "target": target,
            "windowCount": windows.count,
            "tree": AXHelper.elementInfo(element: appElement, pid: app.processIdentifier, path: [0], depth: depth)
        ]
        Trace.log(["event": "snapshot", "target": target, "depth": depth, "output": outputPath ?? "stdout"])
        if let outputPath {
            guard writeJSONObject(data, to: outputPath) else {
                Output.error("Failed to write file", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            Output.ok(["path": outputPath], quiet: ctx.options.quiet)
            return UitoolExit.success.rawValue
        }
        Output.ok(data, quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func diff(ctx: CommandContext, args: [String]) -> Int32 {
        guard args.count >= 2 else {
            Output.error("Usage: diff <before.json> <after.json>", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        let beforePath = args[0]
        let afterPath = args[1]
        guard let before = readJSONObject(at: beforePath), let after = readJSONObject(at: afterPath) else {
            Output.error("Failed to read snapshot file", quiet: ctx.options.quiet)
            return UitoolExit.notFound.rawValue
        }
        guard let beforeSnapshot = extractSnapshotPayload(before), let afterSnapshot = extractSnapshotPayload(after) else {
            Output.error("Invalid snapshot file", quiet: ctx.options.quiet)
            return UitoolExit.invalidArguments.rawValue
        }
        let beforeMap = flattenSnapshot(snapshot: beforeSnapshot)
        let afterMap = flattenSnapshot(snapshot: afterSnapshot)

        let beforeIds = Set(beforeMap.keys)
        let afterIds = Set(afterMap.keys)
        let addedIds = afterIds.subtracting(beforeIds).sorted()
        let removedIds = beforeIds.subtracting(afterIds).sorted()

        let shared = beforeIds.intersection(afterIds).sorted()
        let changed = shared.compactMap { id -> [String: Any]? in
            guard let left = beforeMap[id], let right = afterMap[id] else { return nil }
            let leftComparable = comparableSnapshotNode(left)
            let rightComparable = comparableSnapshotNode(right)
            guard !NSDictionary(dictionary: leftComparable).isEqual(to: rightComparable) else { return nil }
            return ["id": id, "before": leftComparable, "after": rightComparable]
        }

        let data: [String: Any] = [
            "added": addedIds,
            "removed": removedIds,
            "changed": changed,
            "summary": [
                "added": addedIds.count,
                "removed": removedIds.count,
                "changed": changed.count
            ]
        ]
        Trace.log(["event": "snapshot.diff", "before": beforePath, "after": afterPath, "summary": data["summary"] ?? [:]])
        Output.ok(data, quiet: ctx.options.quiet)
        return UitoolExit.success.rawValue
    }

    static func screenshot(ctx: CommandContext, args: [String]) -> Int32 {
        guard AXHelper.ensureTrusted() else {
            Output.error("Accessibility permission denied", quiet: ctx.options.quiet)
            return UitoolExit.permissionDenied.rawValue
        }
        let output = parseStringFlag(args, "-o") ?? parseStringFlag(args, "--output")
        if let elementId = parseStringFlag(args, "--element") {
            guard let element = AXHelper.elementFromId(elementId) else {
                Output.error("Element not found", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            guard let frame = AXHelper.frame(of: element) else {
                Output.error("Element has no frame", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            guard let image = capture(rect: frame) else {
                Output.error("Failed to capture", quiet: ctx.options.quiet)
                return UitoolExit.notFound.rawValue
            }
            return writeImage(image, output: output, quiet: ctx.options.quiet)
        }
        guard let app = AXHelper.runningApp(options: ctx.options) else {
            Output.error("App not found", quiet: ctx.options.quiet)
            return UitoolExit.appNotFound.rawValue
        }
        if let window = focusedWindow(for: app), let number: NSNumber = AXHelper.attribute(window, AXConst.Attr.windowNumber) {
            if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(number.uint32Value), [.boundsIgnoreFraming]) {
                return writeCGImage(image, output: output, quiet: ctx.options.quiet)
            }
        }
        Output.error("Failed to capture window", quiet: ctx.options.quiet)
        return UitoolExit.notFound.rawValue
    }
}

struct EventHelper {
    static func click(at point: CGPoint, button: CGMouseButton = .left, clickCount: Int = 1) {
        let down = CGEvent(mouseEventSource: nil, mouseType: button == .left ? .leftMouseDown : .rightMouseDown, mouseCursorPosition: point, mouseButton: button)
        down?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        let up = CGEvent(mouseEventSource: nil, mouseType: button == .left ? .leftMouseUp : .rightMouseUp, mouseCursorPosition: point, mouseButton: button)
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
        var modifierKeyCodes: [CGKeyCode] = []
        var hasFn = false
        for part in parts {
            switch part {
            case "cmd", "command":
                flags.insert(.maskCommand)
                modifierKeyCodes.append(55)
            case "shift":
                flags.insert(.maskShift)
                modifierKeyCodes.append(56)
            case "alt", "option":
                flags.insert(.maskAlternate)
                modifierKeyCodes.append(58)
            case "ctrl", "control":
                flags.insert(.maskControl)
                modifierKeyCodes.append(59)
            case "fn", "function":
                hasFn = true
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
        let isFunctionKey = keyPart.hasPrefix("f") && Int(keyPart.dropFirst()) != nil
        let shouldSendFn = hasFn || isFunctionKey
        if shouldSendFn {
            flags.insert(.maskSecondaryFn)
            modifierKeyCodes.append(63)
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for mod in modifierKeyCodes {
            let modDown = CGEvent(keyboardEventSource: source, virtualKey: mod, keyDown: true)
            modDown?.flags = flags
            modDown?.post(tap: .cghidEventTap)
        }
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        for mod in modifierKeyCodes.reversed() {
            let modUp = CGEvent(keyboardEventSource: source, virtualKey: mod, keyDown: false)
            modUp?.flags = flags
            modUp?.post(tap: .cghidEventTap)
        }
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
    var textDescendants = false
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
        case "--query":
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
        case "--descendants", "--desc":
            options.textDescendants = true
            i += 1
        case "--click":
            options.shouldClick = true
            i += 1
        default:
            if !arg.hasPrefix("-"),
               options.role == nil, options.title == nil, options.identifier == nil, options.text == nil {
                options.text = arg
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

func optionsWithPositionalTarget(_ options: GlobalOptions, args: [String]) -> GlobalOptions {
    var resolved = options
    if !hasTarget(resolved), let name = firstPositionalArg(args) {
        resolved.appName = name
    }
    return resolved
}

func hasTarget(_ options: GlobalOptions) -> Bool {
    options.appName != nil || options.bundleId != nil || options.pid != nil || options.appPath != nil || options.executablePath != nil
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
        Output.error("App not found", quiet: quiet)
        return UitoolExit.appNotFound.rawValue
    case .windowNotFound:
        Output.error("Window not found", quiet: quiet)
        return UitoolExit.notFound.rawValue
    case .ok(let app, let root, let path):
        Trace.log(["event": "target.resolved", "target": resolvedTargetData(app), "window": windowTitle ?? ""])
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

func findOutline(in root: AXUIElement, title: String?) -> AXUIElement? {
    var outlines: [AXUIElement] = []
    func walk(_ element: AXUIElement) {
        if AXHelper.role(of: element) == "AXOutline" {
            outlines.append(element)
        }
        for child in AXHelper.children(of: element) {
            walk(child)
        }
    }
    walk(root)
    guard let title, !title.isEmpty else { return outlines.first }
    return outlines.first(where: {
        (AXHelper.title(of: $0) ?? "").localizedCaseInsensitiveContains(title)
    })
}

func outlineRowElements(in outline: AXUIElement) -> [AXUIElement] {
    var rows: [AXUIElement] = []
    func walk(_ element: AXUIElement) {
        if AXHelper.role(of: element) == "AXRow" {
            rows.append(element)
        }
        for child in AXHelper.children(of: element) {
            walk(child)
        }
    }
    walk(outline)
    return rows
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
    for (index, name) in path.enumerated() {
        guard let matchElement = currentElements.first(where: {
            guard let title = AXHelper.stringAttribute($0, AXConst.Attr.title) else { return false }
            return menuTitleMatches(title, name, options: match)
        }) else { return nil }
        if index == path.count - 1 {
            return matchElement
        }
        currentElements = menuChildren(of: matchElement)
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
        Output.error("Failed to encode image", quiet: quiet)
        return UitoolExit.notFound.rawValue
    }
    FileHandle.standardOutput.write(data)
    return UitoolExit.success.rawValue
}

func writeCGImage(_ image: CGImage, output: String?, quiet: Bool) -> Int32 {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        Output.error("Failed to encode image", quiet: quiet)
        return UitoolExit.notFound.rawValue
    }
    if let output {
        do {
            try data.write(to: URL(fileURLWithPath: output))
        } catch {
            Output.error("Failed to write file", quiet: quiet)
            return UitoolExit.notFound.rawValue
        }
        Output.ok(["path": output], quiet: quiet)
        return UitoolExit.success.rawValue
    }
    FileHandle.standardOutput.write(data)
    return UitoolExit.success.rawValue
}

struct InteractionOptions {
    var activate = false
    var frontmost = false
}

func parseInteractionOptions(_ args: [String]) -> InteractionOptions {
    InteractionOptions(activate: args.contains("--activate"), frontmost: args.contains("--frontmost"))
}

func removingFlags(_ args: [String], _ flags: [String]) -> [String] {
    let flagSet = Set(flags)
    return args.filter { !flagSet.contains($0) }
}

func positionalArgs(_ args: [String], valueFlags: [String] = []) -> [String] {
    let valueFlagSet = Set(valueFlags)
    var result: [String] = []
    var i = 0
    while i < args.count {
        let arg = args[i]
        if valueFlagSet.contains(arg) {
            i += 2
            continue
        }
        if !arg.hasPrefix("-") {
            result.append(arg)
        }
        i += 1
    }
    return result
}

func prepareInteraction(options: GlobalOptions, interaction: InteractionOptions, quiet: Bool, elementId: String? = nil) -> Int32? {
    guard interaction.activate || interaction.frontmost else { return nil }
    var targetOptions = options
    if !hasTarget(targetOptions), let elementId, let parsed = AXHelper.parseElementId(elementId) {
        targetOptions.pid = parsed.pid
    }
    guard let app = (hasTarget(targetOptions) ? AXHelper.runningApp(options: targetOptions) : AXHelper.frontmostApp()) else {
        Output.error("App not found", quiet: quiet)
        return UitoolExit.appNotFound.rawValue
    }
    if interaction.activate {
        guard app.activate(options: [.activateIgnoringOtherApps]) else {
            Output.error("Failed to focus app", quiet: quiet)
            return UitoolExit.appNotFound.rawValue
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    if interaction.frontmost, AXHelper.frontmostApp()?.processIdentifier != app.processIdentifier {
        Output.error("Target app is not frontmost", quiet: quiet)
        return UitoolExit.appNotFound.rawValue
    }
    Trace.log(["event": "interaction.prepare", "target": resolvedTargetData(app), "activate": interaction.activate, "frontmost": interaction.frontmost])
    return nil
}

func resolvedTargetData(_ app: NSRunningApplication) -> [String: Any] {
    let appElement = AXHelper.appElement(for: app)
    let windows: [AXUIElement] = AXHelper.attribute(appElement, AXConst.Attr.windows) ?? []
    return [
        "name": app.localizedName ?? "",
        "pid": Int(app.processIdentifier),
        "bundleId": app.bundleIdentifier ?? "",
        "appPath": AXHelper.resolvedPath(app.bundleURL?.path) ?? "",
        "executablePath": AXHelper.resolvedPath(app.executableURL?.path) ?? "",
        "windowCount": windows.count,
        "frontmost": app.processIdentifier == AXHelper.frontmostApp()?.processIdentifier,
        "target": "app://\(app.processIdentifier)"
    ]
}

func elementSummary(_ element: AXUIElement, pid: pid_t, appElement: AXUIElement) -> [String: Any] {
    if let path = AXHelper.findPath(to: element, in: appElement) {
        return AXHelper.elementInfo(element: element, pid: pid, path: path, depth: 0)
    }
    var info = AXHelper.elementInfo(element: element, pid: pid, path: [0], depth: 0)
    info.removeValue(forKey: "id")
    return info
}

func writeJSONObject(_ object: [String: Any], to path: String) -> Bool {
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]) else { return false }
    do {
        try data.write(to: URL(fileURLWithPath: path))
        return true
    } catch {
        return false
    }
}

func readJSONObject(at path: String) -> [String: Any]? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
    return object as? [String: Any]
}

func extractSnapshotPayload(_ object: [String: Any]) -> [String: Any]? {
    if let ok = object["ok"] as? Bool, ok, let data = object["data"] as? [String: Any] {
        return data
    }
    if object["tree"] != nil {
        return object
    }
    return nil
}

func flattenSnapshot(snapshot: [String: Any]) -> [String: [String: Any]] {
    guard let tree = snapshot["tree"] as? [String: Any] else { return [:] }
    var map: [String: [String: Any]] = [:]
    collectSnapshotNodes(tree, into: &map)
    return map
}

func collectSnapshotNodes(_ node: [String: Any], into map: inout [String: [String: Any]]) {
    if let id = node["id"] as? String {
        map[id] = node
    }
    guard let children = node["children"] as? [Any] else { return }
    for child in children {
        if let childNode = child as? [String: Any] {
            collectSnapshotNodes(childNode, into: &map)
        }
    }
}

func comparableSnapshotNode(_ node: [String: Any]) -> [String: Any] {
    var result: [String: Any] = [:]
    let keys = ["role", "title", "value", "description", "identifier", "enabled", "focused", "frame"]
    for key in keys {
        if let value = node[key] {
            result[key] = value
        }
    }
    return result
}
