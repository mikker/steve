import XCTest

final class IntegrationTests: XCTestCase {
    func testAppsCommand() throws {
        guard ProcessInfo.processInfo.environment["STEVE_INTEGRATION"] == "1" else {
            throw XCTSkip("Set STEVE_INTEGRATION=1 to run integration tests")
        }
        let binaryURL = try steveBinaryURL()
        let result = try runProcess(binaryURL, arguments: ["apps"])
        XCTAssertEqual(result.exitCode, 0)
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = trimmed.data(using: .utf8) ?? Data()
        let obj = try JSONSerialization.jsonObject(with: data)
        let dict = obj as? [String: Any]
        XCTAssertEqual(dict?["ok"] as? Bool, true)
        XCTAssertNotNil(dict?["data"])
    }
}

private struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private func steveBinaryURL() throws -> URL {
    if let env = ProcessInfo.processInfo.environment["STEVE_BIN"] {
        return URL(fileURLWithPath: env)
    }
    let cwd = FileManager.default.currentDirectoryPath
    let candidates = [
        "\(cwd)/.build/debug/steve",
        "\(cwd)/.build/arm64-apple-macosx/debug/steve",
        "\(cwd)/.build/x86_64-apple-macosx/debug/steve"
    ]
    for path in candidates {
        if FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
    }
    throw XCTSkip("steve binary not found; set STEVE_BIN")
}

private func runProcess(_ url: URL, arguments: [String]) throws -> ProcessResult {
    let process = Process()
    process.executableURL = url
    process.arguments = arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

    return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
}
