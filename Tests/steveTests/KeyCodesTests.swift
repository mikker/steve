import XCTest
@testable import steve

final class KeyCodesTests: XCTestCase {
    func testFunctionKeyMappings() {
        XCTAssertNotNil(KeyCodes.keyCode(for: "f1"))
        XCTAssertNotNil(KeyCodes.keyCode(for: "f12"))
        XCTAssertNotNil(KeyCodes.keyCode(for: "f19"))
        XCTAssertNotNil(KeyCodes.keyCode(for: "f24"))
    }

    func testSupportedKeysIncludesFunctionKeys() {
        let keys = KeyCodes.supportedKeys()
        XCTAssertTrue(keys.contains("f12"))
    }
}
