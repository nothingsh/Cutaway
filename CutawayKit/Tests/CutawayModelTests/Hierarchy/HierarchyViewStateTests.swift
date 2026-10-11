import CutawayTestSupport
import XCTest

@testable import CutawayModel

/// The transitions of how the tree is looked at, without an inspection around them: what
/// each changes, and what it reports as changed. The `hierarchy` fixture: 1 holds 2, which
/// holds 3, 4 (holding 5), 6 (holding 7), 8 and 9.
final class HierarchyViewStateTests: XCTestCase {
    private func tree() throws -> LayerTree {
        try LayerTree(try Fixtures.hierarchy())
    }

    /// Every layer expanded, as a new tree with `.expanded` starts.
    private func state(_ tree: LayerTree) -> HierarchyViewState {
        var state = HierarchyViewState()
        _ = state.take(tree, restoring: nil, newLayers: .expanded)
        return state
    }

    func test_C_HIER_02_collapsingMovesASelectionInsideOntoTheNode() throws {
        let tree = try tree()
        var state = state(tree)
        XCTAssertEqual(state.select(5, in: tree), .selection)

        XCTAssertEqual(state.setExpanded([4], false, in: tree), [.expansion, .selection])
        XCTAssertFalse(state.expansion.isExpanded(4))
        XCTAssertEqual(state.selection, 4)
        XCTAssertEqual(state.setExpanded([4], false, in: tree), [], "already collapsed")
        XCTAssertEqual(state.setExpanded([4, 99], true, in: tree), .expansion, "99 is not there")
        XCTAssertEqual(state.selection, 4, "expanding moves nothing")
    }

    func test_C_HIER_02_selectingInsideACollapsedNodeSelectsTheNode() throws {
        let tree = try tree()
        var state = state(tree)
        _ = state.setExpanded([6], false, in: tree)
        XCTAssertEqual(state.select(7, in: tree), .selection)
        XCTAssertEqual(state.selection, 6)
        XCTAssertEqual(state.select(6, in: tree), [], "the same row")
        XCTAssertEqual(state.select(99, in: tree), [], "not in the tree")
        XCTAssertEqual(state.selection, 6)
        XCTAssertEqual(state.select(nil, in: tree), .selection)
        XCTAssertNil(state.selection)
    }

    func test_C_HIER_06_expandingToADepthCollapsesTheRestAndMovesTheSelection() throws {
        let tree = try tree()
        var state = state(tree)
        _ = state.select(7, in: tree)
        XCTAssertEqual(state.expand(toDepth: 2, in: tree), [.expansion, .selection])
        XCTAssertEqual(state.expansion.expandedIDs.intersection([1, 2, 4, 6]), [1, 2])
        XCTAssertEqual(state.selection, 6)
        XCTAssertEqual(state.expand(toDepth: 2, in: tree), [], "nothing changed")
    }

    func test_C_HIER_05_focusingOpensTheAncestorsAndKeepsSelectionAndHoverInside() throws {
        let tree = try tree()
        var state = state(tree)
        _ = state.setExpanded([4], false, in: tree)
        _ = state.select(3, in: tree)
        _ = state.hover(7, in: tree)

        XCTAssertEqual(state.focus(on: 5, in: tree), [.focus, .expansion, .selection, .hover])
        XCTAssertEqual(state.focus, 5)
        XCTAssertTrue(state.expansion.isExpanded(4), "the ancestors are opened")
        XCTAssertEqual(state.selection, 5, "a selection outside moves onto the focus")
        XCTAssertNil(state.hover)
        XCTAssertEqual(state.focus(on: 5, in: tree), [], "the same focus")
        XCTAssertEqual(state.focus(on: 99, in: tree), [], "not in the tree")
        XCTAssertEqual(state.select(3, in: tree), [], "outside the focus")

        XCTAssertEqual(state.focus(on: nil, in: tree), .focus)
        XCTAssertNil(state.focus)
        XCTAssertEqual(state.selection, 5)
    }

    func test_C_HIER_05_leavingAFocusMovesTheSelectionOntoItsRow() throws {
        let tree = try tree()
        var state = state(tree)
        _ = state.focus(on: 4, in: tree)
        _ = state.select(5, in: tree)
        // A node above the focus collapses: within the focus, nothing above it is looked at.
        _ = state.setExpanded([2], false, in: tree)
        XCTAssertEqual(state.selection, 5)
        XCTAssertEqual(state.focus(on: nil, in: tree), [.focus, .selection])
        XCTAssertEqual(state.selection, 2)
    }

    func test_C_HIER_04_revealingExpandsTheAncestorsAndSelectsTheLayer() throws {
        let tree = try tree()
        var state = state(tree)
        _ = state.setExpanded([4], false, in: tree)
        XCTAssertEqual(state.reveal(5, in: tree), [.expansion, .selection])
        XCTAssertTrue(state.expansion.isExpanded(4))
        XCTAssertEqual(state.selection, 5)
        XCTAssertEqual(state.reveal(5, in: tree), [])
        _ = state.focus(on: 6, in: tree)
        XCTAssertEqual(state.reveal(3, in: tree), [], "outside the focus")
    }

    func test_C_PREV_03_hoverIsALayerOfTheTreeOrNone() throws {
        let tree = try tree()
        var state = state(tree)
        XCTAssertEqual(state.hover(3, in: tree), .hover)
        XCTAssertEqual(state.hover(3, in: tree), [])
        XCTAssertEqual(state.hover(99, in: tree), [])
        XCTAssertEqual(state.hover, 3)
        XCTAssertEqual(state.hover(nil, in: tree), .hover)
        XCTAssertNil(state.hover)
    }

    func test_C_HIER_02_aNewTreeKeepsWhatIsStillThereAndDropsWhatIsGone() throws {
        let tree = try tree()
        var state = state(tree)
        _ = state.setExpanded([6], false, in: tree)
        _ = state.focus(on: 2, in: tree)
        _ = state.select(8, in: tree)
        _ = state.hover(8, in: tree)
        let changed = try LayerTree(try InspectionStoreTests.changed())  // without layer 8

        XCTAssertEqual(
            state.take(changed, restoring: nil, newLayers: .expanded),
            [.expansion, .selection, .hover])
        XCTAssertEqual(state.focus, 2)
        XCTAssertNil(state.selection)
        XCTAssertNil(state.hover)
        XCTAssertFalse(state.expansion.isExpanded(6), "kept")
        XCTAssertTrue(state.expansion.isExpanded(10), "new layers open by the rule")
        XCTAssertFalse(state.expansion.knows(8))
    }

    func test_C_HIER_02_aNewTreeMovesTheSelectionIntoTheFocusOrOntoItsRow() throws {
        let tree = try tree()
        var state = state(tree)
        _ = state.focus(on: 4, in: tree)
        _ = state.select(5, in: tree)
        // Layer 5 moves under 6, out of the focus.
        var hierarchy = try Fixtures.hierarchy()
        let index = try XCTUnwrap(hierarchy.nodes.firstIndex { $0.id == 5 })
        var five = hierarchy.nodes.remove(at: index)
        five.parentID = 6
        hierarchy.nodes.append(five)
        let moved = try LayerTree(hierarchy)

        XCTAssertEqual(state.take(moved, restoring: nil, newLayers: .expanded), [.expansion, .selection])
        XCTAssertEqual(state.selection, 4)
    }

    func test_C_ARCH_03_aRestoredStateBringsItsExpansionAndFocus() throws {
        let tree = try tree()
        var state = HierarchyViewState()
        let restoring = ArchiveState(
            expanded: [1, 2], selected: nil, focused: 5, previewMode: .twoD,
            cameras: PreviewCameras(), showsHiddenLayers: false, showsBorders: true)
        XCTAssertEqual(
            state.take(tree, restoring: restoring, newLayers: .expanded), [.expansion, .focus])
        XCTAssertEqual(state.focus, 5)
        XCTAssertTrue(state.expansion.isExpanded(4), "above the focus is opened")
        XCTAssertFalse(state.expansion.isExpanded(6))
    }
}
