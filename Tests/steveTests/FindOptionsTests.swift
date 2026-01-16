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

    func testParseFindOptionsPositionalRole() {
        let options = parseFindOptions(["AXButton"])
        XCTAssertEqual(options.role, "AXButton")
    }

    func testParseFindOptionsWindowDoesNotSetRole() {
        let options = parseFindOptions(["--window", "Settings"])
        XCTAssertEqual(options.windowTitle, "Settings")
        XCTAssertNil(options.role)
    }
}
