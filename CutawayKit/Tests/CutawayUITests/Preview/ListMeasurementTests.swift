import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// Holding ⌥ with the pointer on a row of the hierarchy list measures that row's layer
/// against the selected one, as over the preview (C-PREV-10, C-PREV-14).
@MainActor
final class ListMeasurementTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    /// The inspector's panes for the `hierarchy` fixture with the `layer-details` images,
    /// layer 3 selected and the card 4 expanded, in a window that is never shown.
    private func panes(
        mode: PreviewMode = .twoD
    ) throws -> (InspectorSplitViewController, PreviewView, InspectionStore, NSWindow) {
        let model = InspectionStore(session: Session(channel: InertChannel(), client: Self.client))
        model.apply(try Fixtures.hierarchy())
        let details = try Fixtures.layerDetails(scenario: "layer-details")
        try Wait.running { await model.applyDetails(details) }
        model.setExpanded(4, true)
        model.select(3)
        model.setPreviewMode(mode)
        let split = InspectorSplitViewController(store: model, appName: "Demo")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1300, height: 900), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1300, height: 900))
        window.layoutIfNeeded()
        try Wait.running { await split.previewController.texturesSettled() }
        return (split, try XCTUnwrap(split.previewController.preview), model, window)
    }

    /// The pointer on the row of `id`, or off every row for nil, as the list reports it.
    private func pointList(at id: UInt64?, in split: InspectorSplitViewController) {
        let hierarchy = split.hierarchyController
        hierarchy.outlineView.pointerDidMove?(id.map { hierarchy.row(of: $0) } ?? -1)
    }

    private func values(_ preview: PreviewView) -> [Double] {
        preview.drawList.measurement?.labels.map(\.value) ?? []
    }

    func test_C_PREV_10_optionOnAHierarchyRowMeasuresItsLayer() throws {
        let (split, preview, model, window) = try panes()
        preview.modifiersChanged([.option])
        pointList(at: 8, in: split)
        XCTAssertEqual(model.hoveredLayerID, 8)
        // The same as with the pointer on layer 8 in the preview.
        XCTAssertEqual(values(preview), [26.5, 68])
        XCTAssertEqual(preview.distanceLabels.map(\.text), ["26.5", "68"])
        XCTAssertEqual(model.selectedLayerID, 3, "the selection stays")
        withExtendedLifetime(window) {}
    }

    func test_C_PREV_10_optionOnTheSelectedRowOrAnUndrawnLayerMeasuresNothing() throws {
        let (split, preview, _, window) = try panes()
        preview.modifiersChanged([.option])
        pointList(at: 3, in: split)
        XCTAssertNil(preview.drawList.measurement, "the selected row")
        // Layer 5 is hidden, so it is not drawn.
        pointList(at: 5, in: split)
        XCTAssertNil(preview.drawList.measurement, "a layer the preview does not draw")
        XCTAssertEqual(preview.distanceLabels.count, 0)
        pointList(at: 8, in: split)
        XCTAssertNotNil(preview.drawList.measurement)
        withExtendedLifetime(window) {}
    }

    func test_C_PREV_10_leavingTheListOrLettingGoOfOptionEndsTheMeasurement() throws {
        let (split, preview, _, window) = try panes()
        pointList(at: 8, in: split)
        XCTAssertNil(preview.drawList.measurement, "without ⌥")
        preview.modifiersChanged([.option])
        XCTAssertNotNil(preview.drawList.measurement, "⌥ pressed with the pointer still")

        preview.modifiersChanged([])
        XCTAssertNil(preview.drawList.measurement, "⌥ released")
        preview.modifiersChanged([.option])
        XCTAssertNotNil(preview.drawList.measurement)

        pointList(at: nil, in: split)
        XCTAssertNil(preview.drawList.measurement, "the pointer left the rows")
        XCTAssertEqual(preview.distanceLabels.count, 0)
        withExtendedLifetime(window) {}
    }

    func test_C_PREV_14_optionOnAHierarchyRowMeasuresIn3D() throws {
        let (split, preview, _, window) = try panes(mode: .threeD)
        preview.modifiersChanged([.option])
        pointList(at: 2, in: split)
        // The same as with the pointer on layer 2 in the preview (PreviewMeasurementTests).
        XCTAssertEqual(values(preview), [96.5, 96.5, 108, 720])
        withExtendedLifetime(window) {}
    }
}
