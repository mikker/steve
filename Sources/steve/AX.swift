import AppKit
import ApplicationServices
import Foundation

enum AXConst {
    enum Attr {
        static let frame: CFString = "AXFrame" as CFString
        static let children: CFString = "AXChildren" as CFString
        static let role: CFString = "AXRole" as CFString
        static let title: CFString = "AXTitle" as CFString
        static let description: CFString = "AXDescription" as CFString
        static let identifier: CFString = "AXIdentifier" as CFString
        static let enabled: CFString = "AXEnabled" as CFString
        static let focused: CFString = "AXFocused" as CFString
        static let windows: CFString = "AXWindows" as CFString
        static let focusedWindow: CFString = "AXFocusedWindow" as CFString
        static let value: CFString = "AXValue" as CFString
        static let selected: CFString = "AXSelected" as CFString
        static let main: CFString = "AXMain" as CFString
        static let minimized: CFString = "AXMinimized" as CFString
        static let fullScreen: CFString = "AXFullScreen" as CFString
        static let size: CFString = "AXSize" as CFString
        static let position: CFString = "AXPosition" as CFString
        static let menuBar: CFString = "AXMenuBar" as CFString
        static let menu: CFString = "AXMenu" as CFString
        static let windowNumber: CFString = "AXWindowNumber" as CFString
    }

    enum Action {
        static let press: CFString = "AXPress" as CFString
        static let scrollUp: CFString = "AXScrollUp" as CFString
        static let scrollDown: CFString = "AXScrollDown" as CFString
    }
}

struct GlobalOptions {
    var appName: String?
    var pid: pid_t?
    var bundleId: String?
    var timeout: TimeInterval = 5
    var verbose = false
    var quiet = false
}

struct AXHelper {
    static func ensureTrusted() -> Bool {
        if AXIsProcessTrusted() { return true }
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true]
        _ = AXIsProcessTrustedWithOptions(options)
        return AXIsProcessTrusted()
    }

    static func frontmostApp() -> NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    static func runningApp(options: GlobalOptions) -> NSRunningApplication? {
        if let pid = options.pid {
            return NSRunningApplication(processIdentifier: pid)
        }
        if let bundle = options.bundleId {
            return NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
        }
        if let name = options.appName {
            return NSRunningApplication.runningApplications(withBundleIdentifier: name).first
                ?? NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name })
        }
        return frontmostApp()
    }

    static func appElement(for app: NSRunningApplication) -> AXUIElement {
        AXUIElementCreateApplication(app.processIdentifier)
    }

    static func systemWideElement() -> AXUIElement {
        AXUIElementCreateSystemWide()
    }

    static func attribute<T>(_ element: AXUIElement, _ attr: CFString) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attr, &value)
        guard result == .success, let value else { return nil }
        return (value as AnyObject) as? T
    }

    static func boolAttribute(_ element: AXUIElement, _ attr: CFString) -> Bool? {
        if let value: NSNumber = attribute(element, attr) {
            return value.boolValue
        }
        return nil
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let axValue: AXValue = attribute(element, AXConst.Attr.frame) else { return nil }
        var rect = CGRect.zero
        if AXValueGetType(axValue) == .cgRect {
            AXValueGetValue(axValue, .cgRect, &rect)
            return rect
        }
        return nil
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        if let children: [AXUIElement] = attribute(element, AXConst.Attr.children) {
            return children
        }
        return []
    }

    static func role(of element: AXUIElement) -> String? {
        attribute(element, AXConst.Attr.role)
    }

    static func title(of element: AXUIElement) -> String? {
        if let title: String = attribute(element, AXConst.Attr.title) { return title }
        if let desc: String = attribute(element, AXConst.Attr.description) { return desc }
        return nil
    }

    static func identifier(of element: AXUIElement) -> String? {
        attribute(element, AXConst.Attr.identifier)
    }

    static func stringAttribute(_ element: AXUIElement, _ attr: CFString) -> String? {
        if let value: String = attribute(element, attr) { return value }
        if let value: NSAttributedString = attribute(element, attr) { return value.string }
        if let value: NSNumber = attribute(element, attr) { return value.stringValue }
        return nil
    }

    static func matchesText(element: AXUIElement, role: String, text: String) -> Bool {
        let needle = text.lowercased()
        var candidates: [String] = []
        if let value = stringAttribute(element, AXConst.Attr.value) { candidates.append(value) }
        if let desc = stringAttribute(element, AXConst.Attr.description) { candidates.append(desc) }
        if role == "AXStaticText", let title = stringAttribute(element, AXConst.Attr.title) { candidates.append(title) }
        return candidates.contains { $0.lowercased().contains(needle) }
    }

    static func elementInfo(element: AXUIElement, pid: pid_t, path: [Int], depth: Int) -> [String: Any] {
        var dict: [String: Any] = [:]
        dict["id"] = elementId(pid: pid, path: path)
        if let role = role(of: element) { dict["role"] = role }
        if let title = title(of: element) { dict["title"] = title }
        if let identifier = identifier(of: element) { dict["identifier"] = identifier }
        if let enabled = boolAttribute(element, AXConst.Attr.enabled) { dict["enabled"] = enabled }
        if let focused = boolAttribute(element, AXConst.Attr.focused) { dict["focused"] = focused }
        if let frame = frame(of: element) {
            dict["frame"] = [
                "x": frame.origin.x,
                "y": frame.origin.y,
                "width": frame.size.width,
                "height": frame.size.height
            ]
        }
        if depth > 0 {
            let kids = children(of: element)
            if !kids.isEmpty {
                var childInfos: [[String: Any]] = []
                for (index, child) in kids.enumerated() {
                    childInfos.append(elementInfo(element: child, pid: pid, path: path + [index], depth: depth - 1))
                }
                dict["children"] = childInfos
            }
        }
        return dict
    }

    static func elementId(pid: pid_t, path: [Int]) -> String {
        let pathString = path.map(String.init).joined(separator: ".")
        return "ax://\(pid)/\(pathString)"
    }

    static func parseElementId(_ id: String) -> (pid: pid_t, path: [Int])? {
        guard id.hasPrefix("ax://") else { return nil }
        let rest = String(id.dropFirst(5))
        let parts = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let pid = Int32(parts[0]) else { return nil }
        let pathString = parts[1]
        let path = pathString.split(separator: ".").compactMap { Int($0) }
        return (pid, path)
    }

    static func elementFromId(_ id: String) -> AXUIElement? {
        guard let parsed = parseElementId(id) else { return nil }
        let app = AXUIElementCreateApplication(parsed.pid)
        var element: AXUIElement = app
        var indices = parsed.path
        if indices.first == 0 { indices.removeFirst() }
        for index in indices {
            let kids = children(of: element)
            guard index >= 0, index < kids.count else { return nil }
            element = kids[index]
        }
        return element
    }

    static func findPath(to target: AXUIElement, in root: AXUIElement, current: [Int] = [0]) -> [Int]? {
        if CFEqual(target, root) { return current }
        let kids = children(of: root)
        for (index, child) in kids.enumerated() {
            if let found = findPath(to: target, in: child, current: current + [index]) {
                return found
            }
        }
        return nil
    }

    static func normalizeRole(_ input: String) -> String {
        if input.hasPrefix("AX") { return input }
        return "AX" + input
    }

    static func match(element: AXUIElement, role: String?, title: String?, identifier: String?, text: String?) -> Bool {
        let actualRole = self.role(of: element) ?? ""
        if let role {
            if normalizeRole(role) != actualRole { return false }
        }
        if let title {
            if title != (self.title(of: element) ?? "") { return false }
        }
        if let identifier {
            if identifier != (self.identifier(of: element) ?? "") { return false }
        }
        if let text {
            if !matchesText(element: element, role: actualRole, text: text) { return false }
        }
        return true
    }

    static func findElements(root: AXUIElement, rootPath: [Int] = [0], role: String?, title: String?, identifier: String?, text: String?) -> [(AXUIElement, [Int])] {
        var matches: [(AXUIElement, [Int])] = []
        func walk(_ element: AXUIElement, _ path: [Int]) {
            if match(element: element, role: role, title: title, identifier: identifier, text: text) {
                matches.append((element, path))
            }
            let kids = children(of: element)
            for (idx, child) in kids.enumerated() {
                walk(child, path + [idx])
            }
        }
        walk(root, rootPath)
        return matches
    }

    static func ancestor(forPath path: [Int], in root: AXUIElement, role: String) -> AXUIElement? {
        var lineage: [AXUIElement] = [root]
        var current = root
        for index in path.dropFirst() {
            let kids = children(of: current)
            guard index >= 0, index < kids.count else { break }
            current = kids[index]
            lineage.append(current)
        }
        let normalized = normalizeRole(role)
        for element in lineage.reversed() {
            if (self.role(of: element) ?? "") == normalized { return element }
        }
        return nil
    }
}
