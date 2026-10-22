import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// The ancestors under the attribute panel's header (C-ATTR-16), on the `hierarchy` fixture
/// inspected from an archive, and on a deeper chain of views.
@MainActor
final class AncestorsBarTests: XCTestCase {
    private func inspection() async throws -> InspectionStore {
        let data = try Fixtures.archive(state: Data())
        let model = InspectionStore(
            source: ArchiveSource(decoder: try ArchiveDecoder(data)), maxTextureDimension: 4096,
            newLayers: .expanded)
        model.enter()
        let loaded = await Wait.until { await model.loadState == .loaded }
        XCTAssertTrue(loaded)
        return model
    }

    /// The panel, wired to the store as the window wires it, in a window that is never shown,
    /// wide enough for the fixture's three ancestors.
    private func panel(
        for model: InspectionStore, width: CGFloat = 360
    ) -> (AttributesViewController, NSWindow) {
        let controller = AttributesViewController(
            store: model.attributes, appName: "Demo",
            inputs: AttributesPanelInputs(layer: model.selectedLayerSummary, tree: model.$tree.eraseToAnyPublisher()),
            actions: AttributesPanelActions(
                showLayer: { [weak model] in model?.showLayer($0) }, hoverLayer: { [weak model] in model?.hover($0) }),
            loadingDelay: 0)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: width, height: 600))
        window.layoutIfNeeded()
        return (controller, window)
    }

    func test_C_ATTR_16_clickingAnAncestorSelectsIt() async throws {
        let model = try await inspection()
        let (controller, window) = panel(for: model)
        model.select(5)
        window.layoutIfNeeded()
        let card = try XCTUnwrap(controller.ancestorsBar.buttons.first { $0.ancestor.id == 4 })
        card.performClick(nil)
        XCTAssertEqual(model.selectedLayerID, 4)
        XCTAssertEqual(controller.ancestorsBar.buttons.map(\.ancestor.id), [1, 2])

        // Outside the focus: the focus goes, as for the other end of a constraint.
        model.focus(on: 4)
        model.select(5)
        window.layoutIfNeeded()
        try XCTUnwrap(controller.ancestorsBar.buttons.first { $0.ancestor.id == 2 }).performClick(nil)
        XCTAssertNil(model.focusedLayerID)
        XCTAssertEqual(model.selectedLayerID, 2)
        withExtendedLifetime(window) {}
    }

    func test_C_ATTR_16_pointingAtAnAncestorHoversIt() async throws {
        let model = try await inspection()
        let (controller, window) = panel(for: model)
        model.select(5)
        window.layoutIfNeeded()
        let card = try XCTUnwrap(controller.ancestorsBar.buttons.first { $0.ancestor.id == 4 })
        card.pointerEntered()
        XCTAssertEqual(model.hoveredLayerID, 4)
        XCTAssertTrue(card.isHovered)
        card.pointerExited()
        XCTAssertNil(model.hoveredLayerID)
        XCTAssertFalse(card.isHovered)

        // Leaving one it never entered says nothing: the pointer is on something else now.
        model.hover(7)
        card.pointerExited()
        XCTAssertEqual(model.hoveredLayerID, 7)

        // Not while it cannot be used.
        controller.ancestorsBar.isEnabled = false
        card.pointerEntered()
        XCTAssertEqual(model.hoveredLayerID, 7)
        withExtendedLifetime(window) {}
    }
}
