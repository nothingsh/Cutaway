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

    /// The requests for attributes the server received.
    private static func attributeRequests(_ server: MockServer) async -> [LayerDetailRequest] {
        await server.receivedFrames.compactMap { frame in
            guard case .getLayerDetails(let request) = frame.body,
                  let first = request.requests.first, first.wantAttributes
            else { return nil }
            return first
        }
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
            .compactMap { ($0 as? NSTextView)?.string }
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
    func test_C_LAYOUT_03_theRunningAppListsLayerThreesConstraintsAndGoesToTheOtherEnd()
        async throws
    {
        var steps = try Self.opening()
        steps += MockScript.layerDetailsSteps([try Fixtures.panelDetail(of: 3)], as: 60)
        steps += MockScript.layerDetailsSteps([try Fixtures.panelDetail(of: 4)], as: 61)
        let server = try await AppWindows.startMockServer(MockScript(steps: steps))
        addTeardownBlock {
            await AppWindows.closeInspectors()
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }
        let outline = try await open(server)

        // Select the label, layer 3.
        outline.selectRowIndexes([2], byExtendingSelection: false)
        var listed = try await waitUntil { self.equations().count == 4 }
        XCTAssertTrue(listed, "layer 3's constraints: \(equations())")
        XCTAssertEqual(equations(), [
            "self.centerX = UIView.centerX",
            "self.top = Safe Area.top + 49",
            "self.width = 240",
            "CardView.top = self.bottom + 78",
        ])
        let content = try XCTUnwrap(inspectorContent())
        XCTAssertTrue(AppWindows.views(in: content, identifier: "constraints.header")
            .contains(where: AppWindows.isShown))

        // Click CardView in constraint 4, as the mouse does.
        let fourth = try XCTUnwrap(
            AppWindows.views(in: content, identifier: "constraints.equation").last as? NSTextView)
        let storage = try XCTUnwrap(fourth.textStorage)
        var link: (value: Any, at: Int)?
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) {
            value, range, stop in
            guard let value else { return }
            link = (value, range.location)
            stop.pointee = true
        }
        let card = try XCTUnwrap(link)
        XCTAssertEqual((fourth.string as NSString).substring(from: card.at).prefix(8), "CardView")
        fourth.clicked(onLink: card.value, at: card.at)

        // Layer 4 is selected, in the list too, and its constraints include constraint 4.
        listed = try await waitUntil {
            outline.selectedRow == 3 && self.equations().count == 4
                && self.equations().first == "self.top = UILabel.bottom + 78"
        }
        XCTAssertTrue(listed, "row \(outline.selectedRow): \(equations())")
        let subtitle = AppWindows.views(identifier: "attributes.header.subtitle")
            .compactMap { $0 as? NSTextField }.first?.stringValue
        XCTAssertEqual(subtitle, "CALayer · ID 4")

        let requests = await Self.attributeRequests(server)
        XCTAssertEqual(requests.map(\.layerID), [3, 4])
        XCTAssertTrue(requests.allSatisfy(\.wantConstraints))
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
    }

    @MainActor
    func test_C_LAYOUT_02_theRunningAppListsLayerThreesConstraints() async throws {
        var steps = try Self.opening()
        steps += MockScript.layerDetailsSteps([try Fixtures.panelDetail(of: 3)], as: 60)
        let server = try await AppWindows.startMockServer(MockScript(steps: steps))
        addTeardownBlock {
            await AppWindows.closeInspectors()
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }
        let outline = try await open(server)

        outline.selectRowIndexes([2], byExtendingSelection: false)
        let listed = try await waitUntil { self.equations().count == 4 }
        XCTAssertTrue(listed)
        let content = try XCTUnwrap(inspectorContent())
        // The third is not in effect and says so; the attributes are listed above.
        XCTAssertEqual(
            AppWindows.views(in: content, identifier: "constraints.notInEffect").count, 1)
        XCTAssertEqual(
            AppWindows.views(in: content, identifier: "constraints.detail")
                .compactMap { ($0 as? NSTextField)?.stringValue },
            ["Priority 250 · titleLabel.preferredWidth"])
        XCTAssertEqual(AppWindows.views(in: content, identifier: "attributes.title").count, 12)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
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

        // Layer 9, the last row; its four constraints are UIKit's, folded into one row.
        outline.selectRowIndexes([outline.numberOfRows - 1], byExtendingSelection: false)
        let listed = try await waitUntil { self.equations().count == 4 }
        XCTAssertTrue(listed, "layer 9's constraints: \(equations())")
        let subtitle = AppWindows.views(identifier: "attributes.header.subtitle")
            .compactMap { $0 as? NSTextField }.first?.stringValue
        XCTAssertEqual(subtitle, "CALayer · ID 9")
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
            "UIView.width = self.maxX + 93",
            "self.width = 0",
            "self.minY = 700",
            "self.height = 0",
        ])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
    }
}
