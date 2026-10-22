import AppKit
import Combine
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// The hierarchy list's search, focus and levels as they are shown: C-HIER-04 to C-HIER-06.
final class HierarchyToolsViewTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    /// A model showing the `hierarchy` fixture, and a list on it with its view loaded.
    @MainActor
    private func loaded() throws -> (InspectionStore, HierarchyViewController) {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        let controller = HierarchyViewController(store: model, appName: "Demo")
        _ = controller.view
        return (model, controller)
    }

    /// The layer IDs of the rows, top to bottom.
    @MainActor
    private func layers(of controller: HierarchyViewController) -> [UInt64?] {
        (0..<controller.outlineView.numberOfRows).map(controller.layerID(atRow:))
    }

    @MainActor
    private func levels(of controller: HierarchyViewController) -> [Int] {
        (0..<controller.outlineView.numberOfRows).map(controller.outlineView.level(forRow:))
    }

    /// Whether the view and every view it is inside of are not hidden.
    @MainActor
    private func isShown(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            if candidate.isHidden { return false }
            current = candidate.superview
        }
        return true
    }

    @MainActor
    private func view<View: NSView>(
        _ identifier: String, in controller: HierarchyViewController, as type: View.Type
    ) throws -> View {
        try XCTUnwrap(
            AppListViewTests.descendant(of: controller.view, identifier: identifier) as? View,
            identifier)
    }

    // MARK: - C-HIER-05: the focus in the list

    @MainActor
    func test_C_HIER_05_aFocusReloadsTheListOnce() throws {
        let (model, controller) = try loaded()
        let reloads = controller.reloadCount
        model.focus(on: 6)
        XCTAssertEqual(controller.reloadCount, reloads + 1)
    }

    // MARK: - C-HIER-04: the search

    /// Types into the search field as the user does: the field's text, then its action. Then
    /// waits out the pause after typing, until the model has the text.
    @MainActor
    private func search(_ text: String, in controller: HierarchyViewController) throws {
        try typeSearch(text, in: controller)
        let deadline = Date().addingTimeInterval(2)
        while controller.store.searchText != text, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertEqual(controller.store.searchText, text, "the search reached the model")
    }

    /// The field's text, then its action, as a keystroke sends it; without waiting.
    @MainActor
    private func typeSearch(_ text: String, in controller: HierarchyViewController) throws {
        let field = try view(
            HierarchyViewController.searchIdentifier, in: controller, as: NSSearchField.self)
        field.stringValue = text
        XCTAssertTrue(field.sendAction(field.action, to: field.target))
    }

    /// Turns the main run loop for a while.
    @MainActor
    private func wait(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Typing a word quickly on a large tree filtered it once for each letter (found in
    /// review): the field's text reaches the model once the typing pauses.
    @MainActor
    func test_C_HIER_04_aWordTypedQuicklyIsOneSearch() throws {
        let (model, controller) = try loaded()
        var published: [String] = []
        let subscription = model.$searchText.dropFirst().sink { published.append($0) }
        defer { subscription.cancel() }
        let reloads = controller.reloadCount
        for prefix in ["l", "la", "lab", "labe", "label"] {
            try typeSearch(prefix, in: controller)
            wait(0.01)
        }
        XCTAssertEqual(published, [], "nothing while the typing goes on")
        XCTAssertEqual(model.searchText, "")
        wait(DebouncedSearchInput.delay + 0.2)
        XCTAssertEqual(published, ["label"])
        XCTAssertEqual(controller.reloadCount, reloads + 1)
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 6, 7, 13, 14])
    }

    @MainActor
    func test_C_HIER_04_clearingTheFieldEndsTheSearchAtOnce() throws {
        let (model, controller) = try loaded()
        try search("label", in: controller)
        // Typing still waiting is dropped, not applied after the clearing.
        try typeSearch("labe", in: controller)
        try typeSearch("", in: controller)
        XCTAssertEqual(model.searchText, "")
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 10, 11, 12, 5, 6, 7, 8, 9, 13, 14])
        wait(DebouncedSearchInput.delay + 0.2)
        XCTAssertEqual(model.searchText, "")
    }

    /// Found in review: a search text the model set itself came back to it from the field,
    /// inside the publishing, and was published twice. Typing still waiting is dropped.
    @MainActor
    func test_C_HIER_04_aSearchTheModelSetsIsPublishedOnce() throws {
        let (model, controller) = try loaded()
        var published: [String] = []
        let subscription = model.$searchText.dropFirst().sink { published.append($0) }
        defer { subscription.cancel() }
        try typeSearch("lab", in: controller)
        model.setSearchText("label")
        XCTAssertEqual(published, ["label"])
        wait(DebouncedSearchInput.delay + 0.2)
        XCTAssertEqual(published, ["label"], "the typing that waited is not applied after")
        XCTAssertEqual(model.searchText, "label")
    }

    /// Found in review: typing still waiting when the list went away never reached the
    /// model, so the inspection's settings lost it (C-WIN-04).
    @MainActor
    func test_C_HIER_04_typingStillWaitingReachesTheModelWhenTheListGoesAway() throws {
        let (model, controller) = try loaded()
        var published: [String] = []
        let subscription = model.$searchText.dropFirst().sink { published.append($0) }
        defer { subscription.cancel() }
        try typeSearch("label", in: controller)
        XCTAssertEqual(model.searchText, "")
        controller.viewWillDisappear()
        XCTAssertEqual(model.searchText, "label")
        wait(DebouncedSearchInput.delay + 0.2)
        XCTAssertEqual(published, ["label"], "and only once")
    }

    @MainActor
    func test_C_HIER_04_clearingTheSearchBringsBackTheRowsAsTheyWere() throws {
        let (model, controller) = try loaded()
        model.setExpanded(4, false)
        let before = layers(of: controller)
        try search("label", in: controller)
        try search("", in: controller)
        XCTAssertEqual(layers(of: controller), before)
        XCTAssertFalse(model.isExpanded(4))
    }

    @MainActor
    func test_C_HIER_04_collapsingARowOfTheSearchLeavesTheModelAlone() throws {
        let (model, controller) = try loaded()
        try search("label", in: controller)
        let revision = model.expansionRevision
        let row = try XCTUnwrap(layers(of: controller).firstIndex(of: 6))
        controller.outlineView.collapseItem(controller.outlineView.item(atRow: row))
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 6, 13, 14])
        XCTAssertEqual(model.expansionRevision, revision)
        XCTAssertTrue(model.isExpanded(6))
    }

    @MainActor
    func test_C_HIER_04_selectingARowOfTheSearchRevealsIt() throws {
        let (model, controller) = try loaded()
        model.setExpanded(6, false)
        try search("label", in: controller)
        let row = try XCTUnwrap(layers(of: controller).firstIndex(of: 7))
        controller.outlineView.selectRowIndexes([row], byExtendingSelection: false)
        XCTAssertEqual(model.selectedLayerID, 7)
        XCTAssertTrue(model.isExpanded(6))
        try search("", in: controller)
        XCTAssertEqual(controller.outlineView.selectedRow, layers(of: controller).firstIndex(of: 7))
    }

    @MainActor
    func test_C_HIER_04_aSelectionTheSearchLeavesOutIsKept() throws {
        let (model, controller) = try loaded()
        model.select(8)
        try search("label", in: controller)
        XCTAssertEqual(controller.outlineView.selectedRow, -1)
        XCTAssertEqual(model.selectedLayerID, 8)
    }

    @MainActor
    func test_C_HIER_04_theFieldShowsTheModelsTextOnlyWhenItDiffers() throws {
        let (model, controller) = try loaded()
        let field = try view(
            HierarchyViewController.searchIdentifier, in: controller, as: NSSearchField.self)
        model.setSearchText("card")
        XCTAssertEqual(field.stringValue, "card", "a list made later shows the search")
        // The user typed; the model publishes the same text back and the field is left alone.
        field.stringValue = "label"
        XCTAssertTrue(field.sendAction(field.action, to: field.target))
        XCTAssertEqual(field.stringValue, "label")
    }

    // MARK: - C-HIER-06: levels

    @MainActor
    private func expandButton(_ controller: HierarchyViewController) throws -> NSPopUpButton {
        try view(HierarchyViewController.expandIdentifier, in: controller, as: NSPopUpButton.self)
    }

    /// Chooses an item of the expand menu as a click does.
    @MainActor
    private func choose(_ title: String, in controller: HierarchyViewController) throws {
        let button = try expandButton(controller)
        let index = button.indexOfItem(withTitle: title)
        XCTAssertGreaterThan(index, 0, title)
        button.selectItem(at: index)
        XCTAssertTrue(button.sendAction(button.action, to: button.target))
    }

    @MainActor
    private func expandedRows(_ controller: HierarchyViewController) -> [UInt64] {
        (0..<controller.outlineView.numberOfRows).compactMap { row in
            controller.outlineView.isItemExpanded(controller.outlineView.item(atRow: row))
                ? controller.layerID(atRow: row) : nil
        }
    }

    // MARK: - The sidebar's header: expansion menu, search and path

    @MainActor
    func test_C_HIER_06_theMenuWorksEveryTimeItIsChosen() throws {
        let (model, controller) = try loaded()
        try choose("Expand to Level 2", in: controller)
        XCTAssertEqual(model.tree.ids.filter(model.isExpanded), [1, 2])
        try choose("Collapse All", in: controller)
        XCTAssertEqual(layers(of: controller), [1])
        try choose("Expand to Level 2", in: controller)
        XCTAssertEqual(model.tree.ids.filter(model.isExpanded), [1, 2])
        // The same item again, after the expansion was changed by hand.
        model.collapseAll()
        try choose("Expand to Level 2", in: controller)
        XCTAssertEqual(model.tree.ids.filter(model.isExpanded), [1, 2])
        XCTAssertEqual(expandedRows(controller), [1, 2])
    }

    @MainActor
    func test_C_HIER_06_theListFollowsExpansionTheModelMakes() throws {
        let (model, controller) = try loaded()
        let reloads = controller.reloadCount
        model.expand(toDepth: 2)
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 6, 8, 9, 13])
        model.expandAll()
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 10, 11, 12, 5, 6, 7, 8, 9, 13, 14])
        XCTAssertEqual(controller.reloadCount, reloads, "followed, not reloaded")
        // A row the user collapses is recorded once and not applied back.
        let row = try XCTUnwrap(layers(of: controller).firstIndex(of: 4))
        controller.outlineView.collapseItem(controller.outlineView.item(atRow: row))
        XCTAssertFalse(model.isExpanded(4))
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 6, 7, 8, 9, 13, 14])
    }

    @MainActor
    func test_C_DET_07_theContextMenuRefreshesTheClickedRowsSubtree() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        model.enter()
        model.canRefreshSubtrees = true
        model.apply(try Fixtures.hierarchy())
        let controller = HierarchyViewController(store: model, appName: "Demo")
        _ = controller.view
        let menu = try XCTUnwrap(controller.outlineView.menu)
        controller.contextMenu(menu, forRow: 3)  // CardView
        XCTAssertEqual(
            menu.items.map(\.title), ["Focus on Layer", "Refresh Subtree"] + Self.lldbTitles + Self.exportTitles)
        let refresh = menu.items[1]
        XCTAssertTrue(
            NSApp.sendAction(try XCTUnwrap(refresh.action), to: refresh.target, from: refresh))
        // The first hierarchy is still on its way here, so the subtree waits for it.
        XCTAssertTrue(model.loadingSubtree == 4 || model.queuedSubtrees == [4])
        XCTAssertNil(model.selectedLayerID, "the clicked row, not the selection")

        // A server that cannot send subtrees gets no such item (C-HIER-05's test has the rest).
        model.canRefreshSubtrees = false
        controller.contextMenu(menu, forRow: 3)
        XCTAssertEqual(menu.items.map(\.title), ["Focus on Layer"] + Self.lldbTitles + Self.exportTitles)
    }

    /// The fixtures' layers have addresses: copying an LLDB command for one (C-SRC-06).
    private static let lldbTitles = ["", "Copy LLDB Command"]

    /// What follows a row's own commands: exporting its screenshot (C-ARCH-06).
    private static let exportTitles = [
        "", "Export Layer Screenshot\u{2026}", "Export Screenshot with Sublayers\u{2026}",
    ]

    @MainActor
    func test_C_HIER_05_nothingCanBeChangedOnceDisconnected() throws {
        let (model, controller) = try loaded()
        model.focus(on: 4)
        model.connectionLost()
        let field = try view(
            HierarchyViewController.searchIdentifier, in: controller, as: NSSearchField.self)
        XCTAssertFalse(field.isEnabled)
        XCTAssertFalse(try expandButton(controller).isEnabled)
        XCTAssertFalse(try view(
            HierarchyViewController.pathIdentifier, in: controller, as: NSPathControl.self
        ).isEnabled)
        XCTAssertFalse(try view(
            HierarchyViewController.leaveFocusIdentifier, in: controller, as: NSButton.self
        ).isEnabled)
        let menu = try XCTUnwrap(controller.outlineView.menu)
        controller.contextMenu(menu, forRow: 0)
        XCTAssertEqual(menu.items, [])
    }

    // MARK: - Found in review

    @MainActor
    func test_C_HIER_04_collapsingARowOfTheSearchKeepsTheSelection() throws {
        let (model, controller) = try loaded()
        model.select(7)
        try search("label", in: controller)
        let row = try XCTUnwrap(layers(of: controller).firstIndex(of: 6))
        controller.outlineView.collapseItem(controller.outlineView.item(atRow: row))
        XCTAssertEqual(model.selectedLayerID, 7)
        try search("", in: controller)
        XCTAssertEqual(controller.outlineView.selectedRow, layers(of: controller).firstIndex(of: 7))
    }

    @MainActor
    func test_C_HIER_06_whatTheListExpandsItselfIsNotAppliedBack() throws {
        let (model, controller) = try loaded()
        let followed = controller.followedExpansions
        let row = try XCTUnwrap(layers(of: controller).firstIndex(of: 4))
        controller.outlineView.collapseItem(controller.outlineView.item(atRow: row))
        XCTAssertFalse(model.isExpanded(4))
        XCTAssertEqual(controller.followedExpansions, followed)
        model.setExpanded(4, true)
        XCTAssertEqual(controller.followedExpansions, followed + 1)
    }

    @MainActor
    func test_C_HIER_05_thePathGoesWhenAReloadEndsTheFocus() throws {
        let (model, controller) = try loaded()
        let path = try view(
            HierarchyViewController.pathIdentifier, in: controller, as: NSPathControl.self)
        model.focus(on: 6)
        XCTAssertTrue(isShown(path))
        var hierarchy = try Fixtures.hierarchy()
        hierarchy.nodes.removeAll { $0.id == 6 || $0.id == 7 }
        model.apply(hierarchy)
        XCTAssertFalse(isShown(path))
        XCTAssertEqual(layers(of: controller).first, 1)
    }
}
