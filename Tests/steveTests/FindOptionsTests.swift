import XCTest
@testable import steve

final class FindOptionsTests: XCTestCase {
    func testParseFindOptionsTextWindowAncestorClick() {
        let args = ["--text", "Dictation Mode", "--window", "Settings", "--ancestor-role", "AXRow", "--desc", "--click"]
        let options = parseFindOptions(args)
        XCTAssertEqual(options.text, "Dictation Mode")
        XCTAssertEqual(options.windowTitle, "Settings")
        XCTAssertEqual(options.ancestorRole, "AXRow")
        XCTAssertTrue(options.textDescendants)
        XCTAssertTrue(options.shouldClick)
        XCTAssertNil(options.role)
    }

    func testParseFindOptionsPositionalQuery() {
        let options = parseFindOptions(["Dictation Mode"])
        XCTAssertEqual(options.text, "Dictation Mode")
        XCTAssertNil(options.role)
    }

    func testParseFindOptionsExplicitRole() {
        let options = parseFindOptions(["--role", "AXButton"])
        XCTAssertEqual(options.role, "AXButton")
    }

    func testParseFindOptionsQueryAlias() {
        let options = parseFindOptions(["--query", "Battery"])
        XCTAssertEqual(options.text, "Battery")
    }

    func testParseFindOptionsWindowDoesNotSetRole() {
        let options = parseFindOptions(["--window", "Settings"])
        XCTAssertEqual(options.windowTitle, "Settings")
        XCTAssertNil(options.role)
    }
}
