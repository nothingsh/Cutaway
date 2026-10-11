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
    func test_C_HIER_05_theFocusedLayerIsTheListsRoot() throws {
        let (model, controller) = try loaded()
        model.focus(on: 4)
        XCTAssertEqual(layers(of: controller), [4, 5])
        XCTAssertEqual(levels(of: controller), [0, 1])
        model.focus(on: nil)
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 5, 6, 7, 8, 9])
    }

    @MainActor
    func test_C_HIER_05_theListKeepsTheModelsExpansionInTheFocus() throws {
        let (model, controller) = try loaded()
        model.setExpanded(6, false)
        model.focus(on: 2)
        XCTAssertEqual(layers(of: controller), [2, 3, 4, 5, 6, 8, 9])
    }

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
        wait(HierarchyViewController.searchDelay + 0.2)
        XCTAssertEqual(published, ["label"])
        XCTAssertEqual(controller.reloadCount, reloads + 1)
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 6, 7])
    }

    @MainActor
    func test_C_HIER_04_clearingTheFieldEndsTheSearchAtOnce() throws {
        let (model, controller) = try loaded()
        try search("label", in: controller)
        // Typing still waiting is dropped, not applied after the clearing.
        try typeSearch("labe", in: controller)
        try typeSearch("", in: controller)
        XCTAssertEqual(model.searchText, "")
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 5, 6, 7, 8, 9])
        wait(HierarchyViewController.searchDelay + 0.2)
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
        wait(HierarchyViewController.searchDelay + 0.2)
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
        wait(HierarchyViewController.searchDelay + 0.2)
        XCTAssertEqual(published, ["label"], "and only once")
    }

    /// Return in the field, through its field editor as the keyboard does.
    @MainActor
    func test_C_HIER_04_returnRunsTheSearchAtOnce() throws {
        let (model, controller) = try loaded()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 300), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        let field = try view(
            HierarchyViewController.searchIdentifier, in: controller, as: NSSearchField.self)
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.string = "label"
        editor.didChangeText()
        XCTAssertEqual(model.searchText, "", "typing waits")
        editor.insertNewline(nil)
        XCTAssertEqual(model.searchText, "label")
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 6, 7])
    }

    @MainActor
    func test_C_HIER_04_theListShowsTheMatchesAndTheirAncestors() throws {
        let (model, controller) = try loaded()
        try search("label", in: controller)
        XCTAssertEqual(model.searchText, "label")
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 6, 7])
        XCTAssertEqual(levels(of: controller), [0, 1, 2, 2, 3])
    }

    @MainActor
    func test_C_HIER_04_ancestorsThatDoNotMatchAreWeaker() throws {
        let (_, controller) = try loaded()
        try search("label", in: controller)
        let colors = (0..<5).map { controller.rowView($0)?.titleColor }
        XCTAssertEqual(colors, [
            .secondaryLabelColor, .secondaryLabelColor, .labelColor, .secondaryLabelColor,
            .labelColor,
        ])
    }

    @MainActor
    func test_C_HIER_04_aHiddenMatchStaysDimmed() throws {
        let (_, controller) = try loaded()
        try search("shape", in: controller)
        XCTAssertEqual(layers(of: controller), [1, 2, 4, 5])
        XCTAssertEqual(controller.rowView(3)?.titleColor, .tertiaryLabelColor)
        XCTAssertEqual(controller.rowView(3)?.isDimmed, true)
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
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 6])
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
    func test_C_HIER_04_noMatchesAreExplained() throws {
        let (_, controller) = try loaded()
        try search("  button ", in: controller)
        let status = try view(
            HierarchyViewController.statusIdentifier, in: controller, as: NSTextField.self)
        XCTAssertEqual(status.stringValue, "No layers match “button”.")
        XCTAssertTrue(isShown(status))
        let field = try view(
            HierarchyViewController.searchIdentifier, in: controller, as: NSSearchField.self)
        XCTAssertTrue(isShown(field), "the search can be cleared")
    }

    @MainActor
    func test_C_HIER_04_theFooterCountsTheMatches() throws {
        let (_, controller) = try loaded()
        let count = try view(
            HierarchyViewController.countIdentifier, in: controller, as: NSTextField.self)
        try search("label", in: controller)
        XCTAssertEqual(count.stringValue, "2 matches")
        try search("scroll", in: controller)
        XCTAssertEqual(count.stringValue, "1 match")
        try search("", in: controller)
        XCTAssertEqual(count.stringValue, "9 layers · 1 hidden")
    }

    @MainActor
    func test_C_HIER_05_theFooterCountsTheFocus() throws {
        let (model, controller) = try loaded()
        let count = try view(
            HierarchyViewController.countIdentifier, in: controller, as: NSTextField.self)
        model.focus(on: 4)
        XCTAssertEqual(count.stringValue, "2 layers · 1 hidden")
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

    @MainActor
    func test_C_HIER_06_theMenuHasALevelForEachDepth() throws {
        let (model, controller) = try loaded()
        let titles = try expandButton(controller).itemTitles.dropFirst().filter { !$0.isEmpty }
        XCTAssertEqual(titles, [
            "Collapse All", "Expand to Level 1", "Expand to Level 2", "Expand to Level 3",
            "Expand All",
        ])
        model.focus(on: 9)
        XCTAssertEqual(
            try expandButton(controller).itemTitles.dropFirst().filter { !$0.isEmpty },
            ["Collapse All", "Expand All"])
    }

    @MainActor
    func test_C_HIER_06_expandingToLevelTwo() throws {
        let (model, controller) = try loaded()
        try choose("Expand to Level 2", in: controller)
        XCTAssertEqual(model.tree.ids.filter(model.isExpanded), [1, 2])
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 6, 8, 9])
        XCTAssertEqual(expandedRows(controller), [1, 2])
    }

    @MainActor
    func test_C_HIER_06_collapsingAndExpandingEverything() throws {
        let (_, controller) = try loaded()
        try choose("Collapse All", in: controller)
        XCTAssertEqual(layers(of: controller), [1])
        try choose("Expand All", in: controller)
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 5, 6, 7, 8, 9])
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

    /// The search field and the expand button are below the toolbar, not under the title
    /// bar's row with the window's buttons.
    @MainActor
    func test_C_HIER_04_theSearchIsBelowTheToolbar() throws {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        let inspector = InspectorWindowController(
            location: .simulator(port: 48160), entry: nil, store: model)
        let window = try XCTUnwrap(inspector.window)
        window.layoutIfNeeded()
        let controller = inspector.splitController.hierarchyController
        // Where the toolbar ends: the top of the area the content can use unobscured.
        let visibleTop = window.contentLayoutRect.maxY
        XCTAssertLessThan(visibleTop, window.contentView?.bounds.maxY ?? 0, "a toolbar")
        for view in [controller.searchField, controller.expandButton] as [NSView] {
            let frame = view.convert(view.bounds, to: nil)
            XCTAssertTrue(isShown(view))
            XCTAssertGreaterThan(frame.height, 0)
            XCTAssertLessThanOrEqual(frame.maxY, visibleTop, "\(type(of: view))")
        }
        inspector.close()
    }

    @MainActor
    func test_C_HIER_06_theListFollowsExpansionTheModelMakes() throws {
        let (model, controller) = try loaded()
        let reloads = controller.reloadCount
        model.expand(toDepth: 2)
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 6, 8, 9])
        model.expandAll()
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(controller.reloadCount, reloads, "followed, not reloaded")
        // A row the user collapses is recorded once and not applied back.
        let row = try XCTUnwrap(layers(of: controller).firstIndex(of: 4))
        controller.outlineView.collapseItem(controller.outlineView.item(atRow: row))
        XCTAssertFalse(model.isExpanded(4))
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 6, 7, 8, 9])
    }

    @MainActor
    func test_C_HIER_06_theMenuIsNotAvailableDuringASearch() throws {
        let (_, controller) = try loaded()
        XCTAssertTrue(try expandButton(controller).isEnabled)
        try search("label", in: controller)
        XCTAssertFalse(try expandButton(controller).isEnabled)
        try search("", in: controller)
        XCTAssertTrue(try expandButton(controller).isEnabled)
    }

    @MainActor
    func test_C_HIER_05_thePathShowsTheWayDownToTheFocus() throws {
        let (model, controller) = try loaded()
        let path = try view(
            HierarchyViewController.pathIdentifier, in: controller, as: NSPathControl.self)
        XCTAssertFalse(isShown(path))
        model.focus(on: 5)
        XCTAssertTrue(isShown(path))
        XCTAssertEqual(
            path.pathItems.map(\.title), ["UIWindow", "UIView", "CardView", "CAShapeLayer"])
    }

    @MainActor
    func test_C_HIER_05_thePathsSymbolsAreSquareSoTheyAreNotStretched() throws {
        let (model, controller) = try loaded()
        let path = try view(
            HierarchyViewController.pathIdentifier, in: controller, as: NSPathControl.self)
        model.focus(on: 5)
        // The path control draws each item's image into a square; the window's symbol is
        // wider than it is tall.
        for item in path.pathItems {
            let image = try XCTUnwrap(item.image, item.title)
            XCTAssertEqual(image.size.width, image.size.height, item.title)
            XCTAssertTrue(image.isTemplate, item.title)
        }
    }

    @MainActor
    func test_C_HIER_05_aStepOfThePathFocusesThere() throws {
        let (model, controller) = try loaded()
        model.focus(on: 5)
        controller.pathStepWasClicked(at: 1)
        XCTAssertEqual(model.focusedLayerID, 2)
        XCTAssertEqual(layers(of: controller).first, 2)
    }

    /// The button that shows all layers keeps to the row's trailing edge: after a short path
    /// it does not follow the path, and a long path is cut short before it rather than push
    /// it out of sight (2026-10-07, reported in use).
    @MainActor
    func test_C_HIER_05_theButtonStaysAtTheTrailingEdgeWhateverThePath() throws {
        // The fixture, and under its card a chain of views with long names, 12 deep.
        var hierarchy = try Fixtures.hierarchy()
        let view = try XCTUnwrap(hierarchy.nodes.first { $0.id == 9 })
        for id in UInt64(20)..<32 {
            var node = view
            node.id = id
            node.parentID = id == 20 ? 4 : id - 1
            node.viewDisplayClassName = "NavigationBarPlatterContainer\(id)"
            hierarchy.nodes.append(node)
        }
        let (model, controller, window) = try inWindow(width: 280, hierarchy)
        let path = try self.view(
            HierarchyViewController.pathIdentifier, in: controller, as: NSPathControl.self)
        let button = try self.view(
            HierarchyViewController.leaveFocusIdentifier, in: controller, as: NSButton.self)
        func frame(_ view: NSView) -> NSRect { view.convert(view.bounds, to: controller.view) }

        model.focus(on: 2)
        window.layoutIfNeeded()
        let trailing = frame(button).maxX
        XCTAssertEqual(trailing, controller.view.bounds.maxX - 10, accuracy: 1, "after a short path")

        model.focus(on: 31)
        window.layoutIfNeeded()
        XCTAssertTrue(isShown(button))
        XCTAssertEqual(frame(button).maxX, trailing, accuracy: 0.5, "after a long path")
        XCTAssertLessThanOrEqual(frame(path).maxX, frame(button).minX)

        // A wider list, and from the long path its first step, as in the report: the button
        // follows the edge, not the path.
        window.setContentSize(NSSize(width: 420, height: 500))
        window.layoutIfNeeded()
        controller.pathStepWasClicked(at: 0)
        window.layoutIfNeeded()
        XCTAssertEqual(model.focusedLayerID, 1)
        XCTAssertEqual(
            frame(button).maxX, controller.view.bounds.maxX - 10, accuracy: 1, "after the first step")
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_HIER_05_theButtonShowsAllLayers() throws {
        let (model, controller) = try loaded()
        model.focus(on: 4)
        let button = try view(
            HierarchyViewController.leaveFocusIdentifier, in: controller, as: NSButton.self)
        button.performClick(nil)
        XCTAssertNil(model.focusedLayerID)
    }

    @MainActor
    func test_C_HIER_05_theContextMenuFocusesOnTheClickedRow() throws {
        let (model, controller) = try loaded()
        let menu = try XCTUnwrap(controller.outlineView.menu)
        controller.contextMenu(menu, forRow: 3)  // CardView
        XCTAssertEqual(menu.items.map(\.title), ["Focus on Layer"] + Self.exportTitles)
        let focus = try XCTUnwrap(menu.items.first)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(focus.action), to: focus.target, from: focus))
        XCTAssertEqual(model.focusedLayerID, 4)

        controller.contextMenu(menu, forRow: 0)
        XCTAssertEqual(
            menu.items.map(\.title), ["Focus on Layer"] + Self.exportTitles + ["Show All Layers"])
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
            menu.items.map(\.title), ["Focus on Layer", "Refresh Subtree"] + Self.exportTitles)
        let refresh = menu.items[1]
        XCTAssertTrue(
            NSApp.sendAction(try XCTUnwrap(refresh.action), to: refresh.target, from: refresh))
        // The first hierarchy is still on its way here, so the subtree waits for it.
        XCTAssertTrue(model.loadingSubtree == 4 || model.queuedSubtrees == [4])
        XCTAssertNil(model.selectedLayerID, "the clicked row, not the selection")

        // A server that cannot send subtrees gets no such item (C-HIER-05's test has the rest).
        model.canRefreshSubtrees = false
        controller.contextMenu(menu, forRow: 3)
        XCTAssertEqual(menu.items.map(\.title), ["Focus on Layer"] + Self.exportTitles)
    }

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
    func test_C_HIER_04_clickingBesideTheRowsOfTheSearchStillDeselects() throws {
        let (model, controller) = try loaded()
        model.select(7)
        try search("label", in: controller)
        controller.outlineView.deselectAll(nil)
        XCTAssertNil(model.selectedLayerID)
    }

    @MainActor
    func test_C_HIER_01_aTreeThatArrivesDuringASearchWithoutMatchesIsSizedForLater() throws {
        let widths = try [nil, "zzz"].map { text -> CGFloat in
            let model = InspectionStore(
                session: Session(channel: InertChannel(), client: Self.client),
                newLayers: .expanded)
            let controller = HierarchyViewController(store: model, appName: "Demo")
            _ = controller.view
            if let text { model.setSearchText(text) }
            model.apply(try Fixtures.hierarchy())
            model.setSearchText("")
            return try XCTUnwrap(controller.outlineView.tableColumns.first).width
        }
        XCTAssertEqual(widths[1], widths[0])
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

    // MARK: - C-HIER-07: view controllers and members on the rows

    @MainActor
    private func detail(
        of id: UInt64, in controller: HierarchyViewController
    ) throws -> NSTextField {
        let row = try XCTUnwrap(layers(of: controller).firstIndex(of: id), "layer \(id) has no row")
        let view = try XCTUnwrap(controller.rowView(row))
        return try XCTUnwrap(
            AppListViewTests.descendant(of: view, identifier: HierarchyRowView.detailIdentifier)
                as? NSTextField)
    }

    @MainActor
    func test_C_HIER_07_aRowNamesItsViewControllerOrTheMemberThatHoldsIt() throws {
        let (_, controller) = try loaded()
        XCTAssertEqual(try detail(of: 2, in: controller).stringValue, "HomeViewController")
        XCTAssertEqual(
            try detail(of: 3, in: controller).stringValue, "HomeViewController.titleLabel")
        XCTAssertEqual(try detail(of: 5, in: controller).stringValue, "CardView.badgeLayer +1")
        XCTAssertEqual(
            try detail(of: 8, in: controller).stringValue, "DMBaseViewController._dividerLayer")
        for id: UInt64 in [1, 7, 9] {
            XCTAssertTrue(try detail(of: id, in: controller).isHidden, "layer \(id)")
        }
        XCTAssertFalse(try detail(of: 3, in: controller).isHidden)
    }

    @MainActor
    func test_C_HIER_07_theTooltipListsEverything() throws {
        let (_, controller) = try loaded()
        let row = try XCTUnwrap(layers(of: controller).firstIndex(of: 5))
        XCTAssertEqual(
            controller.rowView(row)?.toolTip,
            "Referenced by CardView.badgeLayer\nReferenced by HomeViewController.cardBadge")
        let two = try XCTUnwrap(layers(of: controller).firstIndex(of: 2))
        XCTAssertEqual(controller.rowView(two)?.toolTip, "View controller HomeViewController")
        XCTAssertNil(controller.rowView(0)?.toolTip)
    }

    @MainActor
    func test_C_HIER_07_aHiddenRowsDetailIsWeakerToo() throws {
        let (_, controller) = try loaded()
        XCTAssertEqual(try detail(of: 3, in: controller).textColor, .secondaryLabelColor)
        XCTAssertEqual(try detail(of: 5, in: controller).textColor, .tertiaryLabelColor)
    }

    @MainActor
    func test_C_HIER_07_aDetailGivesWayRatherThanWidenTheList() throws {
        // The same tree without the fields of protocol 0.2.
        var plain = try Fixtures.hierarchy()
        for index in plain.nodes.indices {
            plain.nodes[index].viewControllerClassName = nil
            plain.nodes[index].viewControllerDisplayClassName = nil
            plain.nodes[index].memberReferences = []
        }
        let widths = try [try Fixtures.hierarchy(), plain].map { hierarchy -> CGFloat in
            let model = InspectionStore(
                session: Session(channel: InertChannel(), client: Self.client),
                newLayers: .expanded)
            model.apply(hierarchy)
            let controller = HierarchyViewController(store: model, appName: "Demo")
            _ = controller.view
            return try XCTUnwrap(controller.outlineView.tableColumns.first).width
        }
        // As wide as the titles need, so that a deep row's title is never cut off: the default
        // sidebar still shows the fixture without scrolling sideways; the tooltip and the
        // panel's header have the rest.
        XCTAssertEqual(widths[0], widths[1])
        let (_, controller) = try loaded()
        XCTAssertLessThan(
            try detail(of: 8, in: controller).contentCompressionResistancePriority(
                for: .horizontal),
            NSLayoutConstraint.Priority.defaultHigh, "the detail is cut short first")
    }

    // MARK: - C-HIER-07: found in review

    /// A list showing the `hierarchy` fixture in a window that is never shown.
    @MainActor
    private func inWindow(
        width: CGFloat, _ hierarchy: Hierarchy? = nil
    ) throws -> (InspectionStore, HierarchyViewController, NSWindow) {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        let controller = HierarchyViewController(store: model, appName: "Demo")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 500), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: width, height: 500))
        model.apply(try hierarchy ?? Fixtures.hierarchy())
        window.layoutIfNeeded()
        return (model, controller, window)
    }

    /// The detail of a row as the outline shows it, not a fresh one.
    @MainActor
    private func shownDetail(
        of id: UInt64, in controller: HierarchyViewController
    ) throws -> NSTextField {
        let row = try XCTUnwrap(layers(of: controller).firstIndex(of: id))
        let view = try XCTUnwrap(
            controller.outlineView.view(atColumn: 0, row: row, makeIfNecessary: false))
        return try XCTUnwrap(
            AppListViewTests.descendant(of: view, identifier: HierarchyRowView.detailIdentifier)
                as? NSTextField)
    }

    @MainActor
    func test_C_HIER_07_detailsUseTheRoomTheListHas() throws {
        let (_, controller, window) = try inWindow(width: 340)
        for id: UInt64 in [2, 3] {
            let detail = try shownDetail(of: id, in: controller)
            XCTAssertGreaterThanOrEqual(
                detail.frame.width, detail.intrinsicContentSize.width - 0.5, "layer \(id)")
        }
        // And still nothing to scroll to sideways.
        let scrollView = try XCTUnwrap(controller.outlineView.enclosingScrollView)
        XCTAssertLessThanOrEqual(
            controller.outlineView.frame.width, scrollView.contentView.bounds.width)

        // A wider list gives the details more.
        window.setContentSize(NSSize(width: 520, height: 500))
        window.layoutIfNeeded()
        let eight = try shownDetail(of: 8, in: controller)
        XCTAssertGreaterThanOrEqual(eight.frame.width, eight.intrinsicContentSize.width - 0.5)
        XCTAssertLessThanOrEqual(
            controller.outlineView.frame.width, scrollView.contentView.bounds.width)
    }

    @MainActor
    func test_C_HIER_07_aNewTreeWithOtherMembersShowsThem() throws {
        let (model, controller, window) = try inWindow(width: 340)
        var changed = try Fixtures.hierarchy()
        let three = try XCTUnwrap(changed.nodes.firstIndex { $0.id == 3 })
        changed.nodes[three].memberReferences = [
            MemberReference(ownerClassName: "X", ownerDisplayClassName: "X", name: "changed"),
        ]
        model.apply(changed)
        window.layoutIfNeeded()
        XCTAssertEqual(try shownDetail(of: 3, in: controller).stringValue, "X.changed")
        let row = try XCTUnwrap(layers(of: controller).firstIndex(of: 3))
        XCTAssertEqual(
            controller.outlineView.view(atColumn: 0, row: row, makeIfNecessary: false)?.toolTip,
            "Referenced by X.changed")
        withExtendedLifetime(window) {}
    }
}
