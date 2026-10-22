import AppKit
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// Limits in the attribute panel (C-ATTR-13), and typed text that is not a number it can send
/// (C-ATTR-05): what is refused stays in its field with the reason under the row, what is on
/// a bound goes, a drag stops on the bound, and a value the app set outside its limits is red.
/// The panel tests play the 1.1 `layer-details`: opacity 0 to 1, a font size above 0, a
/// number of lines and a bounds' width and height at least 0.
extension AttributeEditingViewTests {
    // MARK: - Helpers

    /// The `SetAttribute` values the server received, in order.
    private static func sentValues(_ server: MockServer) async -> [AttributeValue?] {
        await server.receivedFrames.compactMap { frame in
            guard case .setAttribute(let request) = frame.body else { return nil }
            return .some(request.value)
        }
    }

    /// Layer 3's attributes, as `layer-details` gives them.
    private static func layerThree() throws -> [AttributeGroup] {
        try Fixtures.attributes(of: 3, scenario: "layer-details")
    }

    private static func replacing(
        _ id: String, with value: AttributeValue?, in groups: [AttributeGroup]
    ) -> [AttributeGroup] {
        groups.map { group in
            var group = group
            group.attributes = group.attributes.map { attribute in
                var attribute = attribute
                if attribute.id == id { attribute.value = value }
                return attribute
            }
            return group
        }
    }

    private static func bounds(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> AttributeValue {
        .rect(Rect(origin: Point(x: x, y: y), size: Size(width: width, height: height)))
    }

    @MainActor
    private func numbers(of row: AttributeRowView) throws -> [NumberFieldView] {
        AppListViewTests.descendants(of: try XCTUnwrap(row.editor)) { $0 is NumberFieldView }
            .compactMap { $0 as? NumberFieldView }
    }

    /// Focuses a field, types into it and presses Return, as the keyboard does.
    @MainActor
    private func enter(_ text: String, into field: AttributeEditField, in window: NSWindow) {
        if field.currentEditor() == nil { XCTAssertTrue(window.makeFirstResponder(field)) }
        AttributeEditorTests.type(text, into: field)
        (field.currentEditor() as? NSTextView)?.insertNewline(nil)
    }

    @MainActor
    private func pressEscape(in field: AttributeEditField) throws {
        let text = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertTrue(field.control(field, textView: text, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
    }

    /// What reaches the server is sent from a task: give it a moment.
    @MainActor
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    // MARK: - Return on a value outside

    @MainActor
    func test_C_ATTR_13_returnOnAValueOutsideKeepsTheFieldEditing() async throws {
        let (model, session, server) = try await inspection([])
        let (controller, window) = panel(for: model)
        let opacity = try row("Opacity", in: controller)
        let number = try XCTUnwrap(try numbers(of: opacity).first)

        enter("140", into: number.field, in: window)
        XCTAssertNotNil(number.field.currentEditor(), "the field stays in editing")
        XCTAssertEqual((number.field.currentEditor() as? NSTextView)?.string, "140", "as typed")
        XCTAssertTrue(number.isShowingRefusal, "a red outline")
        XCTAssertEqual(opacity.noteText, "Must be between 0% and 100%.")
        XCTAssertTrue(opacity.noteIsError)

        try pressEscape(in: number.field)
        XCTAssertEqual(number.field.stringValue, "100")
        XCTAssertNil(opacity.noteText)
        XCTAssertFalse(number.isShowingRefusal)
        try await settle()
        let sent = await Self.sentValues(server)
        XCTAssertEqual(sent, [])

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_13_aRectsWidthOutsideIsRefusedAndItsXIsSent() async throws {
        let (model, session, server) = try await inspection(
            Self.resultSteps(try Self.layerThree(), as: 30))
        let (controller, window) = panel(for: model)
        let bounds = try row("Bounds", in: controller)
        let fields = try numbers(of: bounds)
        XCTAssertEqual(fields.count, 4)

        enter("-20", into: fields[2].field, in: window)
        XCTAssertEqual(bounds.noteText, "Width must be 0 or more.")
        XCTAssertTrue(fields[2].isShowingRefusal)
        try pressEscape(in: fields[2].field)
        XCTAssertNil(bounds.noteText)

        enter("-20", into: fields[0].field, in: window)
        let answered = await Wait.until { @MainActor in model.attributes.edits.isEmpty }
        XCTAssertTrue(answered)
        try await settle()
        let sent = await Self.sentValues(server)
        XCTAssertEqual(sent, [Self.bounds(-20, 0, 200, 24)], "x is free")

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_13_valuesOnTheBoundAreSent() async throws {
        let layerThree = try Self.layerThree()
        let (model, session, server) = try await inspection(
            Self.resultSteps(Self.replacing("view.alpha", with: .double(0), in: layerThree), as: 30))
        let (controller, window) = panel(for: model)
        let opacity = try row("Opacity", in: controller)
        let number = try XCTUnwrap(try numbers(of: opacity).first)

        enter("0", into: number.field, in: window)
        XCTAssertNil(opacity.noteText)
        let answered = await Wait.until { @MainActor in model.attributes.edits.isEmpty }
        XCTAssertTrue(answered)
        try await settle()
        let sent = await Self.sentValues(server)
        XCTAssertEqual(sent, [.double(0)])

        // The other end, a component's bound and an open bound's nearest number, in an editor
        // of their own: one change in the panel asks for the subtree again.
        var half = try XCTUnwrap(layerThree.flatMap(\.attributes).first { $0.id == "view.alpha" })
        half.value = .double(0.5)
        let (top, tops) = makeEditor(half)
        XCTAssertEqual(numbers(in: top)[0].commit("100"), .accepted)
        let bounds = try XCTUnwrap(layerThree.flatMap(\.attributes).first { $0.id == "layer.bounds" })
        let (rect, rects) = makeEditor(bounds)
        XCTAssertEqual(numbers(in: rect)[2].commit("0"), .accepted)
        let fontSize = try XCTUnwrap(layerThree.flatMap(\.attributes).first { $0.id == "label.fontSize" })
        let (size, sizes) = makeEditor(fontSize)
        XCTAssertEqual(numbers(in: size)[0].commit("0.001"), .accepted)
        XCTAssertEqual(tops(), [.double(1)])
        XCTAssertEqual(rects(), [Self.bounds(0, 0, 0, 24)])
        XCTAssertEqual(sizes(), [.double(0.001)])

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_13_eachKindOfBoundHasItsMessage() async throws {
        let (model, session, server) = try await inspection([])
        let (controller, window) = panel(for: model)
        let fontSize = try row("Font Size", in: controller)
        let lines = try row("Lines", in: controller)

        let size = try XCTUnwrap(try numbers(of: fontSize).first)
        enter("0", into: size.field, in: window)
        XCTAssertEqual(fontSize.noteText, "Must be more than 0.")
        try pressEscape(in: size.field)
        let count = try XCTUnwrap(try numbers(of: lines).first)
        enter("-1", into: count.field, in: window)
        XCTAssertEqual(lines.noteText, "Must be 0 or more.")
        try pressEscape(in: count.field)
        try await settle()
        let sent = await Self.sentValues(server)
        XCTAssertEqual(sent, [])

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_05_textThatIsNotANumberSaysSo() async throws {
        let (model, session, server) = try await inspection([])
        let (controller, window) = panel(for: model)
        let opacity = try row("Opacity", in: controller)
        let number = try XCTUnwrap(try numbers(of: opacity).first)

        enter("abc", into: number.field, in: window)
        XCTAssertEqual(opacity.noteText, "Enter a number.")
        XCTAssertTrue(number.isShowingRefusal)
        // Leaving puts the number back, without a word.
        window.makeFirstResponder(nil)
        XCTAssertEqual(number.field.stringValue, "100")
        XCTAssertNil(opacity.noteText)

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    // MARK: - Esc and leaving

    @MainActor
    func test_C_ATTR_13_escapeOrLeavingPutsTheValueBackAndTheMessageGoes() async throws {
        let (model, session, server) = try await inspection([])
        let (controller, window) = panel(for: model)
        let opacity = try row("Opacity", in: controller)
        let number = try XCTUnwrap(try numbers(of: opacity).first)

        // Tab.
        enter("140", into: number.field, in: window)
        XCTAssertNotNil(opacity.noteText)
        (number.field.currentEditor() as? NSTextView)?.insertTab(nil)
        XCTAssertEqual(number.field.stringValue, "100")
        XCTAssertNil(opacity.noteText)
        XCTAssertFalse(number.isShowingRefusal)

        // A click elsewhere.
        window.makeFirstResponder(nil)
        enter("140", into: number.field, in: window)
        XCTAssertNotNil(opacity.noteText)
        window.makeFirstResponder(nil)
        XCTAssertEqual(number.field.stringValue, "100")
        XCTAssertNil(opacity.noteText)

        // Leaving with a value outside without Return: put back, nothing said.
        XCTAssertTrue(window.makeFirstResponder(number.field))
        AttributeEditorTests.type("700", into: number.field)
        window.makeFirstResponder(nil)
        XCTAssertEqual(number.field.stringValue, "100")
        XCTAssertNil(opacity.noteText)

        try await settle()
        let sent = await Self.sentValues(server)
        XCTAssertEqual(sent, [])

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ATTR_13_leavingWithAGoodValueSendsIt() async throws {
        let (model, session, server) = try await inspection(
            Self.resultSteps(
                Self.replacing("view.alpha", with: .double(0.5), in: try Self.layerThree()), as: 30))
        let (controller, window) = panel(for: model)
        let opacity = try row("Opacity", in: controller)
        let number = try XCTUnwrap(try numbers(of: opacity).first)

        enter("140", into: number.field, in: window)
        AttributeEditorTests.type("50", into: number.field)
        XCTAssertNotNil(opacity.noteText, "the reason stays while typing on")
        window.makeFirstResponder(nil)
        XCTAssertNil(opacity.noteText)
        let answered = await Wait.until { @MainActor in model.attributes.edits.isEmpty }
        XCTAssertTrue(answered)
        try await settle()
        let sent = await Self.sentValues(server)
        XCTAssertEqual(sent, [.double(0.5)])

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }

    // MARK: - Editors of their own

    /// An editor of its own, recording the values it sends.
    @MainActor
    private func makeEditor(_ attribute: Attribute) -> (AttributeEditorView, () -> [AttributeValue?]) {
        final class Recorder { var sent: [AttributeValue?] = [] }
        let recorder = Recorder()
        let editor = AttributeEditorView(
            attribute: attribute, onSet: { value, _ in recorder.sent.append(value) }, onFinish: {})
        return (editor, { recorder.sent })
    }

    @MainActor
    private func inWindow(_ view: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 120), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentView = view
        window.layoutIfNeeded()
        return window
    }

    @MainActor
    private func numbers(in editor: AttributeEditorView) -> [NumberFieldView] {
        AppListViewTests.descendants(of: editor) { $0 is NumberFieldView }.compactMap { $0 as? NumberFieldView }
    }

    // MARK: - A value the app set outside its limits

    @MainActor
    func test_C_ATTR_13_anAppSetComponentOutsideIsRedAndSaysWhy() throws {
        var bounds = try XCTUnwrap(try Self.layerThree().flatMap(\.attributes).first { $0.id == "layer.bounds" })
        bounds.value = Self.bounds(0, 0, -20, 24)
        let (editor, sent) = makeEditor(bounds)
        let row = AttributeRowView(title: "Bounds", value: bounds.value, editor: editor)
        let window = inWindow(row)
        let fields = numbers(in: editor)
        XCTAssertEqual(fields[2].field.textColor, .systemRed)
        XCTAssertEqual(fields[2].field.toolTip, "Width must be 0 or more.")
        XCTAssertEqual(fields[0].field.textColor, .labelColor)
        XCTAssertNil(fields[0].field.toolTip)

        enter("5", into: fields[0].field, in: window)
        XCTAssertEqual(row.noteText, "Width must be 0 or more.")
        XCTAssertTrue(row.noteIsError)
        XCTAssertEqual(sent(), [])

        // Once the app holds a width within its limits, the red goes.
        editor.show(Self.bounds(0, 0, 10, 24))
        XCTAssertEqual(fields[2].field.textColor, .labelColor)
        withExtendedLifetime(window) {}
    }

    // MARK: - Without limits

    @MainActor
    func test_C_ATTR_13_withoutLimitsEverythingIsSent() async throws {
        let (model, session, server) = try await inspection(
            Self.resultSteps(try Self.layerThree(), as: 30), protocol10: true)
        let (controller, window) = panel(for: model)
        let opacity = try row("Opacity", in: controller)
        let number = try XCTUnwrap(try numbers(of: opacity).first)

        enter("1.4", into: number.field, in: window)
        XCTAssertNil(opacity.noteText)
        let answered = await Wait.until { @MainActor in model.attributes.edits.isEmpty }
        XCTAssertTrue(answered)
        try await settle()
        let sent = await Self.sentValues(server)
        XCTAssertEqual(sent, [.double(1.4)], "the app decides (C-ATTR-05, C-ATTR-06)")

        withExtendedLifetime(window) {}
        await session.close()
        await server.stop()
    }
}
