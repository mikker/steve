import Foundation

enum UitoolExit: Int32 {
    case success = 0
    case notFound = 1
    case appNotFound = 2
    case timeout = 3
    case permissionDenied = 4
    case invalidArguments = 5
}

struct JSON {
    static func okPayload(_ data: Any? = nil) -> [String: Any] {
        if let data {
            return ["ok": true, "data": data]
        }
        return ["ok": true]
    }

    static func errorPayload(_ message: String) -> [String: Any] {
        ["ok": false, "error": message]
    }

    static func encode(_ obj: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: obj, options: [])
    }

    static func ok(_ data: Any? = nil, quiet: Bool = false) {
        guard !quiet else { return }
        printJSON(okPayload(data), to: FileHandle.standardOutput)
    }

    static func error(_ message: String, quiet: Bool = false) {
        guard !quiet else { return }
        printJSON(errorPayload(message), to: FileHandle.standardError)
    }

    private static func printJSON(_ obj: Any, to handle: FileHandle) {
        guard let data = encode(obj) else {
            let fallback = "{\"ok\":false,\"error\":\"Failed to encode JSON\"}"
            if let fallbackData = fallback.data(using: .utf8) {
                handle.write(fallbackData)
                handle.write(Data("\n".utf8))
            }
            return
        }
        handle.write(data)
        handle.write(Data("\n".utf8))
    }
}
