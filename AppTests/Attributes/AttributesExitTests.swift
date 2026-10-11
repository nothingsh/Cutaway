import AppKit
import CutawayTestSupport
import CutawayWire
import XCTest

/// End to end: the running app shows the attributes of layer 3 of the
/// `layer-details` fixture when that layer is selected in the list (C-ATTR-01). The test looks
/// at what the app shows, through AppKit alone.
final class AttributesExitTests: XCTestCase {
    @MainActor
    private func hierarchyOutline() -> NSOutlineView? {
        AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView
    }

    @MainActor
    private func attributesList() -> NSView? {
        AppWindows.views(identifier: "attributes.list").first
    }

    /// The group headers' names, the attributes' titles and their values, in order.
    @MainActor
    private func shown() -> (groups: [String], titles: [String], values: [String]) {
        guard let list = attributesList() else { return ([], [], []) }
        return (
            AppWindows.views(in: list, identifier: "attributes.group")
                .compactMap { $0.accessibilityLabel() },
            AppWindows.views(in: list, identifier: "attributes.title")
                .compactMap { ($0 as? NSTextField)?.stringValue },
            AppWindows.views(in: list, identifier: "attributes.value")
                .compactMap { $0.accessibilityValue() as? String })
    }

    @MainActor
    func test_C_ATTR_01_theRunningAppShowsTheSelectedLayersAttributes() async throws {
        // The screenshots and the attributes each ask once; both get the same answer, so their
        // order does not matter.
        let script = try MockScript.fixtures(
            "handshake", "app-icon", "hierarchy", "layer-details", "layer-details")
        let server = try await AppWindows.startMockServer(script)
        addTeardownBlock {
            // Leave the app as it was for the other tests, even when this one failed.
            await AppWindows.closeInspectors()
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }
        try await AppWindows.chooseApp(named: "Demo", server: server)

        var deadline = Date().addingTimeInterval(5)
        while hierarchyOutline()?.numberOfRows != AppWindows.fixtureRowsAtFirst, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let outline = try XCTUnwrap(hierarchyOutline(), "the app did not open the inspection")
        XCTAssertEqual(
            outline.numberOfRows, AppWindows.fixtureRowsAtFirst, "the layers did not arrive")
        let message = try XCTUnwrap(
            AppWindows.views(identifier: "attributes.message").first as? NSTextField)
        XCTAssertTrue(AppWindows.isShown(message))
        XCTAssertEqual(message.stringValue, "No Selection")

        // Select the label, layer 3, as a click on its row does.
        XCTAssertEqual(
            (outline.view(atColumn: 0, row: 2, makeIfNecessary: true).flatMap {
                AppWindows.views(in: $0, identifier: "hierarchy.title").first as? NSTextField
            })?.stringValue,
            "UILabel")
        outline.selectRowIndexes([2], byExtendingSelection: false)

        deadline = Date().addingTimeInterval(5)
        while shown().titles.count != 12, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let list = try XCTUnwrap(attributesList())
        XCTAssertTrue(AppWindows.isShown(list))
        XCTAssertFalse(AppWindows.isShown(message))
        let (groups, titles, values) = shown()
        XCTAssertEqual(groups, ["Layer", "Label", "View"], "three groups")
        XCTAssertEqual(titles, [
            "Frame", "Position", "Shadow Offset", "Opacity", "Hidden", "Background Color",
            "Border Color", "Transform", "Text", "Number Of Lines", "Text Alignment",
            "Layout Margins",
        ])
        // The server speaks 1.0, so every attribute but the frame has an editor (C-ATTR-04); only
        // the frame is shown as text. The read-only panel's values have the package's tests
        // (AttributesViewTests, C-ATTR-02).
        XCTAssertEqual(values, ["96.5, 108, 200, 24"])
        XCTAssertEqual(AppWindows.views(in: list, identifier: "attributes.editor").count, 11)

        // One connection; one of the two GetLayerDetails asked for layer 3's attributes alone.
        let requests = await server.receivedFrames.compactMap { frame -> GetLayerDetails? in
            guard case .getLayerDetails(let request) = frame.body else { return nil }
            return request
        }
        XCTAssertEqual(requests.count, 2)
        XCTAssertTrue(requests.contains { $0.requests == [LayerDetailRequest(
            layerID: 3, wantSolo: false, wantGroup: false, wantAttributes: true,
            wantConstraints: true)] })
        let connections = await server.connectionCount
        XCTAssertEqual(connections, 1)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
    }
}
