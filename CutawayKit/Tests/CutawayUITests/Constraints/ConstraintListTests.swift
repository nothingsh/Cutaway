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

    func test_C_LAYOUT_02_constraintsUIKitMadeAreCountedAndNamedByTheirClass() throws {
        let list = try list(of: 9)
        XCTAssertEqual(list.count, 4)
        XCTAssertEqual(list.own, [])
        XCTAssertEqual(list.generatedCount, 4)
        XCTAssertEqual(list.generated.map(\.plainEquation), [
            "HomeViewController.width = self.maxX + 93",
            "self.width = 0",
            "self.minY = 700",
            "self.height = 0",
        ])
        XCTAssertEqual(list.generatedSummary, "Autoresizing Mask")
    }

    func test_C_LAYOUT_02_theOwnComeFirstAndUIKitsOfSeveralClassesHaveNoSummary() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        // From a server that gives no origin, so that the classes decide.
        var constraints = Fixtures.withoutTheOptionalFields(try Fixtures.constraints(of: 3))
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

    func test_C_LAYOUT_02_theServersOriginFoldsTheConstraints() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        var three = try Fixtures.constraints(of: 3)
        three[0].origin = .system
        let list3 = ConstraintList(three.map { ConstraintRow($0, selected: 3, tree: tree) })
        XCTAssertEqual(list3.own.map(\.id), [2, 3, 4])
        XCTAssertEqual(list3.generated.map(\.id), [1])

        var nine = try Fixtures.constraints(of: 9)
        nine[0].origin = .app
        let list9 = ConstraintList(nine.map { ConstraintRow($0, selected: 9, tree: tree) })
        XCTAssertEqual(list9.own.map(\.id), [8])
        XCTAssertEqual(list9.generatedCount, 3)
    }

    func test_C_LAYOUT_02_withoutOriginsAnchorConstraintsAreTheApps() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        var constraints = Fixtures.withoutTheOptionalFields(try Fixtures.constraints(of: 3))
        constraints[1].className = "NSLayoutAnchorConstraint"
        let list = ConstraintList(constraints.map { ConstraintRow($0, selected: 3, tree: tree) })
        XCTAssertEqual(list.own.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(list.generatedCount, 0)

        let nine = ConstraintList(
            Fixtures.withoutTheOptionalFields(try Fixtures.constraints(of: 9))
                .map { ConstraintRow($0, selected: 9, tree: tree) })
        XCTAssertEqual(nine.generatedCount, 4, "the same as with origins")
    }
}
