import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// What the inspection takes once the connection to its app is gone (C-WIN-03, C-ATTR-04):
/// the store itself turns away what the user asks of the tree, the preview and the app, and
/// still ends what is under way.
final class DisconnectedInspectionTests: XCTestCase {
    /// A live inspection whose session never connected, with the fixtures' tree, all of it
    /// expanded.
    @MainActor
    private func model() throws -> InspectionStore {
        let session = Session(
            channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0"))
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        return model
    }

    /// Everything the user's intents could change.
    private struct Shown: Equatable {
        var selected: UInt64?
        var hovered: UInt64?
        var focused: UInt64?
        var expanded: Set<UInt64>
        var showsAllConstraintEnds: Bool
        var previewMode: PreviewMode
        var cameras: PreviewCameras
        var showsHiddenLayers: Bool
        var borders: BorderOptions
        var reloadAgain: Bool
        var queuedSubtrees: [UInt64]
        var screenshotExport: ScreenshotExportState
        var attributes: AttributesStore.State

        @MainActor
        init(_ model: InspectionStore) {
            selected = model.selectedLayerID
            hovered = model.hoveredLayerID
            focused = model.focusedLayerID
            expanded = model.expandedLayerIDs
            showsAllConstraintEnds = model.showsAllConstraintEnds
            previewMode = model.previewMode
            cameras = model.cameras
            showsHiddenLayers = model.showsHiddenLayers
            borders = model.borders
            reloadAgain = model.reloadAgain
            queuedSubtrees = model.queuedSubtrees
            screenshotExport = model.screenshotExport
            attributes = model.attributes.state
        }
    }

    @MainActor
    func test_C_WIN_03_theStoreTakesNoIntentOnceTheConnectionIsGone() throws {
        let model = try model()
        model.canRefreshSubtrees = true
        let tree = model.tree
        let node = try XCTUnwrap(tree.ids.first {
            tree.parent(of: $0) != nil && !tree.children(of: $0).isEmpty
        })
        let child = try XCTUnwrap(tree.children(of: node).first)
        model.select(node)
        model.pan(by: 10, 10)
        // A hierarchy on its way, which a refresh would ask for again after it.
        model.enter()
        XCTAssertTrue(model.isLoading)
        model.connectionLost()
        let before = Shown(model)

        // The tree.
        model.select(child)
        model.select(nil)
        model.reveal(child)
        model.selectParent()
        model.selectFirstChild()
        // What the attribute panel asks: a chip's layer, and Retry.
        model.showLayer(child)
        model.retryAttributes()
        model.hover(child)
        model.expand(toDepth: 1)
        model.expandAll()
        model.collapseAll()
        model.focus(on: node)
        // The constraints the attribute panel points at.
        model.hoverConstraintEnd(nil, layerID: child)
        model.pointConstraints([0], stresses: true)
        model.setShowsAllConstraintEnds(true)
        model.toggleConstraintEnds()
        // The preview.
        model.setPreviewMode(.threeD)
        model.rotate(byDragOf: 10, 10)
        model.pan(by: 5, 5)
        model.zoom(by: 2, about: ScenePoint(x: 0, y: 0), in: Viewport(width: 100, height: 100))
        model.setLayerSpacing(80)
        model.resetCamera()
        model.setShowsHiddenLayers(true)
        model.setBorderStyle(.byKind)
        model.setOnlyAppClasses(true)
        model.toggleBorders()
        // The app.
        model.refresh()
        model.refreshSubtree(of: node)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        model.exportScreenshot(of: node, kind: .group, to: url) { _ in nil }

        XCTAssertEqual(Shown(model), before)
        XCTAssertFalse(model.canExportImage(of: node, kind: .group))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        model.leave()
    }

    @MainActor
    func test_C_WIN_03_theHoverEndsWithTheConnection() throws {
        let model = try model()
        let id = try XCTUnwrap(model.tree.ids.last)
        model.hover(id)
        XCTAssertEqual(model.hoveredLayerID, id)
        var hovers: [UInt64?] = []
        let subscription = model.$hoveredLayerID.dropFirst().sink { hovers.append($0) }

        model.connectionLost()
        XCTAssertNil(model.hoveredLayerID)
        XCTAssertEqual(hovers, [nil])
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func test_C_WIN_03_whatEndsSomethingStillGoesOnOnceDisconnected() throws {
        let model = try model()
        model.archiveSave = .failed(.disconnected)
        model.screenshotExport = .failed(.other)
        model.connectionLost()

        model.dismissArchiveSave()
        XCTAssertEqual(model.archiveSave, .idle)
        model.dismissScreenshotExport()
        XCTAssertEqual(model.screenshotExport, .idle)
        // The list's disclosure triangles still open and close its rows, and the store
        // follows them: refused, it would show another expansion than the list.
        let node = try XCTUnwrap(model.tree.ids.first { !model.tree.children(of: $0).isEmpty })
        model.setExpanded(node, false)
        XCTAssertFalse(model.isExpanded(node))
        // Typing that was on its way when the connection went still reaches the search, and
        // carries over to the next connection (C-WIN-04).
        model.setSearchText("Label")
        XCTAssertEqual(model.searchText, "Label")
        XCTAssertNotNil(model.filter)
        model.leave()
    }

    @MainActor
    func test_C_ATTR_04_nothingCanBeChangedOnceDisconnected() throws {
        let model = try model()
        model.attributes.setEditingSupported(true)
        let id = try XCTUnwrap(model.tree.ids.first)
        model.select(id)
        var canEdit: [Bool] = []
        let subscription = model.attributes.$canEdit.sink { canEdit.append($0) }

        model.connectionLost()
        XCTAssertEqual(canEdit, [true, false])
        model.attributes.set(
            AttributeKey(layerID: id, attributeID: "view.alpha"), to: .double(0.5), continuous: false)
        XCTAssertEqual(model.attributes.edits, [:], "nothing was sent")
        withExtendedLifetime(subscription) {}
    }
}
