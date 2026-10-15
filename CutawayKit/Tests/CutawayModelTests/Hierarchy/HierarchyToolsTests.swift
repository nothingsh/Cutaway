import Combine
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// Searching the list (C-HIER-04), focusing on a subtree (C-HIER-05) and expanding to a level
/// (C-HIER-06), as the model holds them.
final class HierarchyToolsTests: XCTestCase {
    /// A model showing the `hierarchy` fixture, with no connection behind it.
    @MainActor
    private func model() throws -> InspectionStore {
        let model = InspectionStore(
            session: Session(
                channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0")),
            newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        return model
    }

    @MainActor
    private func expanded(_ model: InspectionStore) -> [UInt64] {
        model.tree.ids.filter(model.isExpanded)
    }

    // MARK: - C-HIER-04: searching

    @MainActor
    func test_C_HIER_04_aSearchLeavesTheMatchesAndTheirAncestors() throws {
        let model = try model()
        model.setSearchText("label")
        XCTAssertEqual(model.searchText, "label")
        XCTAssertEqual(model.filter?.matches, [3, 7])
        XCTAssertEqual(model.filter?.shown, [1, 2, 3, 6, 7])
    }

    @MainActor
    func test_C_HIER_04_whiteSpaceAroundTheTextIsIgnored() throws {
        let model = try model()
        model.setSearchText("  Label ")
        XCTAssertEqual(model.searchText, "  Label ", "the field shows what was typed")
        XCTAssertEqual(model.filter?.text, "Label")
        XCTAssertEqual(model.filter?.matches, [3, 7])
        model.setSearchText("   ")
        XCTAssertNil(model.filter)
    }

    @MainActor
    func test_C_HIER_04_searchingLeavesTheExpansionAndTheLayoutAlone() throws {
        let model = try model()
        model.setExpanded(6, false)
        let revision = model.expansionRevision
        let builds = model.geometryBuildCount
        let needs = model.layout.neededTextures
        model.setSearchText("label")
        model.setSearchText("")
        XCTAssertEqual(model.expansionRevision, revision)
        XCTAssertEqual(model.geometryBuildCount, builds)
        XCTAssertEqual(model.layout.neededTextures, needs)
        XCTAssertFalse(model.isExpanded(6))
    }

    @MainActor
    func test_C_HIER_04_aNewTreeIsSearchedAgain() throws {
        let model = try model()
        model.setSearchText("label")
        var hierarchy = try Fixtures.hierarchy()
        hierarchy.nodes.removeAll { $0.id == 7 }
        model.apply(hierarchy)
        XCTAssertEqual(model.filter?.matches, [3])
        XCTAssertEqual(model.filter?.shown, [1, 2, 3])
    }

    @MainActor
    func test_C_HIER_04_theRowsRevisionMarksEveryChangeOfTheRows() throws {
        let model = try model()
        var revisions: [UInt64] = []
        let subscription = model.$rowsRevision.dropFirst().sink { revisions.append($0) }
        defer { subscription.cancel() }
        let start = model.rowsRevision

        model.setSearchText("label")
        model.setSearchText("label ")  // the same filter
        model.setSearchText("")
        XCTAssertEqual(revisions, [start + 1, start + 2])
    }

    @MainActor
    func test_C_HIER_04_theFilterIsInPlaceWhenTheRowsRevisionPublishes() throws {
        let model = try model()
        var seen: [Set<UInt64>?] = []
        let subscription = model.$rowsRevision.dropFirst().sink { _ in
            seen.append(model.filter?.shown)
        }
        defer { subscription.cancel() }
        model.setSearchText("label")
        XCTAssertEqual(seen, [[1, 2, 3, 6, 7]])
    }

    // MARK: - C-HIER-05: focusing

    @MainActor
    func test_C_HIER_05_focusingLaysOutOnlyTheSubtree() throws {
        let model = try model()
        model.focus(on: 6)
        XCTAssertEqual(model.focusedLayerID, 6)
        XCTAssertEqual(model.tree.ids.filter(model.layout.isDisplayed), [6, 7])
        XCTAssertEqual(model.layout.neededTextures.map(\.layerID), [6, 7])
    }

    @MainActor
    func test_C_HIER_05_aHiddenLayerInTheSubtreeStaysHidden() throws {
        let model = try model()
        model.focus(on: 4)
        XCTAssertEqual(model.tree.ids.filter(model.layout.isDisplayed), [4])
    }

    @MainActor
    func test_C_HIER_05_aSelectionOutsideTheFocusMovesOntoIt() throws {
        let model = try model()
        model.select(3)
        model.focus(on: 6)
        XCTAssertEqual(model.selectedLayerID, 6)
    }

    @MainActor
    func test_C_HIER_05_layersOutsideTheFocusCannotBeSelected() throws {
        let model = try model()
        model.focus(on: 6)
        model.select(3)
        XCTAssertNil(model.selectedLayerID)
        model.select(7)
        XCTAssertEqual(model.selectedLayerID, 7)
        model.select(3)
        XCTAssertEqual(model.selectedLayerID, 7, "a layer outside the focus changes nothing")
    }

    @MainActor
    func test_C_HIER_05_aCollapsedNodeAboveTheFocusDoesNotTakeTheSelection() throws {
        let model = try model()
        // Focus on 7 while its parent is collapsed: the parent is expanded for it.
        model.setExpanded(6, false)
        model.focus(on: 7)
        XCTAssertTrue(model.isExpanded(6))
        XCTAssertEqual(model.selectedLayerID, nil, "nothing was selected")
        model.select(7)
        XCTAssertEqual(model.selectedLayerID, 7)
        model.focus(on: nil)
        XCTAssertEqual(model.selectedLayerID, 7)
    }

    @MainActor
    func test_C_HIER_05_collapsingTheRootOfTheFocusMovesTheSelectionOntoIt() throws {
        let model = try model()
        model.focus(on: 6)
        model.select(7)
        model.setExpanded(6, false)
        XCTAssertEqual(model.selectedLayerID, 6)
    }

    @MainActor
    func test_C_HIER_05_aSearchLooksOnlyInTheFocus() throws {
        let model = try model()
        model.setSearchText("label")
        model.focus(on: 6)
        XCTAssertEqual(model.filter?.matches, [7])
        XCTAssertEqual(model.filter?.shown, [6, 7], "up to the root of the focus")
        model.focus(on: nil)
        XCTAssertEqual(model.filter?.shown, [1, 2, 3, 6, 7])
    }

    @MainActor
    func test_C_HIER_05_aFocusThatIsGoneFromANewTreeEnds() throws {
        let model = try model()
        model.focus(on: 6)
        var hierarchy = try Fixtures.hierarchy()
        hierarchy.nodes.removeAll { $0.id == 6 || $0.id == 7 }
        model.apply(hierarchy)
        XCTAssertNil(model.focusedLayerID)
        XCTAssertTrue(model.layout.isDisplayed(1))
    }

    @MainActor
    func test_C_HIER_05_aFocusThatIsStillThereStays() throws {
        let model = try model()
        model.focus(on: 6)
        model.apply(try Fixtures.hierarchy())
        XCTAssertEqual(model.focusedLayerID, 6)
        XCTAssertEqual(model.tree.ids.filter(model.layout.isDisplayed), [6, 7])
    }

    @MainActor
    func test_C_HIER_05_aSelectionThatMovedOutOfTheFocusMovesOntoIt() throws {
        let model = try model()
        model.focus(on: 6)
        model.select(7)
        var hierarchy = try Fixtures.hierarchy()
        // Layer 7 now sits under layer 2, outside the focus.
        let index = try XCTUnwrap(hierarchy.nodes.firstIndex { $0.id == 7 })
        hierarchy.nodes[index].parentID = 2
        model.apply(hierarchy)
        XCTAssertEqual(model.selectedLayerID, 6)
    }

    @MainActor
    func test_C_HIER_05_focusingMarksTheRowsOnce() throws {
        let model = try model()
        let start = model.rowsRevision
        model.focus(on: 6)
        XCTAssertEqual(model.rowsRevision, start + 1)
        model.focus(on: 6)
        XCTAssertEqual(model.rowsRevision, start + 1, "the same focus changes nothing")
        model.focus(on: 42)
        XCTAssertEqual(model.rowsRevision, start + 1, "a layer that is not in the tree")
        model.focus(on: nil)
        XCTAssertEqual(model.rowsRevision, start + 2)
    }

    // MARK: - C-HIER-06: expanding to a level

    @MainActor
    func test_C_HIER_06_withAFocusOnlyTheSubtreeChanges() throws {
        let model = try model()
        model.focus(on: 2)
        model.expand(toDepth: 1)
        XCTAssertEqual(expanded(model), [1, 2], "1 is outside the focus and stays expanded")
        model.collapseAll()
        XCTAssertEqual(expanded(model), [1])
    }

    @MainActor
    func test_C_HIER_06_expandingToALevelPublishesOnce() throws {
        let model = try model()
        let revision = model.expansionRevision
        let builds = model.geometryBuildCount
        var layouts = 0
        let subscription = model.$layout.dropFirst().sink { _ in layouts += 1 }
        defer { subscription.cancel() }

        model.expand(toDepth: 2)
        XCTAssertEqual(model.expansionRevision, revision + 1)
        XCTAssertEqual(model.geometryBuildCount, builds + 1)
        XCTAssertEqual(layouts, 1)

        model.expand(toDepth: 2)
        XCTAssertEqual(model.expansionRevision, revision + 1, "nothing changed")
        XCTAssertEqual(layouts, 1)
    }

    @MainActor
    func test_C_HIER_06_aSelectionInsideACollapsedNodeMovesOntoIt() throws {
        let model = try model()
        model.select(7)
        model.expand(toDepth: 2)
        XCTAssertEqual(model.selectedLayerID, 6)
    }

    // MARK: - C-HIER-04: selecting a row of the search's list

    @MainActor
    func test_C_HIER_04_revealingALayerExpandsItsAncestorsAndSelectsIt() throws {
        let model = try model()
        model.setExpanded(6, false)
        model.setSearchText("label")
        let revision = model.expansionRevision
        model.reveal(7)
        XCTAssertTrue(model.isExpanded(6))
        XCTAssertEqual(model.selectedLayerID, 7)
        XCTAssertEqual(model.expansionRevision, revision + 1)
    }

    @MainActor
    func test_C_HIER_04_revealingALayerOutsideTheFocusDoesNothing() throws {
        let model = try model()
        model.focus(on: 6)
        model.reveal(3)
        XCTAssertNil(model.selectedLayerID)
    }

    // MARK: - Found in review

    /// Whether, each time `action` makes the expansion publish, the layout for it was built
    /// already: whoever follows the expansion (the list, which then reports its rows and so
    /// asks for screenshots) finds the new layout's needs in place.
    @MainActor
    private func buildsBeforeAnnouncing(
        _ model: InspectionStore, _ action: () -> Void
    ) -> [Bool] {
        var seen: [Int] = []
        let subscription = model.$expansionRevision.dropFirst().sink { _ in
            seen.append(model.geometryBuildCount)
        }
        defer { subscription.cancel() }
        action()
        return seen.map { $0 == model.geometryBuildCount }
    }

    @MainActor
    func test_C_HIER_06_theLayoutIsBuiltBeforeTheExpansionIsAnnounced() throws {
        let model = try model()
        XCTAssertEqual(buildsBeforeAnnouncing(model) { model.expand(toDepth: 2) }, [true])
        model.expandAll()
        model.setExpanded(6, false)
        XCTAssertEqual(buildsBeforeAnnouncing(model) { model.focus(on: 7) }, [true])
        model.focus(on: nil)
        model.setExpanded(4, false)
        XCTAssertEqual(buildsBeforeAnnouncing(model) { model.reveal(5) }, [true])
    }

    @MainActor
    func test_C_HIER_05_leavingTheFocusMovesASelectionOutOfACollapsedNode() throws {
        let model = try model()
        model.setExpanded(4, false)
        model.focus(on: 6)
        model.select(7)
        // A new tree puts the focused layer 6 inside the collapsed layer 4.
        var hierarchy = try Fixtures.hierarchy()
        let index = try XCTUnwrap(hierarchy.nodes.firstIndex { $0.id == 6 })
        hierarchy.nodes[index].parentID = 4
        model.apply(hierarchy)
        XCTAssertEqual(model.selectedLayerID, 7, "inside the focus, as it was")
        model.focus(on: nil)
        XCTAssertEqual(model.selectedLayerID, 4, "the row that stands for it")
    }

    @MainActor
    func test_C_HIER_05_aHoverOutsideTheFocusEnds() throws {
        let model = try model()
        model.hover(3)
        model.focus(on: 6)
        XCTAssertNil(model.hoveredLayerID)
        model.hover(7)
        model.focus(on: nil)
        XCTAssertEqual(model.hoveredLayerID, 7)
    }
}
