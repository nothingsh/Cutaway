import AppKit
import CutawayTestSupport
import CutawayUI
import CutawayWire
import XCTest

@testable import Cutaway

/// End to end: in the running app, attributes of the `set-attribute`
/// scenario are changed from the panel and the panel shows the answers; the failures of
/// `set-attribute-rejected` are said in the rows (C-ATTR-04 to C-ATTR-06).
final class AttributeEditingExitTests: XCTestCase {
    /// Something the test looks for is not there (yet). Thrown rather than recorded: the
    /// lookups run inside waits, where `XCTUnwrap` would record every early miss as a failure.
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

    /// The row of the attribute with this title: the nearest view above its title that is a
    /// row.
    @MainActor
    private func row(_ title: String) throws -> NSView {
        guard let content = try inspectorWindow().contentView,
              let label = AppWindows.views(in: content, identifier: "attributes.title")
              .first(where: { ($0 as? NSTextField)?.stringValue == title })
        else { throw NotFound(what: title) }
        var current = label.superview
        while let candidate = current {
            if candidate.accessibilityIdentifier() == "attributes.row" { return candidate }
            current = candidate.superview
        }
        throw NotFound(what: "the row of \(title)")
    }

    @MainActor
    private func one<View: NSView>(
        _ identifier: String, in row: NSView, as type: View.Type
    ) throws -> View {
        guard let view = AppWindows.views(in: row, identifier: identifier).first as? View else {
            throw NotFound(what: identifier)
        }
        return view
    }

    /// What typing does to a field that has the focus: its text changes and it hears of it.
    @MainActor
    private static func typeKeys(_ text: String, into field: NSTextField) {
        guard let editor = field.currentEditor() as? NSTextView else { return }
        editor.string = text
        editor.didChangeText()
    }

    /// Types into a field of a row and leaves it, as Return does.
    @MainActor
    private func type(_ text: String, into title: String, field index: Int = 0) throws {
        let fields = AppWindows.views(in: try row(title), identifier: "attributes.editor.field")
            .compactMap { $0 as? NSTextField }
        guard let field = fields.dropFirst(index).first else { throw NotFound(what: title) }
        let window = try inspectorWindow()
        XCTAssertTrue(window.makeFirstResponder(field), title)
        Self.typeKeys(text, into: field)
        window.makeFirstResponder(nil)
    }

    /// The value of a row's first field, or of its value text when it has no editor.
    @MainActor
    private func fieldText(_ title: String) throws -> String? {
        (AppWindows.views(in: try row(title), identifier: "attributes.editor.field").first
            as? NSTextField)?.stringValue
    }

    /// Why the row's last change failed: the tooltip of the warning sign it shows, if any.
    @MainActor
    private func failure(_ title: String) throws -> String? {
        AppWindows.views(in: try row(title), identifier: "attributes.editor.failure")
            .first(where: AppWindows.isShown)?.toolTip
    }

    /// Types a value the app does not take into a row: once the app's answer has come in, the
    /// row shows `value` again, without a warning sign.
    @MainActor
    private func expectRejected(_ text: String, into title: String, backTo value: String) async throws {
        try type(text, into: title)
        // Leaving the field sends at once, and the row shows the change on its way.
        XCTAssertTrue(try sending(title), title)
        let back = try await waitUntil { try !self.sending(title) && self.fieldText(title) == value }
        XCTAssertTrue(back, title)
        XCTAssertNil(try failure(title), title)
    }

    /// Whether a row shows a change on its way.
    @MainActor
    private func sending(_ title: String) throws -> Bool {
        AppWindows.views(in: try row(title), identifier: "attributes.editor.spinner")
            .contains(where: AppWindows.isShown)
    }

    /// Waits until the refresh after the `subtrees`th change has asked for its screenshots
    /// (`details` requests for screenshots or attributes so far), and a moment more for their
    /// end to come in: the next change must not overtake it.
    @MainActor
    private func waitForRefresh(
        _ subtrees: Int, details: Int, of server: MockServer
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        func count(_ kind: MessageKind) async -> Int {
            await server.receivedFrames.filter { MessageKind($0.body) == kind }.count
        }
        func done() async -> Bool {
            let refreshes = await count(.getSubtree)
            let requests = await count(.getLayerDetails)
            return refreshes >= subtrees && requests >= details
        }
        while await !done(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let asked = await done()
        XCTAssertTrue(asked, "the refresh after change \(subtrees)")
        try await Task.sleep(for: .milliseconds(300))
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

    @MainActor
    func test_C_ATTR_06_theRunningAppChangesAttributesFromThePanel() async throws {
        let server = try await AppWindows.startMockServer(try Self.editingScript())
        addTeardownBlock {
            await AppWindows.closeInspectors()
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }
        try await AppWindows.chooseApp(named: "Demo", server: server)
        let outline = try XCTUnwrap(
            AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)
        // Layers 3 and 4 are in rows 2 and 3 as the list first shows the fixture.
        var loaded = try await waitUntil { outline.numberOfRows == AppWindows.fixtureRowsAtFirst }
        XCTAssertTrue(loaded)

        // Layer 3: its frame is read-only, its text and alignment are not (C-ATTR-04).
        outline.selectRowIndexes([2], byExtendingSelection: false)
        loaded = try await waitUntil { try self.fieldText("Text") == "Hello" }
        XCTAssertTrue(loaded, "layer 3's attributes, with editors")
        XCTAssertTrue(AppWindows.views(in: try row("Frame"), identifier: "attributes.editor").isEmpty)
        try type("Welcome back", into: "Text")
        var answered = try await waitUntil {
            try self.fieldText("Text") == "Welcome back"
                && !AppWindows.views(in: try self.row("Text"), identifier: "attributes.editor.spinner")
                .contains(where: AppWindows.isShown)
        }
        XCTAssertTrue(answered)
        try await waitForRefresh(1, details: 4, of: server)
        let alignment = try one("attributes.editor.popup", in: try row("Text Alignment"), as: NSPopUpButton.self)
        alignment.selectItem(at: 2)
        XCTAssertTrue(alignment.sendAction(alignment.action, to: alignment.target))
        answered = try await waitUntil { alignment.titleOfSelectedItem == "right" }
        XCTAssertTrue(answered)
        try await waitForRefresh(2, details: 6, of: server)

        // Layer 4: a colour where there was none, the alpha (the opacity follows).
        outline.selectRowIndexes([3], byExtendingSelection: false)
        loaded = try await waitUntil { try self.fieldText("Alpha") == "1" }
        XCTAssertTrue(loaded, "layer 4's attributes")
        let hex = try one("attributes.editor.hex", in: try row("Background Color"), as: NSTextField.self)
        XCTAssertEqual(hex.stringValue, "")
        let window = try inspectorWindow()
        XCTAssertTrue(window.makeFirstResponder(hex))
        Self.typeKeys("#3366CC", into: hex)
        window.makeFirstResponder(nil)
        answered = try await waitUntil { hex.stringValue == "#3366CC" }
        XCTAssertTrue(answered)
        try await waitForRefresh(3, details: 9, of: server)
        try type("0.5", into: "Alpha")
        answered = try await waitUntil { try self.fieldText("Opacity") == "0.5" }
        XCTAssertTrue(answered, "the opacity read back with the alpha")
        try await waitForRefresh(4, details: 11, of: server)

        // Three failures; the value from before stays. One the attribute cannot take is said
        // by a warning sign; a value the app does not take just goes back, without one.
        try type("1", into: "Corner Radius")
        var said = try await waitUntil { try self.failure("Corner Radius") == "This attribute cannot be changed." }
        XCTAssertTrue(said)
        XCTAssertEqual(try fieldText("Corner Radius"), "12")
        try await expectRejected("0.4", into: "Opacity", backTo: "0.5")
        try await expectRejected("0.4", into: "Alpha", backTo: "0.5")

        // The layer is gone: the panel says so (C-ATTR-06, as C-DET-03).
        try type("2", into: "Corner Radius")
        said = try await waitUntil {
            (AppWindows.views(identifier: "attributes.message").first as? NSTextField)?
                .stringValue == "Layer Not Found"
        }
        XCTAssertTrue(said)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
    }

    /// The changes the test makes, each answered, then the failures.
    private static func editingScript() throws -> MockScript {
        let changes = try MockScript.fixtures("set-attribute").steps
        let rejections = try MockScript.fixtures("set-attribute-rejected").steps
        var steps = try MockScript.fixtures(
            "handshake", "app-icon", "hierarchy", "layer-details", "layer-details").steps
        // Each change that succeeds takes the window again and asks for the changed layer's
        // screenshot (C-DET-06), and, the layer being selected, its attributes and constraints
        // again (C-LAYOUT-01). The two go in either order; both
        // are answered with the layer as the change left it.
        let tree = try Fixtures.hierarchy()
        let results = try Fixtures.setAttributeResults()
        func refresh(_ id: UInt32, after result: SetAttributeResult) -> [MockScript.Step] {
            let layer = LayerDetail(
                layerID: result.layerID, status: .ok, solo: nil, group: nil,
                attributeGroups: result.attributeGroups)
            return [
                .expect(.getSubtree, as: id),
                .send(Frame(requestID: id, body: .hierarchy(tree))),
            ]
                + MockScript.layerDetailsSteps([layer], as: id + 100)
                + MockScript.layerDetailsSteps([layer], as: id + 200)
        }
        func change(_ index: Int) -> [MockScript.Step] {
            Array(changes[(index * 2)..<(index * 2 + 2)])
                + refresh(UInt32(80 + index), after: results[index])
        }
        steps += change(0) + change(1)  // layer 3: the text, the alignment
        steps += MockScript.layerDetailsSteps(
            [LayerDetail(
                layerID: 4, status: .ok, solo: nil, group: nil,
                attributeGroups: try Fixtures.layerFourBeforeEditing())],
            as: 60)
        steps += change(2) + change(3)  // layer 4: a colour, the alpha
        steps += rejections.dropFirst(2)  // not editable, rejected, rejected
        steps += rejections.prefix(2)  // the layer is gone
        return MockScript(steps: steps)
    }
}
