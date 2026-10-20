import AppKit
import CutawayRender
import CutawayTestSupport
import CutawayUI
import CutawayWire
import XCTest

@testable import Cutaway

/// End to end: in the running app, selecting layer 3 lists its 4
/// constraints; clicking the other end of constraint 4 goes to layer 4 (C-LAYOUT-02,
/// C-LAYOUT-03). Layer 9's constraints from UIKit read as UIKit writes them
/// (C-LAYOUT-05). A server below 0.4 is a different major version from the app's since
/// protocol 1.0, so the app never meets one; the package's tests cover that case (C-LAYOUT-01).
final class ConstraintsExitTests: XCTestCase {
    /// The handshake, the icon, the hierarchy and the first round of screenshots.
    private static func opening() throws -> [MockScript.Step] {
        try MockScript.fixtures("handshake", "app-icon", "hierarchy", "layer-details").steps
    }

    @MainActor
    private func inspectorContent() -> NSView? {
        AppWindows.inspectorWindows().first?.contentView
    }

    /// The equations of the Constraints section, in order; empty when there is none.
    @MainActor
    private func equations() -> [String] {
        guard let content = inspectorContent() else { return [] }
        return AppWindows.views(in: content, identifier: "constraints.equation")
            // The equation as words, its chips by their names (C-LAYOUT-06).
            .compactMap { ($0 as? NSTextView)?.accessibilityValue() as? String }
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    /// Opens the app's inspection and waits for the first screenshots. Returns the list.
    @MainActor
    private func open(_ server: MockServer) async throws -> NSOutlineView {
        try await AppWindows.chooseApp(named: "Demo", server: server)
        let preview = try XCTUnwrap(
            AppWindows.views(identifier: PreviewView.identifier).first as? PreviewView)
        let arrived = try await AppWindows.waitFor(
            Pixel(blue: 0, green: 255, red: 0, alpha: 255), at: 4, in: preview)
        XCTAssertTrue(arrived, "the first round of screenshots")
        let outline = try XCTUnwrap(
            AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)
        XCTAssertEqual(outline.numberOfRows, AppWindows.fixtureRowsAtFirst)
        return outline
    }

    @MainActor
    func test_C_LAYOUT_05_theRunningAppListsLayerNinesAutoresizingConstraints() async throws {
        var steps = try Self.opening()
        steps += MockScript.layerDetailsSteps([try Fixtures.panelDetail(of: 9)], as: 60)
        let server = try await AppWindows.startMockServer(MockScript(steps: steps))
        addTeardownBlock {
            await AppWindows.closeInspectors()
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }
        let outline = try await open(server)

        // Layer 9, the row before layer 13's; its four constraints are UIKit's, folded into one
        // row.
        outline.selectRowIndexes([outline.numberOfRows - 2], byExtendingSelection: false)
        let listed = try await waitUntil { self.equations().count == 4 }
        XCTAssertTrue(listed, "layer 9's constraints: \(equations())")
        // Nothing holds it: the header's second line is its size alone (C-HIER-07, C-ATTR-18).
        let subtitle = try XCTUnwrap(AppWindows.views(identifier: "attributes.header.subtitle")
            .compactMap { $0 as? NSTextField }.first)
        XCTAssertTrue(AppWindows.isShown(subtitle))
        XCTAssertEqual(subtitle.stringValue, "0 × 0")
        let content = try XCTUnwrap(inspectorContent())
        let fold = try XCTUnwrap(
            AppWindows.views(in: content, identifier: "constraints.generated").first as? NSButton)
        XCTAssertTrue(AppWindows.isShown(fold))
        XCTAssertEqual(fold.accessibilityLabel(), "4 from UIKit")
        let rows = AppWindows.views(in: content, identifier: "constraints.equation")
        XCTAssertEqual(rows.count, 4)
        XCTAssertFalse(rows.contains(where: AppWindows.isShown), "folded by default")

        fold.performClick(nil)
        XCTAssertTrue(rows.allSatisfy(AppWindows.isShown))
        XCTAssertEqual(equations(), [
            "HomeViewController.width = self.maxX + 93",
            "self.width = 0",
            "self.minY = 700",
            "self.height = 0",
        ])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
    }
}
