import XCTest
@testable import steve

final class ParsingTests: XCTestCase {
    func testParseGlobalOptionsRemovesFlags() {
        var args = ["--app", "Finder", "apps"]
        let (options, error) = parseGlobalOptions(&args)
        XCTAssertNil(error)
        XCTAssertEqual(options.appName, "Finder")
        XCTAssertEqual(args, ["apps"])
    }

    func testParseGlobalOptionsPidTimeoutVerboseQuiet() {
        var args = ["--pid", "123", "--timeout", "7.5", "--verbose", "--quiet", "apps"]
        let (options, error) = parseGlobalOptions(&args)
        XCTAssertNil(error)
        XCTAssertEqual(options.pid, Int32(123))
        XCTAssertEqual(options.timeout, 7.5, accuracy: 0.0001)
        XCTAssertTrue(options.verbose)
        XCTAssertTrue(options.quiet)
        XCTAssertEqual(args, ["apps"])
    }

    func testParseGlobalOptionsFormatJsonFlag() {
        var args = ["--format", "json", "apps"]
        let (options, error) = parseGlobalOptions(&args)
        XCTAssertNil(error)
        XCTAssertEqual(options.format, .json)
        XCTAssertEqual(args, ["apps"])
    }

    func testParseGlobalOptionsShortJsonFlag() {
        var args = ["-j", "apps"]
        let (options, error) = parseGlobalOptions(&args)
        XCTAssertNil(error)
        XCTAssertEqual(options.format, .json)
        XCTAssertEqual(args, ["apps"])
    }

    func testParseGlobalOptionsFormatEqualsJson() {
        var args = ["--format=json", "apps"]
        let (options, error) = parseGlobalOptions(&args)
        XCTAssertNil(error)
        XCTAssertEqual(options.format, .json)
        XCTAssertEqual(args, ["apps"])
    }

    func testParseGlobalOptionsInvalidPid() {
        var args = ["--pid", "abc"]
        let (_, error) = parseGlobalOptions(&args)
        XCTAssertEqual(error, "Invalid pid")
    }

    func testParseGlobalOptionsAppPathAndExecPath() {
        var args = ["--app-path", "/Applications/Safari.app", "--exec-path", "/Applications/Safari.app/Contents/MacOS/Safari", "apps"]
        let (options, error) = parseGlobalOptions(&args)
        XCTAssertNil(error)
        XCTAssertEqual(options.appPath, "/Applications/Safari.app")
        XCTAssertEqual(options.executablePath, "/Applications/Safari.app/Contents/MacOS/Safari")
        XCTAssertEqual(args, ["apps"])
    }

    func testParseGlobalOptionsTargetHandle() {
        var args = ["--target", "app://1234", "apps"]
        let (options, error) = parseGlobalOptions(&args)
        XCTAssertNil(error)
        XCTAssertEqual(options.pid, Int32(1234))
        XCTAssertEqual(args, ["apps"])
    }

    func testParseGlobalOptionsTargetEqualsHandle() {
        var args = ["--target=4567", "apps"]
        let (options, error) = parseGlobalOptions(&args)
        XCTAssertNil(error)
        XCTAssertEqual(options.pid, Int32(4567))
        XCTAssertEqual(args, ["apps"])
    }

    func testParseGlobalOptionsJsonlTraceEnabled() {
        var args = ["--jsonl-trace", "apps"]
        let (options, error) = parseGlobalOptions(&args)
        XCTAssertNil(error)
        XCTAssertTrue(options.traceJSONL)
        XCTAssertNil(options.tracePath)
        XCTAssertEqual(args, ["apps"])
    }

    func testParseGlobalOptionsJsonlTracePath() {
        var args = ["--jsonl-trace", "/tmp/trace.jsonl", "apps"]
        let (options, error) = parseGlobalOptions(&args)
        XCTAssertNil(error)
        XCTAssertTrue(options.traceJSONL)
        XCTAssertEqual(options.tracePath, "/tmp/trace.jsonl")
        XCTAssertEqual(args, ["apps"])
    }
}
