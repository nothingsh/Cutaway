import CutawayModel
import CutawayScene
import CutawayTestSupport
import XCTest

@testable import CutawayUI

/// Which rows of the list mark what the last refresh changed (C-LIVE-05): a layer's own row,
/// or, inside a collapsed row, the nearest row the list shows, as changed.
final class HierarchyChangeMarksTests: XCTestCase {
    private func tree() throws -> LayerTree {
        try LayerTree(try Fixtures.hierarchy())
    }

    func test_C_LIVE_05_eachShownLayerMarksItsOwnRow() throws {
        let diff = RefreshDiff(added: [7], changed: [3, 4], removed: 0, generation: 1)
        let rows = HierarchyChangeMarks.rows(of: diff, in: try tree()) { _ in true }
        XCTAssertEqual(rows, [7: .added, 3: .changed, 4: .changed])
    }

    func test_C_LIVE_05_aLayerInsideACollapsedRowMarksTheNearestShownRowAsChanged() throws {
        // Layer 6 is collapsed: 7 has no row. Layer 4 is collapsed too: 11, in 10, has none.
        let hidden: Set<UInt64> = [7, 10, 11, 12, 5]
        let diff = RefreshDiff(added: [7], changed: [11], removed: 0, generation: 1)
        let rows = HierarchyChangeMarks.rows(of: diff, in: try tree()) { !hidden.contains($0) }
        XCTAssertEqual(rows, [6: .changed, 4: .changed])
    }

    func test_C_LIVE_05_aRowsOwnMarkWinsOverOneFromInsideIt() throws {
        let hidden: Set<UInt64> = [7]
        let diff = RefreshDiff(added: [6, 7], changed: [], removed: 0, generation: 1)
        let rows = HierarchyChangeMarks.rows(of: diff, in: try tree()) { !hidden.contains($0) }
        XCTAssertEqual(rows, [6: .added])
    }

    func test_C_LIVE_05_aLayerWithNoShownRowAboveItMarksNothing() throws {
        let diff = RefreshDiff(added: [7], changed: [], removed: 2, generation: 1)
        let rows = HierarchyChangeMarks.rows(of: diff, in: try tree()) { _ in false }
        XCTAssertEqual(rows, [:])
    }
}
