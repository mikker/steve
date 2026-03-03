import Foundation

struct Trace {
    private static var enabled = false
    private static var path: String?
    private static var fileHandle: FileHandle?
    private static let lock = NSLock()
    private static let timestampFormatter = ISO8601DateFormatter()

    static func configure(enabled: Bool, path: String?) {
        lock.lock()
        defer { lock.unlock() }
        self.enabled = enabled
        self.path = path
        closeHandleLocked()
    }

    static func log(_ payload: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        guard enabled else { return }

        var record = payload
        record["ts"] = timestampFormatter.string(from: Date())

        guard let data = Output.encode(record) else { return }
        var line = data
        line.append(Data("\n".utf8))

        if let handle = openHandleLocked() {
            handle.write(line)
        } else {
            FileHandle.standardError.write(line)
        }
    }

    private static func openHandleLocked() -> FileHandle? {
        guard let path, !path.isEmpty else { return nil }
        if let fileHandle {
            return fileHandle
        }
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: path) else { return nil }
        do {
            try handle.seekToEnd()
        } catch {
            return nil
        }
        fileHandle = handle
        return handle
    }

    private static func closeHandleLocked() {
        guard let fileHandle else { return }
        try? fileHandle.close()
        self.fileHandle = nil
    }
}
