import AppKit
import CutawayModel
import CutawayRender
import CutawayScene
import CutawayTestSupport
import CutawayUI
import XCTest

@testable import Cutaway

/// End to end: in the running app, going from 2D to 3D, and collapsing
/// node 2 in 3D, each show frames on the way, and nothing is drawn once they are over
/// (C-PREV-11, C-PREV-12, C-SCENE-10).
final class TransitionExitTests: XCTestCase {
    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Whether one of the points lies on the way from `start` to `end`, away from both.
    private func onTheWay(_ points: [CGPoint], from start: CGPoint, to end: CGPoint) -> Bool {
        points.contains {
            distance($0, start) > 1 && distance($0, end) > 1
                && distance($0, start) < distance(start, end)
        }
    }

    /// Where the fixture's layers are on screen; nil for a layer that is not drawn.
    @MainActor
    private func centers(_ preview: PreviewView) -> [CGPoint?] {
        (1...9).map { preview.imagePoint(ofCenterOf: $0) }
    }

    /// Turns the run loop for a while, from the frame the preview was last asked for, and
    /// returns nil when the preview drew nothing meanwhile; otherwise what it drew.
    @MainActor
    private func drawing(_ preview: PreviewView, for seconds: Double = 0.5) async throws
        -> String?
    {
        try await AppWindows.waitForPendingFrame(of: preview)
        let frames = preview.frameCount
        let before = centers(preview)
        try await Task.sleep(for: .seconds(seconds))
        let drawn = preview.frameCount - frames
        guard drawn > 0 else { return nil }
        let moved = centers(preview) != before ? "layers moved" : "no layer moved"
        return "\(drawn) frame(s), \(moved), in a transition: \(preview.isInTransition)"
            + AppWindows.displayAsleepNote
    }

    /// Whether the preview comes to rest within `limit`: half a second without drawing. The
    /// last screenshots may still be on their way, and new images alone are shown a little
    /// later than they come (C-SCALE-02).
    @MainActor
    private func settles(_ preview: PreviewView, within limit: Double = 3) async throws -> Bool {
        let deadline = Date().addingTimeInterval(limit)
        while Date() < deadline {
            if try await drawing(preview) == nil { return true }
        }
        return false
    }

    @MainActor
    func test_C_PREV_11_C_PREV_12_theRunningAppGoesOverToAnotherModeAndAnotherExpansion()
        async throws
    {
        let server = try await AppWindows.startMockServer(
            try .fixtures("handshake", "app-icon", "hierarchy", "layer-details"))
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
        XCTAssertTrue(AppWindows.isShown(preview))
        let delegate = try XCTUnwrap(NSApplication.shared.delegate as? AppDelegate)
        let model = try XCTUnwrap(delegate.store)
        let inspection = try XCTUnwrap(model.inspectedApp.flatMap { model.inspection(at: $0) })
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            throw XCTSkip("Reduce Motion is on: the preview makes no transitions")
        }
        let wait = try await settles(preview)
        XCTAssertTrue(wait, "settled before the switch")

        // 2D to 3D, as a click on the switch does.
        let flat = try XCTUnwrap(preview.imagePoint(ofCenterOf: 3))
        let control = try XCTUnwrap(
            AppWindows.views(identifier: "inspection.mode").first as? NSSegmentedControl)
        var frames = preview.frameCount
        control.selectedSegment = 1
        control.sendAction(control.action, to: control.target)
        XCTAssertEqual(inspection.previewMode, .threeD)
        XCTAssertTrue(preview.isInTransition)
        let turning = try await AppWindows.samples(whileInTransition: preview) {
            try XCTUnwrap(preview.imagePoint(ofCenterOf: 3))
        }
        let threeD = try XCTUnwrap(turning.last)
        XCTAssertTrue(
            onTheWay(turning.dropLast(), from: flat, to: threeD),
            "a frame with layer 3 between \(flat) and \(threeD): \(turning)")
        XCTAssertGreaterThan(preview.frameCount - frames, 1, "more than one frame")
        let after3D = try await drawing(preview)
        XCTAssertNil(after3D, "nothing is drawn once the turn is over")

        // Collapsing node 2 in 3D brings layer 3 down onto node 2's level. Where it ends is
        // where the scene puts it just before the end, when it goes.
        let before = inspection.layout
        frames = preview.frameCount
        inspection.setExpanded(2, false)
        XCTAssertTrue(preview.isInTransition)
        let scale = preview.window?.backingScaleFactor ?? 1
        let transition = try XCTUnwrap(
            SceneTransition(from: before.presentation, to: inspection.layout))
        let last = try XCTUnwrap(
            transition.project(
                progress: 1 - 1e-9, lens: Lens(inspection.camera),
                viewport: preview.viewport,
                selected: inspection.selectedLayerID, hovered: inspection.hoveredLayerID
            ).items.first { $0.layerID == 3 }?.center)
        let onNode2 = CGPoint(x: last.x * scale, y: last.y * scale)
        let collapsing = try await AppWindows.samples(whileInTransition: preview) {
            preview.imagePoint(ofCenterOf: 3)
        }
        XCTAssertNil(collapsing.last.flatMap { $0 }, "layer 3 goes at the end")
        XCTAssertTrue(
            onTheWay(collapsing.compactMap { $0 }, from: threeD, to: onNode2),
            "a frame with layer 3 between \(threeD) and \(onNode2): \(collapsing)")
        XCTAssertGreaterThan(preview.frameCount - frames, 1, "more than one frame")
        let afterCollapse = try await drawing(preview)
        XCTAssertNil(afterCollapse, "nothing is drawn once the collapse is over")
        // Collapsed, node 2 asks for its group image, which the replayed script does not
        // hold: no check of mismatches.
    }
}
