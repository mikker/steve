import XCTest
@testable import steve

final class StatusBarOptionsTests: XCTestCase {
    func testParseStatusBarOptionsList() {
        let options = parseStatusBarOptions(["--list"])
        XCTAssertTrue(options.listItems)
        XCTAssertNil(options.name)
    }

    func testParseStatusBarOptionsMenuName() {
        let options = parseStatusBarOptions(["--menu", "Wi-Fi"])
        XCTAssertTrue(options.listMenu)
        XCTAssertEqual(options.name, "Wi-Fi")
    }

    func testParseStatusBarOptionsMatchFlags() {
        let options = parseStatusBarOptions(["--contains", "--case-insensitive", "--normalize-ellipsis", "Battery"])
        XCTAssertTrue(options.match.contains)
        XCTAssertTrue(options.match.caseInsensitive)
        XCTAssertTrue(options.match.normalizeEllipsis)
        XCTAssertEqual(options.name, "Battery")
    }
}
