import AppKit
import CutawayRender
import CutawayTestSupport
import CutawayUI
import CutawayWire
import XCTest

@testable import Cutaway

/// End to end: in the running app, with layer 3 selected, holding ⌥ over
/// layer 8 draws 26.5 and 68 (C-PREV-10, C-REND-08). In 3D, holding ⌥ over
/// layer 2 draws 96.5, 96.5, 108 and 720 (C-PREV-14).
final class MeasurementExitTests: XCTestCase {
    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @MainActor
    func test_C_PREV_10_theRunningAppMeasuresLayerEightAgainstTheSelectedLayerThree()
        async throws
    {
        // Selecting layer 3 asks for its attributes (and, at 0.4, its constraints).
        var steps = try MockScript.fixtures(
            "handshake", "app-icon", "hierarchy", "layer-details").steps
        steps += MockScript.layerDetailsSteps([try Fixtures.panelDetail(of: 3)], as: 60)
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
        let outline = try XCTUnwrap(
            AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)

        // Select the label, layer 3, then hold ⌥ over layer 8.
        outline.selectRowIndexes([2], byExtendingSelection: false)
        let point = try XCTUnwrap(preview.imagePoint(ofCenterOf: 8))
        let scale = preview.window?.backingScaleFactor ?? 1
        let location = NSPoint(x: point.x / scale, y: preview.bounds.height - point.y / scale)
        let moved = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .mouseMoved, location: preview.convert(location, to: nil),
                modifierFlags: [.option], timestamp: 0,
                windowNumber: preview.window?.windowNumber ?? 0, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1))
        preview.mouseMoved(with: moved)
        let measured = try await waitUntil { preview.imageDistances.count == 2 }
        XCTAssertTrue(measured, "\(preview.imageDistances.count) distances")
        XCTAssertEqual(preview.imageDistances.map(\.value), [26.5, 68])
        let labels = AppWindows.views(identifier: "preview.distanceLabel")
            .compactMap { $0.accessibilityLabel() }
        XCTAssertEqual(labels, ["26.5", "68"])

        // The line across is drawn: its middle is the measuring colour.
        let image = try preview.snapshot()
        let across = preview.imageDistances[0]
        let middle = CGPoint(x: (across.from.x + across.to.x) / 2, y: (across.from.y + across.to.y) / 2)
        let around = (-2...2).flatMap { dy in
            (-2...2).map { dx in image.pixel(x: Int(middle.x) + dx, y: Int(middle.y) + dy) }
        }
        XCTAssertTrue(
            around.contains { AppWindows.isClose($0, preview.measurePixel) },
            "no \(preview.measurePixel) among \(around)")

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
    }

    @MainActor
    func test_C_PREV_14_theRunningAppMeasuresLayerTwoAgainstTheSelectedLayerThreeIn3D()
        async throws
    {
        var steps = try MockScript.fixtures(
            "handshake", "app-icon", "hierarchy", "layer-details").steps
        steps += MockScript.layerDetailsSteps([try Fixtures.panelDetail(of: 3)], as: 60)
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
        let outline = try XCTUnwrap(
            AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)

        // 3D, as a click on the switch does, and the turn over to it.
        let control = try XCTUnwrap(
            AppWindows.views(identifier: "inspection.mode").first as? NSSegmentedControl)
        control.selectedSegment = 1
        control.sendAction(control.action, to: control.target)
        _ = try await AppWindows.samples(whileInTransition: preview) {}

        // Select the label, layer 3, then hold ⌥ over layer 2 near its bottom left corner,
        // where no other layer covers it.
        outline.selectRowIndexes([2], byExtendingSelection: false)
        let corner = try XCTUnwrap(preview.imageCorners(of: 2))[2]
        let center = try XCTUnwrap(preview.imagePoint(ofCenterOf: 2))
        let point = CGPoint(
            x: corner.x + (center.x - corner.x) * 0.1, y: corner.y + (center.y - corner.y) * 0.1)
        let scale = preview.window?.backingScaleFactor ?? 1
        let location = NSPoint(x: point.x / scale, y: preview.bounds.height - point.y / scale)
        let moved = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .mouseMoved, location: preview.convert(location, to: nil),
                modifierFlags: [.option], timestamp: 0,
                windowNumber: preview.window?.windowNumber ?? 0, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1))
        preview.mouseMoved(with: moved)
        let measured = try await waitUntil { preview.imageDistances.count == 4 }
        XCTAssertTrue(measured, "\(preview.imageDistances.count) distances")
        XCTAssertEqual(preview.imageDistances.map(\.value), [96.5, 96.5, 108, 720])
        let labels = AppWindows.views(identifier: "preview.distanceLabel")
            .compactMap { $0.accessibilityLabel() }
        XCTAssertEqual(labels, ["96.5", "96.5", "108", "720"])

        // The line down from layer 3 to the bottom is drawn in the measuring colour. In 3D a
        // line is not put on whole pixels (Preview.metal): at a density of 1 its one pixel of
        // width falls across two, each a mix of the measuring colour and what is behind it.
        // Across the line the mixes add up to its width, one point.
        let image = try preview.snapshot()
        let down = preview.imageDistances[3]
        let middle = CGPoint(x: (down.from.x + down.to.x) / 2, y: (down.from.y + down.to.y) / 2)
        let across = (-3...3).map { image.pixel(x: Int(middle.x) + $0, y: Int(middle.y)) }
        let behind = across[0]
        XCTAssertTrue(AppWindows.isClose(behind, across[6]), "not one colour behind: \(across)")
        let shares = across.map { AppWindows.share(of: preview.measurePixel, in: $0, over: behind) }
        XCTAssertFalse(shares.contains(nil), "not \(preview.measurePixel) over \(behind): \(across)")
        XCTAssertEqual(
            shares.compactMap { $0 }.reduce(0, +), Double(scale), accuracy: 0.15, "\(across)")

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
    }
}
