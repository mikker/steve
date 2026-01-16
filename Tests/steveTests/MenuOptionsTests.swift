import XCTest
@testable import steve

final class MenuOptionsTests: XCTestCase {
    func testParseMenuOptionsFlags() {
        let options = parseMenuOptions(["--contains", "--case-insensitive", "--normalize-ellipsis", "--list", "File", "New"])
        XCTAssertTrue(options.match.contains)
        XCTAssertTrue(options.match.caseInsensitive)
        XCTAssertTrue(options.match.normalizeEllipsis)
        XCTAssertTrue(options.listChildren)
        XCTAssertEqual(options.path, ["File", "New"])
    }
}
