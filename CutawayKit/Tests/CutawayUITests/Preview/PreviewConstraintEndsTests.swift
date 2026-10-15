import AppKit
import CutawayModel
import CutawayRender
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// The preview marks the other ends of the selected layer's constraints, layout guides
/// among them, and writes no names over them: all of them with the switch on (C-LAYOUT-04),
/// otherwise those pointed at in the attribute panel (C-LAYOUT-07).
final class PreviewConstraintEndsTests: XCTestCase {
    /// The safe area of layer 2 in the `layout-constraints` fixture.
    private static let safeArea = SceneRect(x: 0, y: 59, width: 393, height: 759)
    private static let layer3Ends: [SceneMark] = [.layer(2), .area(safeArea, in: 2), .layer(4)]

    /// A preview controller in a window that is never shown, laid out at 480 × 900.
    @MainActor
    private func previewInWindow(
        _ model: InspectionStore
    ) throws -> (PreviewViewController, PreviewView, NSWindow) {
        let controller = PreviewViewController(store: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 900), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 480, height: 900))
        window.layoutIfNeeded()
        return (controller, try XCTUnwrap(controller.preview), window)
    }

    /// Waits without holding the main actor, so that answers reach the model.
    @MainActor
    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        await Wait.until { await MainActor.run { condition() } }
    }

    /// The text fields shown anywhere in `view`. The tags (C-PREV-16) are hidden while no
    /// layer is selected or hovered in the preview itself.
    @MainActor
    private func texts(in view: NSView) -> [NSTextField] {
        view.subviews.filter { !$0.isHidden }
            .flatMap { ($0 as? NSTextField).map { [$0] } ?? texts(in: $0) }
    }

    @MainActor
    func test_C_LAYOUT_04_theSelectedLayersEndsAreMarkedAndNoGuideIsNamed() async throws {
        let (model, session, server) = try await ConstraintsSectionTests.inspection(answering: [3])
        model.setShowsAllConstraintEnds(true)
        let (_, preview, window) = try previewInWindow(model)
        XCTAssertEqual(preview.drawList.marks, [])

        model.select(3)
        let settled1 = await waitUntil { preview.drawList.marks.map(\.mark) == Self.layer3Ends }
        XCTAssertTrue(settled1)
        // Text over the drawing does not turn with the layers and reads as part of the inspected app.
        XCTAssertEqual(texts(in: preview), [])

        model.setPreviewMode(.threeD)
        let settled2 = await waitUntil { preview.drawList.marks.count == 3 }
        XCTAssertTrue(settled2)
        XCTAssertEqual(texts(in: preview), [])

        // Nothing selected: no marks.
        model.select(nil)
        let settled3 = await waitUntil { preview.drawList.marks.isEmpty }
        XCTAssertTrue(settled3)

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_04_newEndsAreDrawnAndNothingMoreWhileTheyStay() async throws {
        let (model, session, server) = try await ConstraintsSectionTests.inspection(answering: [3])
        model.setShowsAllConstraintEnds(true)
        let (_, preview, window) = try previewInWindow(model)
        let drawn = await waitUntil { preview.frameCount >= 1 }
        XCTAssertTrue(drawn)
        try await Task.sleep(for: .milliseconds(300))
        let before = preview.frameCount

        model.select(3)
        let marked = await waitUntil { preview.drawList.marks.count == 3 }
        XCTAssertTrue(marked)
        try await Task.sleep(for: .milliseconds(300))
        // The selection, then the ends: drawn together or one after the other.
        XCTAssertTrue((before + 1...before + 2).contains(preview.frameCount), "\(preview.frameCount - before) frames")
        let after = preview.frameCount

        // Nothing more is drawn while the ends stay the same.
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(preview.frameCount, after)

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LAYOUT_07_withTheSwitchOffOnlyThePointedRowsEndsAreDrawnOneFrameAChange()
        async throws
    {
        let (model, session, server) = try await ConstraintsSectionTests.inspection(answering: [3])
        let (_, preview, window) = try previewInWindow(model)
        model.select(3)
        let loaded = await waitUntil {
            if case .loaded = model.attributes.state { return true }
            return false
        }
        XCTAssertTrue(loaded)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(preview.drawList.marks, [], "selecting marks nothing")
        let before = preview.frameCount

        model.pointConstraints([1], stresses: true)
        let pointed = await waitUntil { preview.drawList.marks.map(\.mark) == [Self.layer3Ends[1]] }
        XCTAssertTrue(pointed)
        XCTAssertEqual(preview.drawList.marks.map(\.emphasis), [.emphasized])
        model.leaveConstraints([1])
        let left = await waitUntil { preview.drawList.marks.isEmpty }
        XCTAssertTrue(left)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(preview.frameCount - before, 2, "a frame for each change, nothing more")

        // The switch draws them all.
        model.toggleConstraintEnds()
        let all = await waitUntil { preview.drawList.marks.map(\.mark) == Self.layer3Ends }
        XCTAssertTrue(all)

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }
}
