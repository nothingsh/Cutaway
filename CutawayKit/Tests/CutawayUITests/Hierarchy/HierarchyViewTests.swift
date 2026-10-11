import AppKit
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// The hierarchy list as it is shown: C-HIER-01, C-HIER-02, C-HIER-03. The outline is checked
/// by its rows, not by eye.
final class HierarchyViewTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    @MainActor
    private func model() -> InspectionStore {
        InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
    }

    /// A controller with its view loaded.
    @MainActor
    private func controller(for model: InspectionStore) -> HierarchyViewController {
        let controller = HierarchyViewController(store: model, appName: "Demo")
        _ = controller.view
        return controller
    }

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
    private func status(of controller: HierarchyViewController) throws -> NSTextField {
        try XCTUnwrap(AppListViewTests.descendant(
            of: controller.view, identifier: HierarchyViewController.statusIdentifier)
            as? NSTextField)
    }

    /// The layer IDs of the rows, top to bottom.
    @MainActor
    private func layers(of controller: HierarchyViewController) -> [UInt64?] {
        (0..<controller.outlineView.numberOfRows).map(controller.layerID(atRow:))
    }

    /// The outline view's item for a layer that has a row.
    @MainActor
    private func item(_ id: UInt64, in controller: HierarchyViewController) throws -> Any {
        let row = try XCTUnwrap(layers(of: controller).firstIndex(of: id), "layer \(id) has no row")
        return try XCTUnwrap(controller.outlineView.item(atRow: row))
    }

    /// The fixture without layer 8 and with a new layer 10 under layer 2.
    private func changedHierarchy() throws -> Hierarchy {
        var hierarchy = try Fixtures.hierarchy()
        var extra = try XCTUnwrap(hierarchy.nodes.first { $0.id == 9 })
        extra.id = 10
        hierarchy.nodes.removeAll { $0.id == 8 }
        hierarchy.nodes.append(extra)
        return hierarchy
    }

    // MARK: - C-HIER-01: the tree

    @MainActor
    func test_C_HIER_01_theOutlineShowsTheNineNodesOfTheFixture() throws {
        let model = model()
        let controller = controller(for: model)
        model.apply(try Fixtures.hierarchy())
        let outline = controller.outlineView

        XCTAssertEqual(outline.numberOfRows, 9)
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual((0..<9).map(outline.level(forRow:)), [0, 1, 2, 2, 3, 2, 3, 2, 2])

        let titles = try (0..<9).map { row in
            try XCTUnwrap(AppListViewTests.descendant(
                of: try XCTUnwrap(controller.rowView(row)),
                identifier: HierarchyRowView.titleIdentifier) as? NSTextField).stringValue
        }
        XCTAssertEqual(titles, [
            "UIWindow", "UIView", "UILabel", "CardView", "CAShapeLayer", "UIScrollView",
            "UILabel", "CALayer", "UIView",
        ])

        // Parents, as the outline view sees them: row 4 (layer 5) is inside row 3 (layer 4).
        let parents = (0..<9).map { row -> Int in
            outline.row(forItem: outline.parent(forItem: outline.item(atRow: row)))
        }
        XCTAssertEqual(parents, [-1, 0, 1, 1, 3, 1, 5, 1, 1])
        XCTAssertTrue(isShown(outline))
        XCTAssertFalse(isShown(try status(of: controller)))
    }

    @MainActor
    func test_C_HIER_01_aTreeOfThousandsOfLayersIsShown() {
        // 3,000 layers; layer n is inside layer n / 2.
        let nodes = (1...3_000).map { id in
            LayerNode(
                id: UInt64(id), parentID: UInt64(id / 2), className: "CALayer",
                displayClassName: "CALayer", viewClassName: nil, viewDisplayClassName: nil,
                bounds: nil, position: nil, anchorPoint: nil, transform: nil, zPosition: 0,
                isHidden: false, opacity: 1, masksToBounds: false)
        }
        let model = model()
        let controller = controller(for: model)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            model.apply(Hierarchy(nodes: nodes, keyWindowID: 1))
        }

        XCTAssertEqual(controller.outlineView.numberOfRows, 3_000)
        XCTAssertLessThan(elapsed, .seconds(5), "showing 3,000 layers took \(elapsed)")
    }

    /// The outline view collapses every expanded row inside a row that is collapsed, each with
    /// its own notification, and expands them again with the row; the model used to lay the
    /// tree out again for each: about ten seconds each way for the root of this tree.
    @MainActor
    func test_C_HIER_02_collapsingARowWithThousandsExpandedInsideLaysTheTreeOutOnce() {
        // 3,000 layers; layer n is inside layer n / 2.
        let nodes = (1...3_000).map { Self.plainNode(UInt64($0), parent: UInt64($0 / 2)) }
        let model = model()
        let controller = controller(for: model)
        layOut(controller)
        model.apply(Hierarchy(nodes: nodes, keyWindowID: 1))
        let outline = controller.outlineView
        model.select(3_000)

        // As "Collapse All" does it, for comparison: the model collapses the rows.
        var start = ContinuousClock.now
        model.collapseAll()
        let fromTheMenu = ContinuousClock.now - start
        model.expandAll()
        XCTAssertEqual(outline.numberOfRows, 3_000)

        var builds = model.geometryBuildCount
        start = ContinuousClock.now
        outline.collapseItem(outline.item(atRow: 0))
        let collapsing = ContinuousClock.now - start
        XCTAssertEqual(outline.numberOfRows, 1)
        XCTAssertFalse(model.isExpanded(1))
        XCTAssertTrue(model.isExpanded(2), "the rows inside keep their expansion")
        XCTAssertEqual(model.selectedLayerID, 1)
        XCTAssertEqual(model.geometryBuildCount, builds + 1)

        // Expanded again in the list: the rows inside come back as they were.
        builds = model.geometryBuildCount
        start = ContinuousClock.now
        outline.expandItem(outline.item(atRow: 0))
        let expanding = ContinuousClock.now - start
        XCTAssertEqual(outline.numberOfRows, 3_000)
        XCTAssertEqual(model.geometryBuildCount, builds + 1)

        // No absolute limit, as the build is not optimised and machines differ.
        XCTAssertLessThan(collapsing, fromTheMenu * 50, "\(collapsing) vs \(fromTheMenu)")
        XCTAssertLessThan(expanding, fromTheMenu * 50, "\(expanding) vs \(fromTheMenu)")

        // With ⌥ the rows inside are collapsed for good, all in one go.
        builds = model.geometryBuildCount
        outline.collapseItem(outline.item(atRow: 0), collapseChildren: true)
        let expandedRows = model.expandedLayerIDs.filter { !model.tree.children(of: $0).isEmpty }
        XCTAssertEqual(expandedRows, [], "every row inside is collapsed too")
        XCTAssertEqual(model.geometryBuildCount, builds + 1)
        outline.expandItem(outline.item(atRow: 0))
        XCTAssertEqual(outline.numberOfRows, 3)
    }

    // MARK: - C-HIER-01: when there is no tree to show

    @MainActor
    func test_C_HIER_01_textStandsInWhileLoadingAndWhenThereAreNoWindows() throws {
        let model = model()
        let controller = controller(for: model)
        let status = try status(of: controller)

        XCTAssertTrue(isShown(status))
        XCTAssertEqual(status.stringValue, "Loading layers…")
        XCTAssertFalse(isShown(controller.outlineView))

        model.apply(Hierarchy(nodes: [], keyWindowID: 0))
        XCTAssertTrue(isShown(status))
        XCTAssertEqual(status.stringValue, "This app has no windows.")
        XCTAssertFalse(isShown(controller.outlineView))

        model.apply(try Fixtures.hierarchy())
        XCTAssertFalse(isShown(status))
        XCTAssertTrue(isShown(controller.outlineView))
    }

    @MainActor
    func test_C_HIER_01_aTreeThatBreaksTheProtocolIsExplained() throws {
        let model = model()
        let controller = controller(for: model)
        var broken = try Fixtures.hierarchy()
        broken.nodes.append(try XCTUnwrap(broken.nodes.first { $0.id == 3 }))

        model.apply(broken)

        let status = try status(of: controller)
        XCTAssertTrue(isShown(status))
        XCTAssertEqual(
            status.stringValue,
            "The app sent a layer tree that breaks the protocol: the ID 3 appears more than once.")
        XCTAssertFalse(isShown(controller.outlineView))
    }

    @MainActor
    func test_C_DET_04_anAppThatIsNotActiveIsExplainedByName() async throws {
        // C-DET-04 with no tree yet: an understandable text in place of the list, no alert.
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "app-not-active"))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client)
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        let controller = controller(for: model)

        model.reload()
        let failed = await Wait.until { await model.loadState == .failed(.appNotActive) }
        XCTAssertTrue(failed)

        let status = try status(of: controller)
        XCTAssertTrue(isShown(status))
        XCTAssertEqual(
            status.stringValue,
            "Demo is not active. Its layers will load when it comes to the foreground.")

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_HIER_01_aRequestThatFailsIsReported() async throws {
        // The server shakes hands and then says nothing more.
        let server = try await MockServer.start(script: try .fixtures("handshake"))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: Self.client, requestTimeout: .milliseconds(200))
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        let controller = controller(for: model)

        model.reload()
        let failed = await Wait.until { await model.loadState == .failed(.other) }
        XCTAssertTrue(failed)

        XCTAssertEqual(try status(of: controller).stringValue,
                       "The layers could not be loaded. Go back to the apps and open it again.")

        await session.close()
        await server.stop()
    }

    // MARK: - C-ATTR-01: clicking the selected row again

    @MainActor
    func test_C_ATTR_01_clickingTheSelectedRowAgainRetriesItsAttributes() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps.append(.expect(.getLayerDetails, as: 90))  // the attributes, never answered
        steps += try MockScript.fixtures("layer-details").steps
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: Self.client, requestTimeout: .milliseconds(300))
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        let controller = controller(for: model)
        // A click on a row reaches the controller.
        XCTAssertTrue(controller.outlineView.target === controller)
        XCTAssertNotNil(controller.outlineView.action)

        model.enter()
        let settled = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 7, total: 7)
        }
        XCTAssertTrue(settled)
        model.select(3)
        let failed = await Wait.until { await model.attributes.state == .failed }
        XCTAssertTrue(failed)

        // A click on a row that is not the selected one is a change of selection, not a retry.
        let other = try XCTUnwrap(layers(of: controller).firstIndex(of: 7))
        controller.rowWasClicked(other)
        XCTAssertEqual(model.attributes.state, .failed)

        let row = try XCTUnwrap(layers(of: controller).firstIndex(of: 3))
        controller.rowWasClicked(row)
        let loaded = await Wait.until {
            if case .loaded = await model.attributes.state { return true }
            return false
        }
        XCTAssertTrue(loaded)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    // MARK: - C-HIER-02: from the outline to the model

    @MainActor
    func test_C_HIER_02_collapsingAndExpandingARowIsRecordedInTheModel() throws {
        let model = model()
        let controller = controller(for: model)
        model.apply(try Fixtures.hierarchy())
        let outline = controller.outlineView

        outline.collapseItem(try item(4, in: controller))
        XCTAssertFalse(model.isExpanded(4))
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 6, 7, 8, 9])

        outline.expandItem(try item(4, in: controller))
        XCTAssertTrue(model.isExpanded(4))
        XCTAssertEqual(outline.numberOfRows, 9)
    }

    // MARK: - C-HIER-09, C-HIER-10: how the rows start, and double-clicking them

    @MainActor
    func test_C_HIER_09_theListOpensDownToTheViewController() throws {
        let model = InspectionStore(session: Session(channel: InertChannel(), client: Self.client))
        let controller = controller(for: model)
        model.apply(try Fixtures.hierarchy())
        // Layers 5 and 7 are inside the collapsed layers 4 and 6.
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 6, 8, 9])
    }

    @MainActor
    func test_C_HIER_10_doubleClickingARowExpandsOrCollapsesIt() throws {
        let model = InspectionStore(session: Session(channel: InertChannel(), client: Self.client))
        let controller = controller(for: model)
        model.apply(try Fixtures.hierarchy())
        let outline = controller.outlineView
        XCTAssertTrue(outline.target === controller)
        XCTAssertEqual(outline.doubleAction, NSSelectorFromString("outlineViewWasDoubleClicked:"))

        controller.rowWasDoubleClicked(try XCTUnwrap(layers(of: controller).firstIndex(of: 4)))
        XCTAssertTrue(model.isExpanded(4))
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 5, 6, 8, 9])

        controller.rowWasDoubleClicked(try XCTUnwrap(layers(of: controller).firstIndex(of: 4)))
        XCTAssertFalse(model.isExpanded(4))
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 6, 8, 9])

        // A row without sublayers, and no row at all, change nothing.
        controller.rowWasDoubleClicked(try XCTUnwrap(layers(of: controller).firstIndex(of: 3)))
        controller.rowWasDoubleClicked(-1)
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 6, 8, 9])
        XCTAssertEqual(model.tree.ids.filter { !model.isExpanded($0) }, [4, 6])
    }

    @MainActor
    func test_C_HIER_10_doubleClickingARowOfTheSearchOnlySelectsIt() throws {
        let model = InspectionStore(session: Session(channel: InertChannel(), client: Self.client))
        let controller = controller(for: model)
        model.apply(try Fixtures.hierarchy())
        // The search shows layer 6 expanded, to show the label inside it.
        model.setSearchText("label")
        let rows = layers(of: controller)
        XCTAssertEqual(rows, [1, 2, 3, 6, 7])

        controller.rowWasDoubleClicked(try XCTUnwrap(rows.firstIndex(of: 6)))
        XCTAssertEqual(layers(of: controller), rows)
        XCTAssertFalse(model.isExpanded(6))
    }

    @MainActor
    func test_C_HIER_02_selectingARowIsRecordedInTheModel() throws {
        let model = model()
        let controller = controller(for: model)
        model.apply(try Fixtures.hierarchy())
        let outline = controller.outlineView

        outline.selectRowIndexes([6], byExtendingSelection: false)
        XCTAssertEqual(model.selectedLayerID, 7)

        outline.selectRowIndexes([2], byExtendingSelection: false)
        XCTAssertEqual(model.selectedLayerID, 3)

        outline.deselectAll(nil)
        XCTAssertNil(model.selectedLayerID)
    }

    @MainActor
    func test_C_HIER_02_collapsingARowAboveTheSelectionSelectsThatRow() throws {
        let model = model()
        let controller = controller(for: model)
        model.apply(try Fixtures.hierarchy())
        let outline = controller.outlineView
        outline.selectRowIndexes([4], byExtendingSelection: false)
        XCTAssertEqual(model.selectedLayerID, 5)

        outline.collapseItem(try item(4, in: controller))

        XCTAssertEqual(model.selectedLayerID, 4)
        XCTAssertEqual(controller.layerID(atRow: outline.selectedRow), 4)
    }

    @MainActor
    func test_C_HIER_02_collapsingARowWithEverythingInsideItSelectsThatRow() throws {
        let model = model()
        let controller = controller(for: model)
        model.apply(try Fixtures.hierarchy())
        let outline = controller.outlineView
        outline.selectRowIndexes([6], byExtendingSelection: false)
        XCTAssertEqual(model.selectedLayerID, 7)

        outline.collapseItem(try item(2, in: controller), collapseChildren: true)

        XCTAssertEqual(layers(of: controller), [1, 2])
        for id: UInt64 in [2, 4, 6] {
            XCTAssertFalse(model.isExpanded(id), "layer \(id)")
        }
        XCTAssertEqual(model.selectedLayerID, 2)
        XCTAssertEqual(controller.layerID(atRow: outline.selectedRow), 2)
    }

    @MainActor
    func test_C_HIER_02_expandingARowWithEverythingInsideItIsRecorded() throws {
        let model = model()
        model.apply(try Fixtures.hierarchy())
        for id: UInt64 in [4, 6, 2] {
            model.setExpanded(id, false)
        }
        let controller = controller(for: model)
        let outline = controller.outlineView
        XCTAssertEqual(layers(of: controller), [1, 2])

        // What the outline view does when the triangle is clicked with Option held.
        outline.expandItem(try item(2, in: controller), expandChildren: true)

        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 5, 6, 7, 8, 9])
        for id: UInt64 in [2, 4, 6] {
            XCTAssertTrue(model.isExpanded(id), "layer \(id)")
        }
    }

    // MARK: - C-HIER-02: from the model to the outline

    @MainActor
    func test_C_HIER_02_theModelsSelectionIsShown() throws {
        let model = model()
        let controller = controller(for: model)
        model.apply(try Fixtures.hierarchy())
        let outline = controller.outlineView

        model.select(7)
        XCTAssertEqual(outline.selectedRow, 6)

        model.select(nil)
        XCTAssertEqual(outline.selectedRow, -1)
    }

    @MainActor
    func test_C_HIER_02_theStateIsShownAgainAfterAReload() throws {
        let model = model()
        let controller = controller(for: model)
        model.apply(try Fixtures.hierarchy())
        let outline = controller.outlineView
        outline.collapseItem(try item(4, in: controller))
        outline.selectRowIndexes(
            [try XCTUnwrap(layers(of: controller).firstIndex(of: 7))], byExtendingSelection: false)

        model.apply(try changedHierarchy())

        // Layer 4 is still collapsed, so layer 5 has no row; 8 is gone; 10 is new.
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 6, 7, 9, 10])
        XCTAssertFalse(outline.isItemExpanded(try item(4, in: controller)))
        XCTAssertTrue(outline.isItemExpanded(try item(6, in: controller)))
        XCTAssertEqual(controller.layerID(atRow: outline.selectedRow), 7)

        // Showing the model's state wrote nothing back to it.
        XCTAssertFalse(model.isExpanded(4))
        XCTAssertTrue(model.isExpanded(6))
        XCTAssertTrue(model.isExpanded(10))
        XCTAssertEqual(model.selectedLayerID, 7)
    }

    @MainActor
    func test_C_HIER_02_aReloadThatRemovesTheSelectedLayerClearsTheSelection() throws {
        let model = model()
        let controller = controller(for: model)
        model.apply(try Fixtures.hierarchy())
        let outline = controller.outlineView
        outline.selectRowIndexes([7], byExtendingSelection: false)
        XCTAssertEqual(model.selectedLayerID, 8)

        model.apply(try changedHierarchy())

        // Not the row that now happens to be at the old index.
        XCTAssertEqual(outline.selectedRow, -1)
        XCTAssertNil(model.selectedLayerID)
    }

    @MainActor
    func test_C_HIER_02_aViewMadeLaterShowsTheModelsState() throws {
        // Coming back to an inspection: the model has state, the view is new.
        let model = model()
        model.apply(try Fixtures.hierarchy())
        model.setExpanded(6, false)
        model.select(3)

        let controller = controller(for: model)
        let outline = controller.outlineView
        XCTAssertEqual(layers(of: controller), [1, 2, 3, 4, 5, 6, 8, 9])
        XCTAssertEqual(controller.layerID(atRow: outline.selectedRow), 3)

        // A collapsed node inside a collapsed node: when the outer one is opened in the
        // outline, the inner one is still closed.
        let nested = self.model()
        nested.apply(try Fixtures.hierarchy())
        nested.setExpanded(6, false)
        nested.setExpanded(2, false)
        let second = self.controller(for: nested)
        XCTAssertEqual(layers(of: second), [1, 2])

        second.outlineView.expandItem(try item(2, in: second))

        XCTAssertEqual(layers(of: second), [1, 2, 3, 4, 5, 6, 8, 9])
        XCTAssertTrue(nested.isExpanded(2))
        XCTAssertFalse(nested.isExpanded(6))
        XCTAssertTrue(nested.isExpanded(4))
    }

    // MARK: - C-HIER-03

    @MainActor
    func test_C_HIER_03_theHiddenLayerIsShownDimmed() throws {
        let model = model()
        let controller = controller(for: model)
        model.apply(try Fixtures.hierarchy())

        for row in 0..<9 {
            let view = try XCTUnwrap(controller.rowView(row))
            let title = try XCTUnwrap(AppListViewTests.descendant(
                of: view, identifier: HierarchyRowView.titleIdentifier) as? NSTextField)
            // Row 4 is layer 5, the hidden shape layer.
            let dimmed = row == 4
            XCTAssertEqual(view.isDimmed, dimmed, "row \(row)")
            XCTAssertEqual(
                title.textColor, dimmed ? .tertiaryLabelColor : .labelColor, "row \(row)")
        }
    }

    @MainActor
    func test_C_HIER_03_aHiddenLayerCarriesTheCrossedOutEye() throws {
        let model = model()
        let controller = controller(for: model)
        model.apply(try Fixtures.hierarchy())

        for row in 0..<9 {
            let view = try XCTUnwrap(controller.rowView(row))
            let mark = try XCTUnwrap(AppListViewTests.descendant(
                of: view, identifier: HierarchyRowView.hiddenIdentifier))
            XCTAssertEqual(mark.isHidden, row != 4, "row \(row)")
        }
    }

    @MainActor
    func test_C_HIER_01_eachRowHasASymbolForWhatItIs() throws {
        let model = model()
        let controller = controller(for: model)
        model.apply(try Fixtures.hierarchy())

        let symbols = try (0..<9).map { row in try XCTUnwrap(controller.rowView(row)).symbolName }
        // UIWindow, UIView, UILabel, CardView, CAShapeLayer, UIScrollView, UILabel, CALayer,
        // UIView.
        XCTAssertEqual(symbols, [
            "macwindow", "square", "textformat", "square", "square.dashed", "scroll",
            "textformat", "square.dashed", "square",
        ])
        let image = try XCTUnwrap(AppListViewTests.descendant(
            of: try XCTUnwrap(controller.rowView(0)), identifier: HierarchyRowView.symbolIdentifier)
            as? NSImageView)
        XCTAssertNotNil(image.image)
    }

    @MainActor
    func test_C_HIER_01_theFooterCountsTheLayers() throws {
        let model = model()
        let controller = controller(for: model)
        let count = try XCTUnwrap(AppListViewTests.descendant(
            of: controller.view, identifier: HierarchyViewController.countIdentifier)
            as? NSTextField)
        XCTAssertFalse(isShown(count), "nothing to count while loading")

        model.apply(try Fixtures.hierarchy())
        XCTAssertTrue(isShown(count))
        XCTAssertEqual(count.stringValue, "9 layers · 1 hidden")
    }

    @MainActor
    func test_C_HIER_01_theWidthOfARowCoversItsSymbolAndHiddenMark() {
        let title = "UIActivityIndicatorView"
        for dimmed in [false, true] {
            let row = HierarchyRowView()
            row.configure(HierarchyRow(title: title, isDimmed: dimmed))
            XCTAssertLessThanOrEqual(
                row.fittingSize.width, HierarchyRowView.width(ofTitle: title) + 0.5,
                "dimmed: \(dimmed)")
        }
    }

    @MainActor
    func test_C_HIER_03_aReusedRowDoesNotStayDimmed() {
        let row = HierarchyRowView()
        row.configure(HierarchyRow(title: "CAShapeLayer", isDimmed: true))
        row.configure(HierarchyRow(title: "UILabel", isDimmed: false))

        XCTAssertFalse(row.isDimmed)
        let title = AppListViewTests.descendant(
            of: row, identifier: HierarchyRowView.titleIdentifier) as? NSTextField
        XCTAssertEqual(title?.stringValue, "UILabel")
        XCTAssertEqual(title?.textColor, .labelColor)
    }

    // MARK: - C-HIER-01: rows too deep for the list's width

    /// A chain of layers, each inside the one before, all with the same title.
    private func chain(depth: Int, title: String) -> Hierarchy {
        let nodes = (1...depth).map { id in
            LayerNode(
                id: UInt64(id), parentID: UInt64(id - 1), className: "CALayer",
                displayClassName: "CALayer", viewClassName: title, viewDisplayClassName: title,
                bounds: nil, position: nil, anchorPoint: nil, transform: nil, zPosition: 0,
                isHidden: false, opacity: 1, masksToBounds: false)
        }
        return Hierarchy(nodes: nodes, keyWindowID: 1)
    }

    /// Gives the controller's view the size the list has in the window.
    @MainActor
    private func layOut(_ controller: HierarchyViewController) {
        controller.view.frame = NSRect(x: 0, y: 0, width: 280, height: 400)
        controller.view.layoutSubtreeIfNeeded()
    }

    /// The width a row's title needs to be shown in full.
    @MainActor
    private func titleWidth(_ title: String) -> CGFloat {
        NSTextField(labelWithString: title).intrinsicContentSize.width
    }

    @MainActor
    func test_C_HIER_01_aDeepRowStillHasRoomForItsTitle() throws {
        let model = model()
        let controller = controller(for: model)
        layOut(controller)
        model.apply(chain(depth: 40, title: "UICollectionViewListCell"))
        controller.view.layoutSubtreeIfNeeded()
        let outline = controller.outlineView

        XCTAssertEqual(outline.numberOfRows, 40)
        let needed = titleWidth("UICollectionViewListCell")
        for row in 0..<40 {
            XCTAssertGreaterThanOrEqual(
                outline.frameOfCell(atColumn: 0, row: row).width, needed, "row \(row)")
        }

        // The list is 280 points wide and these rows are not: it scrolls sideways.
        let scrollView = try XCTUnwrap(outline.enclosingScrollView)
        XCTAssertTrue(scrollView.hasHorizontalScroller)
        XCTAssertGreaterThan(outline.frame.width, scrollView.contentView.bounds.width)
    }

    @MainActor
    func test_C_HIER_01_aTreeThatFitsDoesNotScrollSideways() throws {
        let model = model()
        let controller = controller(for: model)
        layOut(controller)
        model.apply(try Fixtures.hierarchy())
        controller.view.layoutSubtreeIfNeeded()
        let outline = controller.outlineView

        for row in 0..<9 {
            let title = try XCTUnwrap(controller.layerID(atRow: row).map(model.tree.displayTitle(of:)))
            XCTAssertGreaterThanOrEqual(
                outline.frameOfCell(atColumn: 0, row: row).width, titleWidth(title), "row \(row)")
        }
        // Nothing to scroll to, and the rows still span the whole list.
        let scrollView = try XCTUnwrap(outline.enclosingScrollView)
        XCTAssertEqual(outline.frame.width, scrollView.contentView.bounds.width)
    }

    @MainActor
    func test_C_HIER_01_theRoomForTitlesFollowsAReload() throws {
        let model = model()
        let controller = controller(for: model)
        layOut(controller)
        let outline = controller.outlineView
        let scrollView = try XCTUnwrap(outline.enclosingScrollView)

        model.apply(chain(depth: 40, title: "UICollectionViewListCell"))
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(outline.frame.width, scrollView.contentView.bounds.width)

        // A shallower tree needs less, and the list stops scrolling sideways.
        model.apply(try Fixtures.hierarchy())
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(outline.frame.width, scrollView.contentView.bounds.width)

        // A deeper one needs more again.
        model.apply(chain(depth: 60, title: "UICollectionViewListCell"))
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThanOrEqual(
            outline.frameOfCell(atColumn: 0, row: 59).width, titleWidth("UICollectionViewListCell"))
    }

    /// Folding a deep subtree away used to leave the list scrolling sideways to the width the
    /// hidden rows needed.
    @MainActor
    func test_C_HIER_01_theRoomForTitlesFollowsTheRowsShown() throws {
        let model = model()
        let controller = controller(for: model)
        layOut(controller)
        let outline = controller.outlineView
        let scrollView = try XCTUnwrap(outline.enclosingScrollView)
        model.apply(chain(depth: 40, title: "UICollectionViewListCell"))
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(outline.frame.width, scrollView.contentView.bounds.width)

        // Collapsed by the model (as "Collapse All" does): one short row, nothing sideways.
        model.collapseAll()
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(outline.numberOfRows, 1)
        XCTAssertEqual(outline.frame.width, scrollView.contentView.bounds.width)

        // Expanded by the model again: as wide as the deepest row.
        model.expandAll()
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(outline.frame.width, scrollView.contentView.bounds.width)

        // Collapsed in the list, as a click on the disclosure does: sized once that is over.
        outline.collapseItem(outline.item(atRow: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(outline.frame.width, scrollView.contentView.bounds.width)
        outline.expandItem(outline.item(atRow: 0), expandChildren: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(outline.frame.width, scrollView.contentView.bounds.width)

        // A search that leaves only shallow rows, and a focus on a shallow node.
        model.setSearchText("no such layer")
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(outline.numberOfRows, 0, "no titles match: the column is left alone")
        model.setSearchText("")
        model.collapseAll()
        model.focus(on: 1)
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(outline.frame.width, scrollView.contentView.bounds.width)
        model.expandAll()
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(outline.frame.width, scrollView.contentView.bounds.width)
    }

    // MARK: - C-PREV-01: the first click

    @MainActor
    func test_C_PREV_01_theListTakesAClickInAWindowThatIsNotKey() {
        let controller = controller(for: model())
        XCTAssertTrue(controller.outlineView.acceptsFirstMouse(for: nil))
    }

    // MARK: - C-HIER-02: reloading in place

    @MainActor
    func test_C_HIER_02_aReloadKeepsTheScrollPosition() throws {
        let model = model()
        let (controller, window) = controllerInWindow(for: model)
        model.apply(try Fixtures.hierarchy())
        model.select(1)
        window.layoutIfNeeded()
        let outline = controller.outlineView
        // Row 2 at the top: scrolled, and not as far as the list goes, so that the same
        // position exists after the reload too.
        outline.scroll(NSPoint(x: 0, y: outline.rect(ofRow: 2).minY))
        let clip = try XCTUnwrap(outline.enclosingScrollView?.contentView)
        let scrolled = clip.bounds.origin
        XCTAssertGreaterThan(scrolled.y, 0, "the list scrolled")

        model.apply(try changedHierarchy())  // other rows: the outline reloads
        window.layoutIfNeeded()

        XCTAssertEqual(clip.bounds.origin, scrolled, "the reload scrolled the list")
        XCTAssertEqual(controller.layerID(atRow: controller.outlineView.selectedRow), 1)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_HIER_02_rowsThatDidNotChangeAreNotReloaded() throws {
        let model = model()
        let controller = controller(for: model)
        model.apply(try Fixtures.hierarchy())
        let reloads = controller.reloadCount

        // The same rows, one layer moved: the model publishes a new tree, the list stays.
        var moved = try Fixtures.hierarchy()
        let index = try XCTUnwrap(moved.nodes.firstIndex { $0.id == 3 })
        moved.nodes[index].position = Point(x: 10, y: 10)
        model.apply(moved)
        XCTAssertEqual(model.tree.node(3)?.position, Point(x: 10, y: 10), "a new tree was taken")
        XCTAssertEqual(controller.reloadCount, reloads)

        model.apply(try changedHierarchy())
        XCTAssertEqual(controller.reloadCount, reloads + 1)
    }

    // MARK: - C-DET-01: the rows in view

    /// A controller in a window that is never shown, 280 × 170 points: below the search
    /// field and above the footer, room for four or five rows.
    @MainActor
    private func controllerInWindow(
        for model: InspectionStore
    ) -> (HierarchyViewController, NSWindow) {
        let controller = HierarchyViewController(store: model, appName: "Demo")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 170), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 280, height: 170))
        window.layoutIfNeeded()
        return (controller, window)
    }

    /// A part of the tree expanded as a whole is expanded in one call, also when its root is
    /// open already and only the rows inside it are collapsed.
    @MainActor
    func test_C_HIER_06_expandingAllAfterTheFirstLevelOpensEveryRowInside() throws {
        let model = model()
        let controller = controller(for: model)
        let hierarchy = try Fixtures.hierarchy()
        model.apply(hierarchy)
        let outline = controller.outlineView
        XCTAssertEqual(outline.numberOfRows, hierarchy.nodes.count)

        model.expand(toDepth: 1)
        XCTAssertTrue(outline.isItemExpanded(outline.item(atRow: 0)), "the window stays open")
        XCTAssertLessThan(outline.numberOfRows, hierarchy.nodes.count)

        model.expandAll()
        XCTAssertEqual(outline.numberOfRows, hierarchy.nodes.count)
        for row in 0..<outline.numberOfRows {
            let item = outline.item(atRow: row)
            if outline.isExpandable(item) { XCTAssertTrue(outline.isItemExpanded(item), "row \(row)") }
        }
    }

    /// The outline view is hidden while it reloads, which takes the keyboard focus away from it:
    /// the list takes it back, and stays where it was scrolled to.
    @MainActor
    func test_C_HIER_01_theListKeepsTheKeyboardFocusAndItsScrollingAcrossAReload() throws {
        let model = model()
        let (controller, window) = controllerInWindow(for: model)
        model.apply(try Fixtures.hierarchy())
        window.layoutIfNeeded()
        let outline = controller.outlineView
        XCTAssertTrue(window.makeFirstResponder(outline))
        outline.scrollRowToVisible(outline.numberOfRows - 1)
        let scrolled = outline.visibleRect.origin
        XCTAssertGreaterThan(scrolled.y, 0)

        // A search, and its end, reload the list.
        model.setSearchText("Layer")
        model.setSearchText("")
        XCTAssertTrue(window.firstResponder === outline)
        XCTAssertEqual(outline.visibleRect.origin, scrolled)
    }

    @MainActor
    func test_C_DET_01_theRowsInViewAreReportedTopToBottom() throws {
        let model = model()
        let (controller, window) = controllerInWindow(for: model)
        model.apply(try Fixtures.hierarchy())
        window.layoutIfNeeded()

        let atTop = model.visibleLayerIDs
        XCTAssertEqual(atTop.first, 1)
        XCTAssertFalse(atTop.contains(9), "the last row is out of view")
        let rows = atTop.map { id in
            (0..<controller.outlineView.numberOfRows).first { controller.layerID(atRow: $0) == id }
        }
        XCTAssertEqual(rows, rows.sorted { ($0 ?? -1) < ($1 ?? -1) }, "top to bottom")

        controller.outlineView.scrollRowToVisible(8)
        let atBottom = model.visibleLayerIDs
        XCTAssertEqual(atBottom.last, 9)
        XCTAssertFalse(atBottom.contains(1), "the first row scrolled out of view")
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_DET_01_collapsingReportsTheRowsThatMoveIntoView() throws {
        let model = model()
        let (controller, window) = controllerInWindow(for: model)
        model.apply(try Fixtures.hierarchy())
        window.layoutIfNeeded()
        XCTAssertFalse(model.visibleLayerIDs.contains(9))

        // Collapsing 2, as a click on its triangle does: rows 3 to 9 go, and nothing below
        // 2 is left; then expanding it again brings them back.
        controller.outlineView.collapseItem(try item(2, in: controller))
        XCTAssertEqual(model.visibleLayerIDs, [1, 2])
        controller.outlineView.expandItem(try item(2, in: controller))
        XCTAssertEqual(model.visibleLayerIDs.prefix(3), [1, 2, 3])
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_DET_01_aListOutsideAWindowReportsNoRows() throws {
        let model = model()
        model.setVisibleLayers([3])  // what an earlier list reported
        let controller = controller(for: model)
        model.apply(try Fixtures.hierarchy())
        XCTAssertEqual(controller.outlineView.numberOfRows, 9)
        XCTAssertEqual(model.visibleLayerIDs, [], "this list sees no rows and says so")
    }

    // MARK: - Scrolling to the selection, typing to a row, deep trees

    /// A window, a stretch of leaves under it, and a collapsed node 100 with a child 101.
    /// With `collapsedFirst`, node 100 comes before the leaves; leaf 10 can be put inside it.
    private func longTree(collapsedFirst: Bool, tenInside: Bool) -> Hierarchy {
        var nodes = [Self.plainNode(1), Self.plainNode(2, parent: 1)]
        let collapsed = [
            Self.plainNode(100, parent: 2),
            Self.plainNode(101, parent: 100),
        ] + (tenInside ? [Self.plainNode(10, parent: 100)] : [])
        let leaves = (tenInside ? 11 : 10)...69
        let leafNodes = leaves.map { Self.plainNode(UInt64($0), parent: 2) }
        nodes += collapsedFirst ? collapsed + leafNodes : leafNodes + collapsed
        return Hierarchy(nodes: nodes, keyWindowID: 1)
    }

    @MainActor
    func test_C_HIER_02_aSelectionThatMovesIntoACollapsedNodeIsScrolledTo() {
        let model = model()
        let (controller, window) = controllerInWindow(for: model)
        model.apply(longTree(collapsedFirst: false, tenInside: false))
        model.setExpanded(100, false)
        model.select(10)
        window.layoutIfNeeded()
        let outline = controller.outlineView

        // Leaf 10 moves into the collapsed node 100, which moves to the top: the selection
        // goes to 100.
        model.apply(longTree(collapsedFirst: true, tenInside: true))
        window.layoutIfNeeded()
        XCTAssertEqual(model.selectedLayerID, 100)
        let row = outline.selectedRow
        XCTAssertEqual(controller.layerID(atRow: row), 100)
        XCTAssertTrue(
            outline.visibleRect.intersects(outline.rect(ofRow: row)),
            "row \(row) \(outline.rect(ofRow: row)) is out of \(outline.visibleRect)")
    }

    @MainActor
    func test_C_HIER_01_typingJumpsToARowByItsTitle() throws {
        let model = model()
        let controller = controller(for: model)
        model.apply(try Fixtures.hierarchy())
        let outline = controller.outlineView
        let item = try XCTUnwrap(outline.item(atRow: 3))
        XCTAssertEqual(
            controller.outlineView(
                outline, typeSelectStringFor: outline.tableColumns.first, item: item),
            "CardView")
    }

    private static func plainNode(_ id: UInt64, parent: UInt64 = 0) -> LayerNode {
        LayerNode(
            id: id, parentID: parent, className: "CALayer", displayClassName: "CALayer",
            viewClassName: nil, viewDisplayClassName: nil,
            bounds: Rect(origin: Point(x: 0, y: 0), size: Size(width: 10, height: 10)),
            position: Point(x: 5, y: 5), anchorPoint: nil, transform: nil, zPosition: 0,
            isHidden: false, opacity: 1, masksToBounds: false)
    }

    @MainActor
    func test_C_HIER_01_aDeepTreeIsShownAboutAsFastAsAWideOne() {
        // A slowdown that grows with depth would show here; there is no absolute limit, as
        // the build is not optimised and machines differ.
        func time(_ hierarchy: Hierarchy) -> Duration {
            let model = model()
            let controller = controller(for: model)
            layOut(controller)
            let start = ContinuousClock.now
            model.apply(hierarchy)
            controller.view.layoutSubtreeIfNeeded()
            return ContinuousClock.now - start
        }
        let siblings = Hierarchy(
            nodes: [Self.plainNode(1)] + (2...2_000).map { Self.plainNode(UInt64($0), parent: 1) },
            keyWindowID: 1)
        let wide = time(siblings)
        let deep = time(chain(depth: 2_000, title: "CALayer"))
        XCTAssertLessThan(deep, wide * 20, "deep \(deep), wide \(wide)")
    }
}
