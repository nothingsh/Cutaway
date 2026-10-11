import AppKit
import CutawayRender
import CutawayTestSupport
import CutawayUI
import CutawayWire
import XCTest

@testable import Cutaway

/// End to end: in the running app, refreshing node 4's subtree asks
/// MockServer for that subtree and then for that subtree's screenshots alone (C-DET-07).
final class SubtreeRefreshExitTests: XCTestCase {
    private static func detailRequests(_ server: MockServer) async -> [GetLayerDetails] {
        await server.receivedFrames.compactMap { frame in
            guard case .getLayerDetails(let request) = frame.body else { return nil }
            return request
        }
    }

    private static func emptyAnswer(_ requestID: UInt32) -> [MockScript.Step] {
        [
            .expect(.getLayerDetails, as: requestID),
            .send(Frame(requestID: requestID, body: .streamEnd(StreamEnd(
                status: .completed, chunkCount: 0, error: nil)))),
        ]
    }

    @MainActor
    func test_C_DET_07_theRunningAppRefreshesOneSubtree() async throws {
        var steps = try MockScript.fixtures(
            "handshake", "app-icon", "hierarchy", "layer-details").steps
        // Selecting CardView asks for its attributes.
        steps += Self.emptyAnswer(60)
        // GetSubtree(4), answered as the fixture does.
        steps += Array(try MockScript.fixtures("subtree").steps.prefix(2))
        // Then the subtree's screenshots and the selected layer's attributes, in either order.
        steps += Self.emptyAnswer(70) + Self.emptyAnswer(71)
        let server = try await AppWindows.startMockServer(MockScript(steps: steps))
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

        // Select CardView (node 4) and refresh its subtree from the View menu.
        let outline = try XCTUnwrap(
            AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)
        outline.selectRowIndexes([3], byExtendingSelection: false)
        let inspector = try XCTUnwrap(
            AppWindows.inspectorWindows().first?.windowController as? InspectorWindowController)
        var deadline = Date().addingTimeInterval(5)
        while await Self.detailRequests(server).count < 2, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let item = try XCTUnwrap(
            NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items)
                .first { $0.title == "Refresh Selected Subtree" })
        XCTAssertTrue(inspector.validateMenuItem(item), "the server speaks 0.3")
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: inspector, from: item))

        deadline = Date().addingTimeInterval(5)
        while await Self.detailRequests(server).count < 4, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let frames = await server.receivedFrames
        XCTAssertEqual(
            frames.filter { MessageKind($0.body) == .getSubtree }.map(\.body),
            [.getSubtree(GetSubtree(rootID: 4))])
        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.count, 4)
        // After the subtree: CardView's image again, and its attributes; nothing else. It
        // starts collapsed (C-HIER-09), so the image is the group.
        let after = requests.suffix(2).flatMap(\.requests)
        XCTAssertEqual(
            Set(after.map { [$0.layerID, $0.wantSolo ? 1 : 0, $0.wantGroup ? 1 : 0,
                             $0.wantAttributes ? 1 : 0] }),
            [[4, 0, 1, 0], [4, 0, 0, 1]])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
    }
}
