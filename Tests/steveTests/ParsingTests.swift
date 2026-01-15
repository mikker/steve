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

    func testParseGlobalOptionsInvalidPid() {
        var args = ["--pid", "abc"]
        let (_, error) = parseGlobalOptions(&args)
        XCTAssertEqual(error, "Invalid pid")
    }
}
