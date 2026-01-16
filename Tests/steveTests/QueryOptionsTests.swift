import XCTest
@testable import steve

final class QueryOptionsTests: XCTestCase {
    func testParseQueryOptionsTextWindow() {
        let options = parseQueryOptions(["--text", "Ready", "--window", "Settings", "--role", "AXStaticText"])
        XCTAssertEqual(options.text, "Ready")
        XCTAssertEqual(options.windowTitle, "Settings")
        XCTAssertEqual(options.role, "AXStaticText")
    }
}
