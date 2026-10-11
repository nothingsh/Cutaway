import AppKit
import CutawayModel
import CutawayRender
import CutawayTestSupport
import CutawayUI
import XCTest

@testable import Cutaway

/// End to end: in the running app the preview is turned, zoomed and moved
/// with synthesized mouse and scroll events, and the hidden layer appears once hidden layers
/// are shown.
final class PreviewControlsExitTests: XCTestCase {
    @MainActor
    private func one<View: NSView>(_ identifier: String, as type: View.Type) throws -> View {
        try XCTUnwrap(AppWindows.views(identifier: identifier).first as? View, identifier)
    }

    /// A mouse event at a point of the preview.
    @MainActor
    private func mouse(
        _ type: NSEvent.EventType, at point: NSPoint, in preview: PreviewView
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: preview.convert(point, to: nil), modifierFlags: [],
            timestamp: 0, windowNumber: preview.window?.windowNumber ?? 0, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    /// A trackpad scroll of (dx, dy) points, with ⌘ when asked.
    private func scroll(dx: Int32, dy: Int32, command: Bool = false) throws -> NSEvent {
        let event = try XCTUnwrap(CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx,
            wheel3: 0))
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        // Always set: an event made without a source carries the keys held at that moment, and a
        // ⌘ held then turns the scroll into a zoom (C-PREV-05) that moves nothing.
        event.flags = command ? .maskCommand : []
        return try XCTUnwrap(NSEvent(cgEvent: event))
    }

    /// The middle of a drawn layer, in the preview's coordinates.
    @MainActor
    private func center(of id: UInt64, in preview: PreviewView) throws -> NSPoint {
        let point = try XCTUnwrap(preview.imagePoint(ofCenterOf: id), "layer \(id) is not drawn")
        let scale = preview.window?.backingScaleFactor ?? 1
        // From the image's pixels, top down, to the view's points, bottom up.
        return NSPoint(x: point.x / scale, y: preview.bounds.height - point.y / scale)
    }

    @MainActor
    func test_C_PREV_04_theRunningAppTurnsZoomsMovesAndShowsHiddenLayers() async throws {
        let server = try await AppWindows.startMockServer(
            try .fixtures("handshake", "app-icon", "hierarchy", "layer-details"))
        addTeardownBlock {
            await AppWindows.closeInspectors()
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }
        try await AppWindows.chooseApp(named: "Demo", server: server)
        let preview = try one(PreviewView.identifier, as: PreviewView.self)
        let arrived = try await AppWindows.waitFor(
            Pixel(blue: 0, green: 255, red: 0, alpha: 255), at: 4, in: preview)
        XCTAssertTrue(arrived, "layer 4's screenshot did not appear")
        let delegate = try XCTUnwrap(NSApplication.shared.delegate as? AppDelegate)
        let model = try XCTUnwrap(delegate.store)
        let inspection = try XCTUnwrap(model.inspectedApp.flatMap { model.inspection(at: $0) })

        // 3D, as a click on the switch does.
        let control = try one("inspection.mode", as: NSSegmentedControl.self)
        control.selectedSegment = 1
        control.sendAction(control.action, to: control.target)
        XCTAssertEqual(inspection.previewMode, .threeD)

        // A drag to the right turns the view, and selects nothing (C-PREV-04).
        let selected = inspection.selectedLayerID
        let before = try center(of: 3, in: preview)
        let start = try center(of: 4, in: preview)
        preview.mouseDown(with: mouse(.leftMouseDown, at: start, in: preview))
        for step in 1...4 {
            preview.mouseDragged(with: mouse(
                .leftMouseDragged, at: NSPoint(x: start.x + Double(step) * 15, y: start.y),
                in: preview))
        }
        preview.mouseUp(with: mouse(
            .leftMouseUp, at: NSPoint(x: start.x + 60, y: start.y), in: preview))
        let turned = try center(of: 3, in: preview)
        XCTAssertGreaterThan(
            max(abs(turned.x - before.x), abs(turned.y - before.y)), 5, "the view did not turn")
        XCTAssertEqual(inspection.selectedLayerID, selected)

        // ⌘ and a scroll zooms in: the label and the card move apart (C-PREV-05).
        func apart() throws -> Double {
            let a = try center(of: 3, in: preview), b = try center(of: 4, in: preview)
            return hypot(a.x - b.x, a.y - b.y)
        }
        let distance = try apart()
        preview.scrollWheel(with: try scroll(dx: 0, dy: 40, command: true))
        XCTAssertGreaterThan(try apart(), distance * 1.2)

        // A scroll moves the view by its points (C-PREV-06).
        let moving = try center(of: 4, in: preview)
        preview.scrollWheel(with: try scroll(dx: 12, dy: 0))
        let moved = try center(of: 4, in: preview)
        XCTAssertEqual(moved.x - moving.x, 12, accuracy: 0.5)
        XCTAssertEqual(moved.y, moving.y, accuracy: 0.5)

        // Showing hidden layers draws the hidden layer 5 (C-PREV-08), once the card it is in
        // is expanded (C-HIER-09). The app then asks for its screenshot, which the replayed
        // script does not hold: no check of mismatches.
        try AppWindows.expandAll()
        XCTAssertNil(preview.imagePoint(ofCenterOf: 5))
        try one("preview.showHidden", as: NSButton.self).performClick(nil)
        XCTAssertTrue(inspection.showsHiddenLayers)
        XCTAssertNotNil(preview.imagePoint(ofCenterOf: 5))
    }
}
