import AppKit
import CutawayModel
import CutawayRender
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// Holding ⌥ over another layer measures it against the selected one, in 2D (C-PREV-10) and
/// in 3D (C-PREV-14).
final class PreviewMeasurementTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    /// A model with the `hierarchy` fixture and the `layer-details` images, layer 3 selected.
    @MainActor
    private func model(selecting id: UInt64? = 3) throws -> InspectionStore {
        let model = InspectionStore(session: Session(channel: InertChannel(), client: Self.client))
        model.apply(try Fixtures.hierarchy())
        let details = try Fixtures.layerDetails(scenario: "layer-details")
        try Wait.running { await model.applyDetails(details) }
        model.select(id)
        return model
    }

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
        // Images the model held before the preview was made are uploaded once decompressed.
        try Wait.running { await controller.texturesSettled() }
        return (controller, try XCTUnwrap(controller.preview), window)
    }

    @MainActor
    private func mouse(
        _ type: NSEvent.EventType, at point: NSPoint, option: Bool = true, in view: NSView
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: view.convert(point, to: nil),
            modifierFlags: option ? [.option] : [], timestamp: 0,
            windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0,
            clickCount: 1, pressure: 1)!
    }

    /// Moves the pointer over the middle of a layer, with ⌥ held unless told otherwise.
    @MainActor
    private func point(
        at id: UInt64, option: Bool = true, in preview: PreviewView
    ) throws {
        let center = try XCTUnwrap(preview.viewPoint(ofCenterOf: id))
        preview.mouseMoved(with: mouse(.mouseMoved, at: center, option: option, in: preview))
    }

    @MainActor
    private func values(_ preview: PreviewView) -> [Double] {
        preview.drawList.measurement?.labels.map(\.value) ?? []
    }

    // MARK: - Measuring

    @MainActor
    func test_C_PREV_10_holdingOptionOverAnotherLayerMeasuresIt() throws {
        let (_, preview, window) = try previewInWindow(try model())
        try point(at: 8, in: preview)
        XCTAssertEqual(values(preview), [26.5, 68])
        XCTAssertEqual(preview.distanceLabels.map(\.text), ["26.5", "68"])
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_10_overTheSelectionOrEmptyCanvasNothingIsMeasured() throws {
        let (_, preview, window) = try previewInWindow(try model())
        try point(at: 3, in: preview)
        XCTAssertNil(preview.drawList.measurement, "over the selection")
        XCTAssertEqual(preview.distanceLabels.count, 0)
        // Above the window's top: no layer.
        preview.mouseMoved(with: mouse(.mouseMoved, at: NSPoint(x: 5, y: 895), in: preview))
        XCTAssertNil(preview.drawList.measurement, "over nothing")
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_10_theMeasurementGoesWhenOptionIsReleasedOrThePointerLeaves() throws {
        let (_, preview, window) = try previewInWindow(try model())
        try point(at: 8, in: preview)
        XCTAssertNotNil(preview.drawList.measurement)

        preview.modifiersChanged([])
        XCTAssertNil(preview.drawList.measurement, "⌥ released")
        XCTAssertEqual(preview.distanceLabels.count, 0)

        // ⌥ pressed again without moving the pointer.
        preview.modifiersChanged([.option])
        XCTAssertEqual(values(preview), [26.5, 68], "⌥ pressed")

        preview.mouseExited(with: PreviewViewTests.exit(preview))
        XCTAssertNil(preview.drawList.measurement, "the pointer left")
        XCTAssertEqual(preview.distanceLabels.count, 0)

        // Moving without ⌥ does not measure.
        try point(at: 8, option: false, in: preview)
        XCTAssertNil(preview.drawList.measurement, "without ⌥")
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_10_nothingIsMeasuredWhileTheButtonIsDown() throws {
        let (_, preview, window) = try previewInWindow(try model())
        try point(at: 8, in: preview)
        let center = try XCTUnwrap(preview.viewPoint(ofCenterOf: 8))
        preview.mouseDown(with: mouse(.leftMouseDown, at: center, in: preview))
        XCTAssertNil(preview.drawList.measurement, "pressed")
        // The click selects node 8; over node 3 it measures again, the other way round.
        preview.mouseUp(with: mouse(.leftMouseUp, at: center, in: preview))
        try point(at: 3, in: preview)
        XCTAssertEqual(values(preview), [26.5, 68], "released")
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_10_aDragWithOptionReleasedOutsideThePreviewMeasuresNothing() throws {
        let (_, preview, window) = try previewInWindow(try model())
        let center = try XCTUnwrap(preview.viewPoint(ofCenterOf: 8))
        let outside = NSPoint(x: preview.bounds.maxX + 50, y: center.y)
        preview.mouseDown(with: mouse(.leftMouseDown, at: center, in: preview))
        preview.mouseDragged(with: mouse(.leftMouseDragged, at: outside, in: preview))
        preview.mouseUp(with: mouse(.leftMouseUp, at: outside, in: preview))
        XCTAssertNil(preview.drawList.measurement)
        XCTAssertEqual(preview.distanceLabels.count, 0)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_10_zoomAndPanRedrawTheMeasurementWithTheSameValues() throws {
        let model = try model()
        let (controller, preview, window) = try previewInWindow(model)
        try point(at: 8, in: preview)
        let before = try XCTUnwrap(preview.drawList.measurement)
        let labelBefore = preview.distanceLabels[0].frame
        // About the middle of node 8, which stays under the pointer.
        let center = try XCTUnwrap(preview.drawList.items.first { $0.layerID == 8 }?.center)
        model.zoom(
            by: 1.5, about: center,
            in: preview.viewport)
        model.pan(by: 10, 5)
        withExtendedLifetime(controller) {}
        let after = try XCTUnwrap(preview.drawList.measurement)
        XCTAssertNotEqual(after.lines, before.lines)
        XCTAssertEqual(after.measurement, before.measurement)
        XCTAssertEqual(preview.distanceLabels.map(\.text), ["26.5", "68"])
        XCTAssertNotEqual(preview.distanceLabels[0].frame, labelBefore)
        // Still below the middle of its line.
        let label = preview.distanceLabels[0]
        let frame = preview.convert(label.frame, from: label.superview)
        let top = preview.isFlipped ? frame.minY : preview.bounds.height - frame.maxY
        XCTAssertEqual(frame.midX, after.labels[0].middle.x, accuracy: 0.5)
        XCTAssertEqual(top, after.labels[0].middle.y + 4, accuracy: 0.5)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_10_measuringChangesNeitherTheSelectionNorTheHover() throws {
        let model = try model()
        let (_, preview, window) = try previewInWindow(model)
        try point(at: 8, option: false, in: preview)
        XCTAssertEqual(model.hoveredLayerID, 8)
        preview.modifiersChanged([.option])
        XCTAssertNotNil(preview.drawList.measurement)
        XCTAssertEqual(model.selectedLayerID, 3)
        XCTAssertEqual(model.hoveredLayerID, 8)
        XCTAssertEqual(preview.drawList.items.first { $0.layerID == 8 }?.highlight, .hovered)
        preview.modifiersChanged([])
        XCTAssertEqual(model.selectedLayerID, 3)
        XCTAssertEqual(model.hoveredLayerID, 8)

        // A click with ⌥ held still selects.
        preview.modifiersChanged([.option])
        let center = try XCTUnwrap(preview.viewPoint(ofCenterOf: 8))
        preview.mouseDown(with: mouse(.leftMouseDown, at: center, in: preview))
        preview.mouseUp(with: mouse(.leftMouseUp, at: center, in: preview))
        XCTAssertEqual(model.selectedLayerID, 8)
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_10_aChangeOfOptionThatChangesNothingDrawsNothing() throws {
        let (_, preview, window) = try previewInWindow(try model(selecting: nil))
        try point(at: 8, option: false, in: preview)
        XCTAssertTrue(PreviewViewTests.waitForFrames(preview, atLeast: 1))
        PreviewViewTests.settle()
        let settled = preview.frameCount
        preview.modifiersChanged([.option])
        PreviewViewTests.settle()
        XCTAssertEqual(preview.frameCount, settled, "nothing selected: nothing to measure")
        withExtendedLifetime(window) {}
    }

    // MARK: - In 3D

    /// The model in 3D, layer 3 selected.
    @MainActor
    private func model3D(selecting id: UInt64? = 3) throws -> InspectionStore {
        let model = try model(selecting: id)
        model.setPreviewMode(.threeD)
        return model
    }

    /// The still picture of the model's state, measuring to `measuring`.
    @MainActor
    private func still(
        _ model: InspectionStore, _ preview: PreviewView, measuring: UInt64?
    ) -> DrawList {
        model.layout.project(
            camera: model.camera,
            viewport: preview.viewport,
            selected: model.selectedLayerID, hovered: model.hoveredLayerID, measuring: measuring)
    }

    @MainActor
    func test_C_PREV_14_holdingOptionOverAnotherLayerMeasuresItIn3D() throws {
        let model = try model3D()
        let (_, preview, window) = try previewInWindow(model)
        try point(at: 2, in: preview)
        XCTAssertEqual(model.hoveredLayerID, 2)
        XCTAssertEqual(values(preview), [96.5, 96.5, 108, 720])
        XCTAssertEqual(preview.distanceLabels.map(\.text), ["96.5", "96.5", "108", "720"])
        XCTAssertEqual(preview.drawList, still(model, preview, measuring: 2))
        XCTAssertEqual(preview.drawList.measurement?.links.count, 4, "2 is a level below 3")
        // Each value below or right of the middle of its line, as in 2D.
        let drawnLabels = try XCTUnwrap(preview.drawList.measurement).labels
        for (label, drawn) in zip(preview.distanceLabels, drawnLabels) {
            let frame = preview.convert(label.frame, from: label.superview)
            let top = preview.isFlipped ? frame.minY : preview.bounds.height - frame.maxY
            if drawn.axis == .horizontal {
                XCTAssertEqual(frame.midX, drawn.middle.x, accuracy: 0.5)
                XCTAssertEqual(top, drawn.middle.y + 4, accuracy: 0.5)
            } else {
                XCTAssertEqual(frame.minX, drawn.middle.x + 4, accuracy: 0.5)
            }
        }
        withExtendedLifetime(window) {}
    }

    @MainActor
    func test_C_PREV_14_turningAndSpacingRedrawTheMeasurementWithTheSameValues() throws {
        let model = try model3D()
        let (controller, preview, window) = try previewInWindow(model)
        try point(at: 2, in: preview)
        let before = try XCTUnwrap(preview.drawList.measurement)
        model.rotate(byDragOf: -40, 20)
        model.setLayerSpacing(model.camera.layerSpacing * 2)
        withExtendedLifetime(controller) {}
        // The view moved under the pointer, whose middle of layer 2 another layer now covers:
        // over a part of layer 2 still in sight.
        model.hover(2)
        let after = try XCTUnwrap(preview.drawList.measurement)
        XCTAssertNotEqual(after.lines, before.lines)
        XCTAssertEqual(after.measurement, before.measurement)
        XCTAssertEqual(preview.drawList, still(model, preview, measuring: 2))
        XCTAssertEqual(preview.distanceLabels.map(\.text), ["96.5", "96.5", "108", "720"])
        withExtendedLifetime(window) {}
    }

    // MARK: - The values as written

    func test_C_PREV_10_aValueIsWrittenWithOneDecimalAtMost() {
        XCTAssertEqual(PreviewPaneText.distanceText(26.5), "26.5")
        XCTAssertEqual(PreviewPaneText.distanceText(68), "68")
        XCTAssertEqual(PreviewPaneText.distanceText(15.057713659400522), "15.1")
        XCTAssertEqual(PreviewPaneText.distanceText(0.96), "1")
        XCTAssertEqual(PreviewPaneText.distanceText(720), "720")
        XCTAssertEqual(PreviewPaneText.distanceText(74.9038105676658), "74.9")
        XCTAssertEqual(PreviewPaneText.distanceText(1e20), "100000000000000000000")
    }
}
