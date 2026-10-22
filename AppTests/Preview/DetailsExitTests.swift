import AppKit
import CutawayRender
import CutawayTestSupport
import CutawayUI
import CutawayWire
import Metal
import XCTest

/// End to end: the running app shows the screenshots over the connection,
/// one chunk after another, and asks with this Mac's texture limit (C-REND-05).
final class DetailsExitTests: XCTestCase {
    private let red = Pixel(blue: 0, green: 0, red: 255, alpha: 255)
    private let green = Pixel(blue: 0, green: 255, red: 0, alpha: 255)

    @MainActor
    func test_C_DET_01_theRunningAppShowsTheScreenshotsAsTheyArrive() async throws {
        let gate = MockGate()
        var details = try MockScript.fixtures("layer-details").steps
        details.insert(.hold(gate), at: 2)  // after chunk 0, which brings layer 3
        let steps = try MockScript.fixtures("handshake", "app-icon", "hierarchy").steps + details
        let server = try await AppWindows.startMockServer(MockScript(steps: steps))
        addTeardownBlock {
            // Leave the app as it was for the other tests, even when this one failed. A
            // server stopped while it holds at the gate would hang: open it first.
            await AppWindows.closeInspectors()
            await gate.open()
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }
        try await AppWindows.chooseApp(named: "Demo", server: server)

        // The layers come first, then the first chunk: layer 3 is red, layer 4 has no image.
        var deadline = Date().addingTimeInterval(5)
        while AppWindows.views(identifier: PreviewView.identifier).first == nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let preview = try XCTUnwrap(
            AppWindows.views(identifier: PreviewView.identifier).first as? PreviewView)
        let firstChunk = try await AppWindows.waitFor(red, at: 3, in: preview)
        XCTAssertTrue(firstChunk, "layer 3's screenshot did not appear")
        XCTAssertFalse(
            AppWindows.isClose(try AppWindows.centerPixel(of: 4, in: preview), green),
            "chunk 1 is held")

        // The toolbar's capsule shows its progress (C-WIN-06).
        let progress = try XCTUnwrap(AppWindows.views(identifier: "toolbar.capsule.progress").first)
        XCTAssertTrue(AppWindows.isShown(progress))

        // The rest arrives.
        await gate.open()
        let secondChunk = try await AppWindows.waitFor(green, at: 4, in: preview)
        XCTAssertTrue(secondChunk, "layer 4's screenshot did not appear")
        deadline = Date().addingTimeInterval(5)
        while AppWindows.isShown(progress), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertFalse(AppWindows.isShown(progress), "every screenshot is settled")

        // C-REND-05: the request carried this Mac's limit.
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let requests = await server.receivedFrames.compactMap { frame -> GetLayerDetails? in
            guard case .getLayerDetails(let request) = frame.body else { return nil }
            return request
        }
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests.first?.maxTextureDimension, UInt32(Renderer.maxTextureDimension(of: device)))

        let connections = await server.connectionCount
        XCTAssertEqual(connections, 1)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        // Leave the app as it was for the other tests.
        AppWindows.closeInspectors()
        await server.stop()
        let gone = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        XCTAssertNil(gone)
    }
}
