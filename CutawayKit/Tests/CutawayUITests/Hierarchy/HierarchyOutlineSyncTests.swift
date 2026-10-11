import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// What the hierarchy list shows in a row and works out about its rows, without the list:
/// C-HIER-01 to C-HIER-04, C-HIER-07.
final class HierarchyOutlineSyncTests: XCTestCase {
    /// The `hierarchy` fixture: 1 UIWindow, 2 UIView inside it, and inside that 3 UILabel,
    /// 4 CardView with 5 CAShapeLayer (hidden), 6 UIScrollView with 7 UILabel, 8 CALayer and
    /// 9 UIView.
    private func tree() throws -> LayerTree {
        try LayerTree(try Fixtures.hierarchy())
    }

    // MARK: - HierarchyRow

    @MainActor
    func test_C_HIER_01_eachRowHasATitleAndASymbolForWhatItIs() throws {
        let tree = try tree()
        let rows = (1...9).map { HierarchyRow(tree, UInt64($0), filter: nil) }
        XCTAssertEqual(rows.map(\.title), [
            "UIWindow", "UIView", "UILabel", "CardView", "CAShapeLayer", "UIScrollView",
            "UILabel", "CALayer", "UIView",
        ])
        XCTAssertEqual(rows.map(\.symbolName), [
            "macwindow", "square", "textformat", "square", "square.dashed", "scroll",
            "textformat", "square.dashed", "square",
        ])
    }

    @MainActor
    func test_C_HIER_03_theHiddenLayerIsDimmed() throws {
        let tree = try tree()
        XCTAssertEqual(
            (1...9).filter { HierarchyRow(tree, UInt64($0), filter: nil).isDimmed }, [5])
    }

    @MainActor
    func test_C_HIER_04_ancestorsThatDoNotMatchAreContext() throws {
        let tree = try tree()
        let filter = try XCTUnwrap(HierarchyFilter(text: "label", tree: tree, within: nil))
        let context = [1, 2, 3, 6, 7].map {
            HierarchyRow(tree, UInt64($0), filter: filter).isContext
        }
        XCTAssertEqual(context, [true, true, false, true, false])
        XCTAssertFalse(HierarchyRow(tree, 1, filter: nil).isContext)
    }

    @MainActor
    func test_C_HIER_07_aRowNamesItsViewControllerOrTheMemberThatHoldsIt() throws {
        let tree = try tree()
        func detail(_ id: UInt64) -> String? { HierarchyRow(tree, id, filter: nil).detail }
        XCTAssertEqual(detail(2), "HomeViewController")
        XCTAssertEqual(detail(3), "HomeViewController.titleLabel")
        XCTAssertEqual(detail(5), "CardView.badgeLayer +1")
        XCTAssertEqual(detail(8), "DMBaseViewController._dividerLayer")
        for id: UInt64 in [1, 7, 9] {
            XCTAssertNil(detail(id), "layer \(id)")
        }
    }

    @MainActor
    func test_C_HIER_07_theTooltipListsEverything() throws {
        let tree = try tree()
        XCTAssertEqual(
            HierarchyRow(tree, 5, filter: nil).toolTip,
            "Referenced by CardView.badgeLayer\nReferenced by HomeViewController.cardBadge")
        XCTAssertEqual(
            HierarchyRow(tree, 2, filter: nil).toolTip, "View controller HomeViewController")
        XCTAssertNil(HierarchyRow(tree, 1, filter: nil).toolTip)
    }

    // MARK: - HierarchyOutlineSync

    func test_C_HIER_02_treesWithTheSameRowsAreTheSame() throws {
        let tree = try tree()
        XCTAssertTrue(HierarchyOutlineSync.sameRows(tree, try self.tree()))

        // One layer moved: the rows are the same.
        var moved = try Fixtures.hierarchy()
        let index = try XCTUnwrap(moved.nodes.firstIndex { $0.id == 3 })
        moved.nodes[index].position = Point(x: 10, y: 10)
        XCTAssertTrue(HierarchyOutlineSync.sameRows(tree, try LayerTree(moved)))

        // One layer fewer.
        var fewer = try Fixtures.hierarchy()
        fewer.nodes.removeAll { $0.id == 8 }
        XCTAssertFalse(HierarchyOutlineSync.sameRows(tree, try LayerTree(fewer)))

        // One layer hidden: dimmed in the list.
        var hidden = try Fixtures.hierarchy()
        let hiddenIndex = try XCTUnwrap(hidden.nodes.firstIndex { $0.id == 3 })
        hidden.nodes[hiddenIndex].isHidden = true
        XCTAssertFalse(HierarchyOutlineSync.sameRows(tree, try LayerTree(hidden)))
    }

    func test_C_HIER_02_aPartOfTheTreeExpandedAsAWholeIsFound() throws {
        let tree = try tree()
        XCTAssertEqual(
            HierarchyOutlineSync.wholeExpansions(below: [1], in: tree) { _ in true }, [1, 2, 4, 6])
        // A collapsed row with sublayers leaves out every row it is inside of.
        XCTAssertEqual(
            HierarchyOutlineSync.wholeExpansions(below: [1], in: tree) { $0 != 6 }, [4])
        XCTAssertEqual(
            HierarchyOutlineSync.wholeExpansions(below: [1], in: tree) { _ in false }, [])
        // Only the rows asked about and those inside them.
        XCTAssertEqual(
            HierarchyOutlineSync.wholeExpansions(below: [4, 6], in: tree) { _ in true }, [4, 6])
    }
}
