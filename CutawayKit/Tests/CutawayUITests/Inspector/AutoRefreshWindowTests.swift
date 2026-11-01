import AppKit
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// C-LIVE-03 in an inspection window: what the user is doing in it holds no automatic refresh
/// back, only an expand or collapse and saving an archive do.
final class AutoRefreshWindowTests: XCTestCase {
    /// A window on the responder's app with layer 3 selected, its attributes and first round of
    /// screenshots in, once the app tells of changes.
    @MainActor
    private func inspection() async throws -> (InspectorWindowController, MockServer, Session) {
        let steps = try MockScript.fixtures("handshake").steps
        let server = try await MockServer.start(
            script: MockScript(steps: steps + [.respond(try MockResponder.demo())]))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: ClientInfo(name: "Cutaway", version: "0.1.0"),
            requestTimeout: .seconds(5))
        _ = try await session.handshake()
        let model = InspectionStore(session: session, newLayers: .expanded)
        // What AppListStore does with the events Discovery forwards.
        Task { @MainActor [weak model] in
            for await event in session.events {
                if case .hierarchyChanged(let change) = event { model?.hierarchyDidChange(change) }
            }
        }
        model.rowsWait = .zero
        let inspector = InspectorWindowController(
            location: .simulator(port: server.port), entry: nil, store: model)
        addTeardownBlock { @MainActor in inspector.close() }
        inspector.showWindow(nil)
        model.enter()
        let tree = await Wait.untilOnMain { model.loadState == .loaded }
        XCTAssertTrue(tree)
        model.select(3)
        let ready = await Wait.untilOnMain {
            if case .loaded = model.attributes.state { return model.attributes.canEdit }
            return false
        }
        XCTAssertTrue(ready)
        let settled = await Wait.untilOnMain { Self.isIdle(model) }
        XCTAssertTrue(settled)
        let watching = await Wait.until { await server.isWatching }
        XCTAssertTrue(watching)
        return (inspector, server, session)
    }

    @MainActor
    private static func isIdle(_ model: InspectionStore) -> Bool {
        !model.loader.isLoading && model.detailProgress.total > 0
            && model.detailProgress.completed == model.detailProgress.total
    }

    private static func subtreeRequests(_ server: MockServer) async -> [UInt64] {
        await server.receivedFrames.compactMap { frame in
            guard case .getSubtree(let request) = frame.body else { return nil }
            return request.rootID
        }
    }

    /// The app reports layer 3, and the refresh that brings is answered.
    @MainActor
    private func reportChange(
        of inspector: InspectorWindowController, from server: MockServer
    ) async throws -> Bool {
        try await server.sendEvent(HierarchyChanged(roots: [3], whole: false))
        let asked = await Wait.until { await Self.subtreeRequests(server) == [3] }
        let done = await Wait.untilOnMain { Self.isIdle(inspector.store) }
        return asked && done
    }

    @MainActor
    func test_C_LIVE_03_typingAValueHoldsNoRefreshBackAndStaysTyped() async throws {
        let (inspector, server, session) = try await inspection()
        let panel = inspector.splitController.attributesController.view
        let field = try XCTUnwrap(AppListViewTests.firstDescendant(of: panel) {
            ($0 as? AttributeEditField)?.isEditable == true
        } as? AttributeEditField)
        let window = try XCTUnwrap(inspector.window)
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        // As the keyboard does, which tells that editing began.
        editor.insertText("Typed", replacementRange: editor.selectedRange())

        let refreshed = try await reportChange(of: inspector, from: server)
        XCTAssertTrue(refreshed)
        XCTAssertNotNil(field.currentEditor(), "still being typed in")
        XCTAssertEqual((field.currentEditor() as? NSTextView)?.string, "Typed")

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LIVE_03_measuringHoldsNoRefreshBack() async throws {
        let (inspector, server, session) = try await inspection()
        let preview = try XCTUnwrap(inspector.splitController.previewController.preview)
        inspector.store.hover(2)
        preview.onMeasuringChange?(true)

        let refreshed = try await reportChange(of: inspector, from: server)
        XCTAssertTrue(refreshed)

        await session.close()
        await server.stop()
    }
}
