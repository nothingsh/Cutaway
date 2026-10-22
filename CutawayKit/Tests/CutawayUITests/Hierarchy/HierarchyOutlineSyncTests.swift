import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// What the hierarchy list works out about its rows, without the list: C-HIER-02.
final class HierarchyOutlineSyncTests: XCTestCase {
    /// The `hierarchy` fixture: 1 UIWindow, 2 UIView inside it, and inside that 3 UILabel,
    /// 4 CardView with the virtual nodes 10 (holding 11) and 12 and 5 CAShapeLayer (hidden),
    /// 6 UIScrollView with 7 UILabel, 8 CALayer, 9 UIView and 13 PaymentCardView with 14 UILabel.
    private func tree() throws -> LayerTree {
        try LayerTree(try Fixtures.hierarchy())
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

    /// A row whose icon changes is not the same row, though its title is: the list and its
    /// sticky rows would go on showing the old icon.
    func test_C_HIER_11_treesWhoseIconsDifferGiveOtherRows() throws {
        let tree = try tree()

        // What the server says of the class: the app's own, so the icon is filled.
        var origin = try Fixtures.hierarchy()
        let originIndex = try XCTUnwrap(origin.nodes.firstIndex { $0.id == 8 })
        origin.nodes[originIndex].layerClassOrigin = .app
        let originTree = try LayerTree(origin)
        XCTAssertEqual(originTree.title(of: 8), tree.title(of: 8))
        XCTAssertNotEqual(LayerIcon(originTree.node(8)), LayerIcon(tree.node(8)))
        XCTAssertFalse(HierarchyOutlineSync.sameRows(tree, originTree))

        // The base class the server names: another glyph.
        var base = try Fixtures.hierarchy()
        let baseIndex = try XCTUnwrap(base.nodes.firstIndex { $0.id == 8 })
        base.nodes[baseIndex].layerBaseClassName = "CAShapeLayer"
        let baseTree = try LayerTree(base)
        XCTAssertEqual(baseTree.title(of: 8), tree.title(of: 8))
        XCTAssertNotEqual(LayerIcon(baseTree.node(8)), LayerIcon(tree.node(8)))
        XCTAssertFalse(HierarchyOutlineSync.sameRows(tree, baseTree))
    }

    func test_C_HIER_02_aPartOfTheTreeExpandedAsAWholeIsFound() throws {
        let tree = try tree()
        XCTAssertEqual(
            HierarchyOutlineSync.wholeExpansions(below: [1], in: tree) { _ in true },
            [1, 2, 4, 6, 10, 13])
        // A collapsed row with sublayers leaves out every row it is inside of.
        XCTAssertEqual(
            HierarchyOutlineSync.wholeExpansions(below: [1], in: tree) { $0 != 6 }, [4, 10, 13])
        XCTAssertEqual(
            HierarchyOutlineSync.wholeExpansions(below: [1], in: tree) { _ in false }, [])
        // Only the rows asked about and those inside them.
        XCTAssertEqual(
            HierarchyOutlineSync.wholeExpansions(below: [4, 6], in: tree) { _ in true }, [4, 6, 10])
    }
}
