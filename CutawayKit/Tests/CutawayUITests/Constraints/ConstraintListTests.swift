import CutawayModel
import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayUI

/// How the Constraints section splits its constraints (C-LAYOUT-02), by the
/// `layout-constraints` fixture on the layers of `hierarchy`, without the section.
final class ConstraintListTests: XCTestCase {
    private func list(of id: UInt64) throws -> ConstraintList {
        let tree = try LayerTree(try Fixtures.hierarchy())
        return ConstraintList(
            try Fixtures.constraints(of: id).map { ConstraintRow($0, selected: id, tree: tree) })
    }

    func test_C_LAYOUT_02_theAppsConstraintsAreListedWithoutAFold() throws {
        let list = try list(of: 3)
        XCTAssertEqual(list.count, 4)
        XCTAssertEqual(list.own.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(list.generated, [])
        XCTAssertEqual(list.generatedCount, 0)
        XCTAssertNil(list.generatedSummary)
    }

    func test_C_LAYOUT_02_constraintsUIKitMadeAreCountedAndNamedByTheirClass() throws {
        let list = try list(of: 9)
        XCTAssertEqual(list.count, 4)
        XCTAssertEqual(list.own, [])
        XCTAssertEqual(list.generatedCount, 4)
        XCTAssertEqual(list.generated.map(\.plainEquation), [
            "UIView.width = self.maxX + 93",
            "self.width = 0",
            "self.minY = 700",
            "self.height = 0",
        ])
        XCTAssertEqual(list.generatedSummary, "Autoresizing Mask")
    }

    func test_C_LAYOUT_02_theOwnComeFirstAndUIKitsOfSeveralClassesHaveNoSummary() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        var constraints = try Fixtures.constraints(of: 3)
        constraints[0].className = "NSContentSizeLayoutConstraint"
        constraints[2].className = "NSAutoresizingMaskLayoutConstraint"
        constraints[3].className = "NSLayoutConstraint"
        let list = ConstraintList(
            constraints.map { ConstraintRow($0, selected: 3, tree: tree) })
        XCTAssertEqual(list.own.map(\.id), [2, 4], "in the server's order")
        XCTAssertEqual(list.generated.map(\.id), [1, 3])
        XCTAssertNil(list.generatedSummary)
        XCTAssertEqual(list.count, 4)
    }

    func test_C_LAYOUT_02_noConstraints() {
        let list = ConstraintList([])
        XCTAssertEqual(list.count, 0)
        XCTAssertEqual(list.generatedCount, 0)
        XCTAssertNil(list.generatedSummary)
    }
}
