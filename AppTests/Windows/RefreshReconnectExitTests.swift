import AppKit
import CutawayRender
import CutawayTestSupport
import CutawayUI
import XCTest

@testable import Cutaway

/// End to end: in the running app a refresh asks MockServer for the
/// layers and their screenshots again (C-DET-05), and when MockServer starts again on its
/// port after stopping, the inspector window is back to inspecting (C-WIN-04).
final class RefreshReconnectExitTests: XCTestCase {
    @MainActor
    private func inspector() -> InspectorWindowController? {
        AppWindows.inspectorWindows().first?.windowController as? InspectorWindowController
    }

    private static func count(_ kind: MessageKind, _ server: MockServer) async -> Int {
        await server.receivedFrames.filter { MessageKind($0.body) == kind }.count
    }

    @MainActor
    func test_C_WIN_04_theRunningAppRefreshesAndComesBackToAnAppThatStartsAgain() async throws {
        let server = try await AppWindows.startMockServer(
            try .fixtures(
                "handshake", "app-icon", "hierarchy", "layer-details", "hierarchy",
                "layer-details"))
        let port = server.port
        addTeardownBlock {
            await AppWindows.closeInspectors()
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }
        try await AppWindows.chooseApp(named: "Demo", server: server)
        let preview = try XCTUnwrap(
            AppWindows.views(identifier: PreviewView.identifier).first as? PreviewView)
        let arrived = try await AppWindows.waitFor(
            Pixel(blue: 0, green: 255, red: 0, alpha: 255), at: 4, in: preview)
        XCTAssertTrue(arrived, "layer 4's screenshot did not appear")

        // Refresh from the toolbar's capsule (C-DET-05, C-WIN-06).
        let first = try XCTUnwrap(inspector())
        let refresh = try XCTUnwrap(first.window?.toolbar?.items.compactMap(\.view).lazy.compactMap {
            AppWindows.views(in: $0, identifier: "toolbar.capsule.refresh").first as? NSButton
        }.first)
        XCTAssertTrue(refresh.isEnabled)
        refresh.performClick(nil)
        var deadline = Date().addingTimeInterval(5)
        while await Self.count(.getLayerDetails, server) < 2, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let hierarchies = await Self.count(.getHierarchy, server)
        let details = await Self.count(.getLayerDetails, server)
        XCTAssertEqual(hierarchies, 2)
        XCTAssertEqual(details, 2)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        // The app goes away: the window stays and waits (C-WIN-03, C-WIN-04).
        await server.stop()
        deadline = Date().addingTimeInterval(5)
        while inspector()?.isDisconnected != true, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(inspector()?.isDisconnected, true)
        let notice = AppWindows.views(identifier: "preview.disconnected.text").first
            as? NSTextField
        XCTAssertEqual(notice?.stringValue.contains("Waiting for it to come back"), true)

        // It starts again on its port: within 5 seconds the window inspects it again, the
        // layers opened as they first are (C-WIN-04, C-HIER-09).
        let restarted = try await MockServer.start(
            port: port, script: .fixtures("handshake", "app-icon", "hierarchy", "layer-details"))
        // Runs before the block above: the app's window closes once this server stops.
        addTeardownBlock { await restarted.stop() }
        deadline = Date().addingTimeInterval(5)
        while inspector()?.isDisconnected != false
            || (AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)?
            .numberOfRows != AppWindows.fixtureRowsAtFirst,
            Date() < deadline
        {
            try await Task.sleep(for: .milliseconds(50))
        }
        let back = try XCTUnwrap(inspector())
        XCTAssertFalse(back === first, "a window for the new connection")
        XCTAssertFalse(back.isDisconnected)
        XCTAssertEqual(
            (AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)?
                .numberOfRows, AppWindows.fixtureRowsAtFirst)
        XCTAssertEqual(back.window?.frame, first.window?.frame)
        let again = try await AppWindows.waitFor(
            Pixel(blue: 0, green: 255, red: 0, alpha: 255), at: 4,
            in: try XCTUnwrap(
                AppWindows.views(identifier: PreviewView.identifier).first as? PreviewView))
        XCTAssertTrue(again, "the screenshots came again")
        let restartedMismatches = await restarted.mismatches
        XCTAssertEqual(restartedMismatches, [])
    }
}
