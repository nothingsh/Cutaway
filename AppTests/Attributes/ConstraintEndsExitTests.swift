import AppKit
import CutawayRender
import CutawayTestSupport
import CutawayUI
import CutawayWire
import XCTest

@testable import Cutaway

/// End to end: in the running app, with View › Show Constraint Ends on, selecting layer 3
/// marks layer 2, its safe area and layer 4 in the preview (C-LAYOUT-04, C-REND-07, C-PREV-18).
final class ConstraintEndsExitTests: XCTestCase {
    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    private static func middle(_ points: [CGPoint]) -> CGPoint {
        CGPoint(
            x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
            y: points.map(\.y).reduce(0, +) / CGFloat(points.count))
    }

    @MainActor
    func test_C_LAYOUT_04_theRunningAppMarksLayerThreesOtherEnds() async throws {
        // The handshake fixture speaks 0.4.
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
        XCTAssertEqual(preview.imageMarkCorners.count, 0)
        let outline = try XCTUnwrap(
            AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)
        let inspector = try XCTUnwrap(
            AppWindows.inspectorWindows().first?.windowController as? InspectorWindowController)

        // Select the label, layer 3: with the switch off, nothing is marked.
        outline.selectRowIndexes([2], byExtendingSelection: false)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(preview.imageMarkCorners.count, 0)

        // View › Show Constraint Ends, as the menu chooses it.
        let item = try XCTUnwrap(
            NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items)
                .first { $0.title == "Show Constraint Ends" })
        XCTAssertTrue(inspector.validateMenuItem(item))
        XCTAssertEqual(item.state, .off)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: inspector, from: item))
        let marked = try await waitUntil { preview.imageMarkCorners.count == 3 }
        XCTAssertTrue(marked, "\(preview.imageMarkCorners.count) marks")

        // Layer 2, its safe area, layer 4.
        let marks = preview.imageMarkCorners
        let center2 = try XCTUnwrap(preview.imagePoint(ofCenterOf: 2))
        let center4 = try XCTUnwrap(preview.imagePoint(ofCenterOf: 4))
        XCTAssertEqual(Self.middle(marks[0]).x, center2.x, accuracy: 0.01)
        XCTAssertEqual(Self.middle(marks[0]).y, center2.y, accuracy: 0.01)
        XCTAssertEqual(Self.middle(marks[2]).x, center4.x, accuracy: 0.01)
        XCTAssertEqual(Self.middle(marks[2]).y, center4.y, accuracy: 0.01)
        // The safe area is 59 points below the window's top and 34 above its bottom.
        let windowHeight = marks[0][2].y - marks[0][0].y
        XCTAssertEqual(
            (marks[1][0].y - marks[0][0].y) / windowHeight, 59.0 / 852, accuracy: 0.001)
        XCTAssertEqual(
            (marks[0][2].y - marks[1][2].y) / windowHeight, 34.0 / 852, accuracy: 0.001)

        // Layer 4's mark is drawn: the middle of its top edge is mostly the marks' colour.
        // The edge is slanted and its line smoothed, so that no pixel need be wholly covered;
        // layer 4's own grey border over its image or the guide's tint is far from purple.
        let image = try preview.snapshot()
        let edge = Self.middle([marks[2][0], marks[2][1]])
        let around = (-2...2).flatMap { dy in
            (-2...2).map { dx in image.pixel(x: Int(edge.x) + dx, y: Int(edge.y) + dy) }
        }
        func isMostlyMark(_ pixel: Pixel) -> Bool {
            let mark = preview.markPixel
            return max(
                abs(Int(pixel.red) - Int(mark.red)), abs(Int(pixel.green) - Int(mark.green)),
                abs(Int(pixel.blue) - Int(mark.blue))) <= 16
        }
        XCTAssertTrue(around.contains(where: isMostlyMark), "no \(preview.markPixel) among \(around)")

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
    }
}
