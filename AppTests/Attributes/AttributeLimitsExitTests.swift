import AppKit
import CutawayTestSupport
import CutawayUI
import CutawayWire
import XCTest

@testable import Cutaway

/// End to end: in the running app, a value outside an attribute's limits is not sent; the
/// field keeps it with the reason under the row, Esc puts the value back, and a value within
/// the limits goes as before (C-ATTR-13). The server plays the 1.1 `layer-details`, where
/// layer 3's opacity is 0 to 1.
final class AttributeLimitsExitTests: XCTestCase {
    private struct NotFound: Error {
        var what: String
    }

    @MainActor
    private func inspectorWindow() throws -> NSWindow {
        guard let window = AppWindows.inspectorWindows().first else {
            throw NotFound(what: "the inspector window")
        }
        return window
    }

    /// The row of the attribute with this title.
    @MainActor
    private func row(_ title: String) throws -> NSView {
        guard let content = try inspectorWindow().contentView,
              let label = AppWindows.views(in: content, identifier: "attributes.title")
              .first(where: { ($0 as? NSTextField)?.stringValue == title })
        else { throw NotFound(what: title) }
        var current = label.superview
        while let candidate = current {
            // A row of its own, or a compound one (C-ATTR-19).
            if ["attributes.row", "attributes.compound"].contains(candidate.accessibilityIdentifier()) {
                return candidate
            }
            current = candidate.superview
        }
        throw NotFound(what: "the row of \(title)")
    }

    @MainActor
    private func field(_ title: String) throws -> NSTextField {
        guard let field = AppWindows.views(in: try row(title), identifier: "attributes.editor.field")
            .first as? NSTextField
        else { throw NotFound(what: "the field of \(title)") }
        return field
    }

    /// What the row says under it, if anything.
    @MainActor
    private func note(_ title: String) throws -> String? {
        // A compound row keeps its note line, hidden while it has nothing to say (C-ATTR-19).
        (AppWindows.views(in: try row(title), identifier: "attributes.note")
            .first(where: AppWindows.isShown) as? NSTextField)?.stringValue
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () throws -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if (try? condition()) == true { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try condition()
    }

    private static func setAttributes(_ server: MockServer) async -> [SetAttribute] {
        await server.receivedFrames.compactMap { frame in
            guard case .setAttribute(let request) = frame.body else { return nil }
            return request
        }
    }

    @MainActor
    func test_C_ATTR_13_theRunningAppRefusesAValueOutsideTheLimits() async throws {
        let server = try await AppWindows.startMockServer(try Self.script())
        addTeardownBlock {
            await AppWindows.closeInspectors()
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }
        try await AppWindows.chooseApp(named: "Demo", server: server)
        let outline = try XCTUnwrap(
            AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)
        var ready = try await waitUntil { outline.numberOfRows == AppWindows.fixtureRowsAtFirst }
        XCTAssertTrue(ready)
        outline.selectRowIndexes([2], byExtendingSelection: false)
        ready = try await waitUntil { try self.field("Opacity").stringValue == "100" }
        XCTAssertTrue(ready, "layer 3's attributes, with editors")

        // 140% and Return: kept in the field, the reason under the row, nothing sent.
        let window = try inspectorWindow()
        let opacity = try field("Opacity")
        XCTAssertTrue(window.makeFirstResponder(opacity))
        var editor = try XCTUnwrap(opacity.currentEditor() as? NSTextView)
        editor.string = "140"
        editor.didChangeText()
        editor.insertNewline(nil)
        // The note under the compound row names the part's attribute (C-ATTR-19).
        XCTAssertEqual(try note("Opacity"), "Opacity: Must be between 0% and 100%.")
        XCTAssertEqual((opacity.currentEditor() as? NSTextView)?.string, "140")
        try await Task.sleep(for: .milliseconds(200))
        var sent = await Self.setAttributes(server)
        XCTAssertEqual(sent, [], "no SetAttribute for a value outside the limits")

        // Esc: the value comes back and the reason goes.
        editor = try XCTUnwrap(opacity.currentEditor() as? NSTextView)
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(opacity.stringValue, "100")
        XCTAssertNil(try note("Opacity"))

        // 50% and Return goes, and the answer comes in.
        XCTAssertTrue(window.makeFirstResponder(opacity))
        editor = try XCTUnwrap(opacity.currentEditor() as? NSTextView)
        editor.string = "50"
        editor.didChangeText()
        editor.insertNewline(nil)
        let answered = try await waitUntil {
            try self.field("Opacity").stringValue == "50"
                && !AppWindows.views(in: try self.row("Opacity"), identifier: "attributes.editor.spinner")
                .contains(where: AppWindows.isShown)
        }
        XCTAssertTrue(answered)
        sent = await Self.setAttributes(server)
        XCTAssertEqual(sent.map(\.value), [.double(0.5)])
    }

    /// The opacity of 0.5 answered, and the refresh that follows a change (C-DET-06,
    /// C-LAYOUT-01).
    private static func script() throws -> MockScript {
        var steps = try MockScript.fixtures(
            "handshake", "app-icon", "hierarchy", "layer-details", "layer-details").steps
        let groups = try Fixtures.attributes(of: 3, scenario: "layer-details").map { group in
            var group = group
            group.attributes = group.attributes.map { attribute in
                var attribute = attribute
                if attribute.id == "view.alpha" { attribute.value = .double(0.5) }
                return attribute
            }
            return group
        }
        let layer = LayerDetail(layerID: 3, status: .ok, solo: nil, group: nil, attributeGroups: groups)
        steps += [
            .expect(.setAttribute, as: 30),
            .send(Frame(requestID: 30, body: .setAttributeResult(SetAttributeResult(
                layerID: 3, attributeGroups: groups)))),
            .expect(.getSubtree, as: 31),
            .send(Frame(requestID: 31, body: .hierarchy(try Fixtures.hierarchy()))),
        ]
        steps += MockScript.layerDetailsSteps([layer], as: 131)
        steps += MockScript.layerDetailsSteps([layer], as: 231)
        return MockScript(steps: steps)
    }
}
