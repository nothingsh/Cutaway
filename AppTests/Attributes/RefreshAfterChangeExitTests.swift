import AppKit
import CutawayRender
import CutawayTestSupport
import CutawayUI
import CutawayWire
import XCTest

@testable import Cutaway

/// End to end: in the running app, a change made in the attribute panel
/// takes the window again and asks for the screenshots of the changed layer and of the
/// layers that moved, and no others (C-DET-06).
final class RefreshAfterChangeExitTests: XCTestCase {
    private static func detailRequests(_ server: MockServer) async -> [GetLayerDetails] {
        await server.receivedFrames.compactMap { frame in
            guard case .getLayerDetails(let request) = frame.body else { return nil }
            return request
        }
    }

    @MainActor
    func test_C_DET_06_theRunningAppRefreshesThePreviewAfterAChange() async throws {
        // The change moves layer 6 by 20 points: the app answers the window with that.
        var moved = try Fixtures.hierarchy()
        let six = try XCTUnwrap(moved.nodes.firstIndex { $0.id == 6 })
        moved.nodes[six].position?.y += 20
        var steps = try MockScript.fixtures(
            "handshake", "app-icon", "hierarchy", "layer-details", "layer-details").steps
        steps += Array(try MockScript.fixtures("set-attribute").steps.prefix(2))
        steps += [
            .expect(.getSubtree, as: 31),
            .send(Frame(requestID: 31, body: .hierarchy(moved))),
        ]
        // The screenshots, and the label's attributes and constraints again (C-LAYOUT-01), in
        // either order: both get the label as the change left it.
        let label = LayerDetail(
            layerID: 3, status: .ok, solo: nil, group: nil,
            attributeGroups: try Fixtures.setAttributeResults()[0].attributeGroups)
        steps += MockScript.layerDetailsSteps([label], as: 70)
        steps += MockScript.layerDetailsSteps([label], as: 71)
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
        XCTAssertTrue(arrived, "the first round of screenshots")

        // Select the label and change its text in the panel.
        let outline = try XCTUnwrap(
            AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)
        outline.selectRowIndexes([2], byExtendingSelection: false)
        var deadline = Date().addingTimeInterval(5)
        // The label's text, in its text area of several lines (C-ATTR-05).
        var area: NSTextView?
        while area == nil, Date() < deadline {
            area = AppWindows.views(identifier: "attributes.editor.text")
                .compactMap { $0 as? NSTextView }.first { $0.string == "Hello" }
            try await Task.sleep(for: .milliseconds(50))
        }
        let text = try XCTUnwrap(area, "the label's text")
        let window = try XCTUnwrap(text.window)
        XCTAssertTrue(window.makeFirstResponder(text))
        text.string = "Welcome back"
        text.didChangeText()
        window.makeFirstResponder(nil)

        deadline = Date().addingTimeInterval(5)
        while await Self.detailRequests(server).count < 4, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let frames = await server.receivedFrames
        let kinds = frames.map { MessageKind($0.body) }
        let set = try XCTUnwrap(kinds.firstIndex(of: .setAttribute))
        let subtree = try XCTUnwrap(kinds.firstIndex(of: .getSubtree))
        XCTAssertLessThan(set, subtree, "the window is taken after the change")
        XCTAssertEqual(frames[subtree].body, .getSubtree(GetSubtree(rootID: 1)))
        // The label's group, and layer 6, which moved; nothing else.
        let requests = await Self.detailRequests(server)
        let screenshots = requests.dropFirst(2).filter {
            !($0.requests.first?.wantAttributes ?? true)
        }
        XCTAssertEqual(screenshots.map { $0.requests.map(\.layerID) }, [[3, 6]])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
    }
}
