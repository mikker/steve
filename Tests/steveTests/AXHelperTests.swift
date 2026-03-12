import XCTest
@testable import steve

final class AXHelperTests: XCTestCase {
    func testElementIdRoundTrip() {
        let id = AXHelper.elementId(pid: 42, path: [0, 3, 1])
        let parsed = AXHelper.parseElementId(id)
        XCTAssertEqual(parsed?.pid, 42)
        XCTAssertEqual(parsed?.path, [0, 3, 1])
    }

    func testNormalizeRole() {
        XCTAssertEqual(AXHelper.normalizeRole("Button"), "AXButton")
        XCTAssertEqual(AXHelper.normalizeRole("AXButton"), "AXButton")
    }

    func testChildTraversalOrderIncludesSwiftUIRelevantCollections() {
        XCTAssertEqual(AXHelper.childAttributeTraversalOrder.first, AXConst.Attr.children)
        XCTAssertTrue(AXHelper.childAttributeTraversalOrder.contains(AXConst.Attr.visibleChildren))
        XCTAssertTrue(AXHelper.childAttributeTraversalOrder.contains(AXConst.Attr.childrenInNavigationOrder))
        XCTAssertTrue(AXHelper.childAttributeTraversalOrder.contains(AXConst.Attr.rows))
        XCTAssertTrue(AXHelper.childAttributeTraversalOrder.contains(AXConst.Attr.visibleRows))
    }
}
