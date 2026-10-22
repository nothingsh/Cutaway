import AppKit
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// C-SCALE-01 in an inspection window: 10,000 app-shaped layers (`ScaleScene`). Screenshots
/// are held back on the server, so that what is measured does not share the main thread with
/// their arrival; drawing with every layer's image is measured on its own (`ScaleRenderTests`).
/// Each result is printed with its limit.
final class ScaleInspectionTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
    }

    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    /// A window over a connection to `server`, shown, not yet entered.
    @MainActor
    private struct Inspection {
        let session: Session
        let model: InspectionStore
        let inspector: InspectorWindowController

        var outline: NSOutlineView { inspector.splitController.hierarchyController.outlineView }
        var preview: PreviewView? { inspector.splitController.previewController.preview }

        /// Lays out and draws the window and the preview now.
        func draw() {
            inspector.window?.displayIfNeeded()
            preview?.display()
        }

        func close() async {
            model.leave()
            inspector.close()
            await session.close()
        }
    }

    @MainActor
    private func open(_ server: MockServer) async throws -> Inspection {
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client, requestTimeout: .seconds(30))
        _ = try await session.handshake()
        let model = InspectionStore(session: session, maxTextureDimension: 4096)
        let inspector = InspectorWindowController(
            location: .simulator(port: server.port), entry: nil, store: model)
        inspector.showWindow(nil)
        return Inspection(session: session, model: model, inspector: inspector)
    }

    /// Waits, turning the main actor over, until `condition` holds; fails after `limit`.
    @MainActor
    private func until(
        within limit: Duration = .seconds(30), _ condition: () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + limit
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    /// A server whose screenshots wait at the gate until the test ends.
    @MainActor
    private func server() async throws -> MockServer {
        let gate = MockGate()
        let server = try await MockServer.start(
            script: try ScaleScene.script(holdingDetailsAt: gate), records: false)
        addTeardownBlock {
            await gate.open()
            await server.stop()
        }
        return server
    }

    /// An inspection with the whole tree listed.
    @MainActor
    private func loaded() async throws -> Inspection {
        let inspection = try await open(try await server())
        let count = try ScaleScene.hierarchy().nodes.count
        inspection.model.enter()
        try await until { inspection.outline.numberOfRows == count }
        inspection.draw()
        addTeardownBlock { await inspection.close() }
        return inspection
    }

    private func check(
        _ item: String, _ measured: Duration, limit: Duration,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let report = ScaleScene.report(item, measured, limit: limit)
        if ScaleScene.checksLimits {
            XCTAssertLessThanOrEqual(measured, limit, report, file: file, line: line)
        }
    }

    // MARK: - C-SCALE-01

    @MainActor
    func test_C_SCALE_01_tenThousandLayersAreListedWithinTwoSecondsOfArriving() async throws {
        let server = try await server()
        let count = try ScaleScene.hierarchy().nodes.count
        // From entering, which asks for the icon and the tree, to the list drawn: the request
        // and the server's encoding count too.
        let measured = try await ScaleScene.median(of: 3) {
            let inspection = try await open(server)
            let start = ContinuousClock.now
            inspection.model.enter()
            try await until { inspection.outline.numberOfRows == count }
            inspection.draw()
            let elapsed = ContinuousClock.now - start
            await inspection.close()
            return elapsed
        }
        check("tree arrived to list shown", measured, limit: .seconds(2))
    }

    @MainActor
    func test_C_SCALE_01_selectingARowHighlightsItAndSwitchesTheAttributesWithinATenthOfASecond()
        async throws
    {
        let inspection = try await loaded()
        let hierarchy = inspection.inspector.splitController.hierarchyController
        let rows = inspection.outline.numberOfRows
        var pick = 0
        let measured = try ScaleScene.median(of: 3) {
            pick += 1
            let row = rows * pick / 4
            let id = try XCTUnwrap(hierarchy.layerID(atRow: row))
            let start = ContinuousClock.now
            inspection.outline.selectRowIndexes([row], byExtendingSelection: false)
            inspection.draw()
            let elapsed = ContinuousClock.now - start
            XCTAssertEqual(inspection.model.attributes.selectedID, id)
            XCTAssertEqual(
                inspection.preview?.drawList.items.first { $0.highlight == .selected }?.layerID, id)
            XCTAssertEqual(
                inspection.inspector.splitController.attributesController.groups, [],
                "the panel still shows the last layer")
            return elapsed
        }
        check("selection", measured, limit: .milliseconds(100))
    }

    @MainActor
    func test_C_SCALE_01_aSearchOfTenThousandRowsAndItsClearingTakeAtMostTwoHundredMilliseconds()
        async throws
    {
        let inspection = try await loaded()
        let all = inspection.outline.numberOfRows
        var searches: [Duration] = [], clearings: [Duration] = []
        for _ in 0..<3 {
            var start = ContinuousClock.now
            inspection.model.setSearchText("Label")
            inspection.draw()
            searches.append(ContinuousClock.now - start)
            XCTAssertGreaterThan(inspection.outline.numberOfRows, 0)
            XCTAssertLessThan(inspection.outline.numberOfRows, all)
            // Another word, as typing goes on.
            start = ContinuousClock.now
            inspection.model.setSearchText("Separator")
            inspection.draw()
            searches.append(ContinuousClock.now - start)
            XCTAssertLessThan(inspection.outline.numberOfRows, all)

            start = ContinuousClock.now
            inspection.model.setSearchText("")
            inspection.draw()
            clearings.append(ContinuousClock.now - start)
            XCTAssertEqual(inspection.outline.numberOfRows, all)
        }
        check("search", searches.sorted()[searches.count / 2], limit: .milliseconds(200))
        check("clearing the search", clearings.sorted()[1], limit: .milliseconds(200))
    }

    @MainActor
    func test_C_SCALE_01_expandingEverythingTakesAtMostASecond() async throws {
        let inspection = try await loaded()
        let all = inspection.outline.numberOfRows
        let measured = ScaleScene.median(of: 3) {
            inspection.model.collapseAll()
            inspection.draw()
            let start = ContinuousClock.now
            inspection.model.expandAll()
            inspection.draw()
            let elapsed = ContinuousClock.now - start
            XCTAssertEqual(inspection.outline.numberOfRows, all)
            return elapsed
        }
        check("expand all", measured, limit: .seconds(1))
    }

    @MainActor
    func test_C_SCALE_01_collapsingEverythingTakesAtMostASecond() async throws {
        let inspection = try await loaded()
        let windows = inspection.model.tree.roots.count
        let measured = ScaleScene.median(of: 3) {
            let start = ContinuousClock.now
            inspection.model.collapseAll()
            inspection.draw()
            let elapsed = ContinuousClock.now - start
            XCTAssertEqual(inspection.outline.numberOfRows, windows)
            inspection.model.expandAll()
            inspection.draw()
            return elapsed
        }
        check("collapse all", measured, limit: .seconds(1))
    }

    /// The answer to the refresh after a change (C-DET-06) replaces the changed layer's whole
    /// window, nearly every layer, though one value changed. What the list and the preview do
    /// on the main thread with that tree, once the store publishes it, is measured: the
    /// borders' colours, the rows compared, the window drawn. Laying the scene out is the
    /// store's, measured with C-SCALE-01's layout.
    @MainActor
    func test_C_SCALE_01_aTreeThatComesAgainAfterAChangeTakesTheListAndPreviewAtMostEightyMilliseconds()
        async throws
    {
        let inspection = try await loaded()
        let model = inspection.model
        let hierarchy = try ScaleScene.hierarchy()
        let changed = hierarchy.nodes[hierarchy.nodes.count / 2].id
        let root = try XCTUnwrap(model.tree.path(to: changed).first)
        // The window's subtree as the server sends it: parents first.
        var inside: Set<UInt64> = [root]
        var window: [LayerNode] = []
        for node in hierarchy.nodes where node.id == root || inside.contains(node.parentID) {
            inside.insert(node.id)
            window.append(node)
        }
        let index = try XCTUnwrap(window.firstIndex { $0.id == changed })
        let rows = inspection.outline.numberOfRows
        let reloads = inspection.inspector.splitController.hierarchyController.reloadCount
        var opacity: Float = 0.5
        let measured = try ScaleScene.median(of: 7) {
            // Another value each time, so that each tree differs from the last.
            let value = opacity
            opacity = opacity == 0.5 ? 0.25 : 0.5
            var answer = window
            answer[index].opacity = value
            let tree = try model.tree.replacingSubtree(
                with: Hierarchy(nodes: answer, keyWindowID: hierarchy.keyWindowID))
            let start = ContinuousClock.now
            // As the store publishes a tree it took in.
            model.tree = tree
            model.announceRows()
            inspection.draw()
            let elapsed = ContinuousClock.now - start
            XCTAssertEqual(inspection.preview?.borders.tree.node(changed)?.opacity, value)
            XCTAssertEqual(inspection.outline.numberOfRows, rows)
            return elapsed
        }
        XCTAssertEqual(
            inspection.inspector.splitController.hierarchyController.reloadCount, reloads,
            "the same rows: the list is not reloaded")
        check("a tree that comes again after a change", measured, limit: .milliseconds(80))
    }

    @MainActor
    func test_C_SCALE_01_anArchiveOfTenThousandLayersOpensWithinTwoSeconds() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScaleInspectionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Large.cutaway")
        // Saved as a capture right after the tree came in would be: every node expanded.
        let hierarchy = try ScaleScene.hierarchy()
        var state = ArchiveState()
        state.expanded = Set(hierarchy.nodes.map(\.id))
        try ScaleScene.archive(state: state.encoded()).write(to: url)
        let count = hierarchy.nodes.count

        let list = AppListStore()
        let coordinator = WindowCoordinator(store: list, discoversDevices: false)
        coordinator.recents = MemoryRecentArchives()
        coordinator.presentOpenFailure = { _, error in XCTFail("\(error)") }
        addTeardownBlock { @MainActor in
            coordinator.launcher.close()
            try? FileManager.default.removeItem(at: directory)
        }
        let measured = try await ScaleScene.median(of: 3) {
            let start = ContinuousClock.now
            let opened = await coordinator.openArchive(url)
            let window = try XCTUnwrap(opened)
            let outline = window.splitController.hierarchyController.outlineView
            try await until { outline.numberOfRows == count }
            window.window?.displayIfNeeded()
            let elapsed = ContinuousClock.now - start
            window.close()
            try await until { coordinator.archiveWindows.isEmpty }
            return elapsed
        }
        check("archive opened to list shown", measured, limit: .seconds(2))
    }
}
