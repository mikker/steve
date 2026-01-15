import XCTest
@testable import steve

final class JSONTests: XCTestCase {
    func testOkPayloadWithoutData() {
        let payload = JSON.okPayload()
        XCTAssertEqual(payload["ok"] as? Bool, true)
        XCTAssertNil(payload["data"])
    }

    func testErrorPayload() {
        let payload = JSON.errorPayload("nope")
        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["error"] as? String, "nope")
    }

    func testEncodeRoundTrip() throws {
        let payload = JSON.okPayload(["a": 1])
        guard let data = JSON.encode(payload) else {
            XCTFail("Failed to encode JSON")
            return
        }
        let obj = try JSONSerialization.jsonObject(with: data)
        let dict = obj as? [String: Any]
        XCTAssertEqual(dict?["ok"] as? Bool, true)
        let dataDict = dict?["data"] as? [String: Any]
        XCTAssertEqual(dataDict?["a"] as? Int, 1)
    }
}
