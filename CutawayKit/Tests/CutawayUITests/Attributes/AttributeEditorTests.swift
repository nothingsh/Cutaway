import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayUI

/// The editors of the attribute panel, one kind of value at a time (C-ATTR-05, C-ATTR-07).
/// What they send is caught where the panel would hand it to the model.
final class AttributeEditorTests: XCTestCase {
    /// What an editor sent, in order: a value (nil for "set to None") and whether a drag goes
    /// on; or the end of a drag without a value.
    private enum Sent: Equatable {
        case value(AttributeValue?, continuous: Bool)
        case finished
    }

    @MainActor
    private final class Recorder {
        var sent: [Sent] = []
    }

    @MainActor
    private func editor(
        _ value: AttributeValue?, kind: AttributeValueKind, acceptsNil: Bool = false,
        colorPauseDelay: TimeInterval = 0.5
    ) -> (AttributeEditorView, Recorder) {
        let recorder = Recorder()
        let attribute = Attribute(
            id: "a", title: "A", value: value, editable: true, acceptsNil: acceptsNil,
            valueKind: kind)
        let editor = AttributeEditorView(
            attribute: attribute,
            onSet: { value, continuous in
                recorder.sent.append(.value(value, continuous: continuous))
            },
            onFinish: { recorder.sent.append(.finished) }, colorPauseDelay: colorPauseDelay)
        return (editor, recorder)
    }

    /// Types into a field that has the focus, as the keyboard does: the text changes and the
    /// field hears of it.
    @MainActor
    static func type(_ text: String, into field: NSTextField) {
        guard let editor = field.currentEditor() as? NSTextView else { return }
        editor.string = text
        editor.didChangeText()
    }

    /// The editor in a window that is never shown, so that fields can take the focus.
    @MainActor
    private func inWindow(_ editor: AttributeEditorView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 200), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentView = editor
        window.layoutIfNeeded()
        return window
    }

    @MainActor
    private func views<View: NSView>(
        _ type: View.Type, _ identifier: String, in editor: AttributeEditorView
    ) -> [View] {
        AppListViewTests.descendants(of: editor) {
            $0.accessibilityIdentifier() == identifier
        }.compactMap { $0 as? View }
    }

    @MainActor
    private func area(in editor: AttributeEditorView) throws -> AttributeTextArea {
        try XCTUnwrap(AppListViewTests.descendants(of: editor) { $0 is AttributeTextArea }.first
            as? AttributeTextArea)
    }

    @MainActor
    private func fields(in editor: AttributeEditorView) -> [AttributeEditField] {
        views(AttributeEditField.self, AttributeEditorView.fieldIdentifier, in: editor)
    }

    // MARK: - Typing

    @MainActor
    func test_C_ATTR_05_onlyAFiniteNumberThatChangedIsSent() throws {
        let (editor, recorder) = editor(.double(1), kind: .double)
        let number = try XCTUnwrap(AppListViewTests.descendants(of: editor) { $0 is NumberFieldView }
            .first as? NumberFieldView)
        // What is not a number is refused with the reason (C-ATTR-05, changed on 2026-10-12):
        // the field keeps it on Return and puts the number back on leaving.
        for text in ["abc", "inf", "nan", ""] {
            XCTAssertEqual(number.commit(text), .refused(reason: "Enter a number."), text)
        }
        XCTAssertEqual(number.commit("1"), .accepted, "the number shown: nothing to send")
        XCTAssertEqual(recorder.sent, [])
        XCTAssertEqual(number.commit(" 0.25 "), .accepted)
        XCTAssertEqual(recorder.sent, [.value(.double(0.25), continuous: false)])

        let (integer, integers) = self.editor(.integer(1), kind: .integer)
        let integerField = try XCTUnwrap(AppListViewTests.descendants(of: integer) {
            $0 is NumberFieldView
        }.first as? NumberFieldView)
        XCTAssertEqual(integerField.commit("2.5"), .refused(reason: "Must be a whole number."))
        XCTAssertEqual(integers.sent, [], "not an integer")
        integerField.commit("3")
        XCTAssertEqual(integers.sent, [.value(.integer(3), continuous: false)])
    }

    /// Types into a text area that has the focus, as the keyboard does.
    @MainActor
    private static func type(_ text: String, into area: AttributeTextArea) {
        area.textView.string = text
        area.textView.didChangeText()
    }

    @MainActor
    private static func press(_ selector: Selector, in area: AttributeTextArea) -> Bool {
        area.textView(area.textView, doCommandBy: selector)
    }

    @MainActor
    func test_C_ATTR_05_returnSendsAndEscapePutsTheValueBack() throws {
        let (editor, recorder) = editor(.string("Hello"), kind: .string)
        let window = inWindow(editor)
        let area = try area(in: editor)

        // Typing, then Esc: nothing is sent and the text comes back.
        XCTAssertTrue(window.makeFirstResponder(area.textView))
        Self.type("Bye", into: area)
        XCTAssertTrue(editor.isBeingEdited)
        XCTAssertTrue(Self.press(#selector(NSResponder.cancelOperation(_:)), in: area))
        XCTAssertEqual(area.textView.string, "Hello")
        XCTAssertFalse(window.firstResponder === area.textView)
        XCTAssertEqual(recorder.sent, [])

        // Typing, then Return: what was typed is sent, and the text keeps the focus.
        XCTAssertTrue(window.makeFirstResponder(area.textView))
        Self.type("Bye", into: area)
        XCTAssertTrue(Self.press(#selector(NSResponder.insertNewline(_:)), in: area))
        XCTAssertEqual(recorder.sent, [.value(.string("Bye"), continuous: false)])
        XCTAssertEqual(area.textView.string, "Bye", "Return starts no new line")
        XCTAssertTrue(window.firstResponder === area.textView)

        // Typing, then leaving: sent too.
        Self.type("Bye bye", into: area)
        window.makeFirstResponder(nil)
        XCTAssertEqual(recorder.sent.last, .value(.string("Bye bye"), continuous: false))
        XCTAssertEqual(recorder.sent.count, 2)

        // Leaving without typing sends nothing; an empty text is an empty string, not nil.
        editor.show(.string("Bye bye"))
        XCTAssertTrue(window.makeFirstResponder(area.textView))
        window.makeFirstResponder(nil)
        XCTAssertEqual(recorder.sent.count, 2)
        XCTAssertTrue(window.makeFirstResponder(area.textView))
        Self.type("", into: area)
        window.makeFirstResponder(nil)
        XCTAssertEqual(recorder.sent.last, .value(.string(""), continuous: false))
    }

    /// What is typed is sent as typed: no quotes or dashes replaced, no spelling corrected.
    @MainActor
    func test_C_ATTR_05_aTextIsSentAsTyped() throws {
        let area = try area(in: editor(.string("a"), kind: .string).0)
        let text = area.textView
        XCTAssertFalse(text.isRichText)
        XCTAssertFalse(text.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(text.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(text.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(text.isAutomaticSpellingCorrectionEnabled)
        XCTAssertFalse(text.isAutomaticLinkDetectionEnabled)
        XCTAssertEqual(text.accessibilityLabel(), "A", "named for accessibility")
    }

    @MainActor
    func test_C_ATTR_05_theFieldsKeepNoUndoOfTheirOwn() throws {
        let field = try XCTUnwrap(fields(in: editor(.double(1), kind: .double).0).first)
        XCTAssertEqual(field.cell?.allowsUndo, false)
        XCTAssertFalse(try area(in: editor(.string("a"), kind: .string).0).textView.allowsUndo)
    }

    @MainActor
    func test_C_ATTR_05_aValueBeingTypedIsNotWrittenOver() throws {
        let (editor, _) = editor(.double(1), kind: .double)
        let window = inWindow(editor)
        let field = try XCTUnwrap(fields(in: editor).first)
        XCTAssertTrue(window.makeFirstResponder(field))
        Self.type("0.4", into: field)
        editor.show(.double(0.9))
        XCTAssertEqual((field.currentEditor() as? NSTextView)?.string, "0.4")
        XCTAssertTrue(editor.isBeingEdited)
    }

    // MARK: - None

    /// Nothing sets a value to nil (reported by the user). A nil text shows "None" and, left
    /// empty, sends nothing.
    @MainActor
    func test_C_ATTR_05_aNilTextLeftEmptySendsNothing() throws {
        let (empty, emptySent) = self.editor(nil, kind: .string, acceptsNil: true)
        let area = try area(in: empty)
        XCTAssertEqual(area.placeholder.stringValue, "None")
        XCTAssertFalse(area.placeholder.isHidden)
        let window = inWindow(empty)
        XCTAssertTrue(window.makeFirstResponder(area.textView))
        window.makeFirstResponder(nil)
        XCTAssertEqual(emptySent.sent, [])
        // Typed into, the placeholder goes.
        XCTAssertTrue(window.makeFirstResponder(area.textView))
        Self.type("x", into: area)
        XCTAssertTrue(area.placeholder.isHidden)
    }

    // MARK: - Enum, colour, components

    @MainActor
    func test_C_ATTR_05_aCaseIsSentByItsRawValue() throws {
        let (editor, recorder) = editor(
            .enumeration(EnumValue(
                value: 10, cases: ["left", "center", "right", "justified", "natural"], caseName: "left",
                caseValues: [10, 20, 30, 40, 50])),
            kind: .enumeration)
        let popUp = try XCTUnwrap(
            views(NSPopUpButton.self, AttributeEditorView.popUpIdentifier, in: editor).first)
        popUp.selectItem(at: 2)
        editor.caseChosen(popUp)
        XCTAssertEqual(
            recorder.sent,
            [.value(.enumeration(EnumValue(value: 30, cases: [], caseName: nil)), continuous: false)])
    }

    @MainActor
    func test_C_ATTR_05_aColourIsTypedInHexOrPickedInThePanel() throws {
        let (editor, recorder) = editor(nil, kind: .color, acceptsNil: true)
        let hex = try XCTUnwrap(
            views(AttributeEditField.self, AttributeEditorView.hexIdentifier, in: editor).first)
        XCTAssertEqual(hex.stringValue, "")
        XCTAssertEqual(hex.placeholderString, "None")
        XCTAssertEqual(hex.onCommit("zz", true), .accepted)
        XCTAssertEqual(recorder.sent, [], "not a colour")
        XCTAssertEqual(hex.onCommit("#3366CC", true), .accepted)
        XCTAssertEqual(hex.onCommit("33669980", true), .accepted)
        XCTAssertEqual(recorder.sent, [
            .value(.color(Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)), continuous: false),
            .value(.color(Color(red: 0.2, green: 0.4, blue: 0.6, alpha: Float(0x80) / 255)),
                   continuous: false),
        ])
        XCTAssertEqual(
            AttributeValueEditing.hexRGBA(of: Color(red: 1, green: 0, blue: 0, alpha: 0.5)),
            "#FF000080")
    }

    /// The panel's "no colour" swatch is closed to public API: an emptied hex field clears the
    /// colour to transparent instead (reported by the user). A colour that is nil, or already
    /// transparent, sends nothing.
    @MainActor
    func test_C_ATTR_05_anEmptiedHexClearsTheColour() throws {
        let clear = Color(red: 0, green: 0, blue: 0, alpha: 0)
        let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
        for (value, expected) in [
            (AttributeValue?.some(.color(red)), [Sent.value(.color(clear), continuous: false)]),
            (.color(clear), []),
            (nil, []),
        ] {
            let (editor, recorder) = editor(value, kind: .color, acceptsNil: true)
            let hex = try XCTUnwrap(
                views(AttributeEditField.self, AttributeEditorView.hexIdentifier, in: editor).first)
            XCTAssertEqual(hex.onCommit("  ", true), .accepted)
            XCTAssertEqual(recorder.sent, expected, "\(String(describing: value))")
        }
    }

    @MainActor
    func test_C_ATTR_07_theColourPanelSendsAsItMovesAndFinishesWhenStill() async throws {
        let (editor, recorder) = editor(nil, kind: .color, acceptsNil: true, colorPauseDelay: 0.05)
        let well = try XCTUnwrap(
            views(NSColorWell.self, AttributeEditorView.wellIdentifier, in: editor).first)
        for red in [0.2, 0.4, 0.6] {
            well.color = NSColor(srgbRed: red, green: 0, blue: 0, alpha: 1)
            editor.colorChanged(well)
        }
        XCTAssertEqual(recorder.sent.count, 3)
        XCTAssertTrue(recorder.sent.allSatisfy {
            if case .value(.color, continuous: true) = $0 { return true }
            return false
        })
        XCTAssertTrue(editor.isBeingEdited, "the panel may still move")
        let finished = await Wait.until { @MainActor in recorder.sent.last == .finished }
        XCTAssertTrue(finished)
        XCTAssertEqual(recorder.sent.filter { $0 == .finished }.count, 1)
    }

    @MainActor
    func test_C_ATTR_05_aComponentChangesItsPartOfTheValue() {
        let (editor, recorder) = editor(
            .rect(Rect(origin: Point(x: 1, y: 2), size: Size(width: 3, height: 4))), kind: .rect)
        let numbers = AppListViewTests.descendants(of: editor) { $0 is NumberFieldView }
            .compactMap { $0 as? NumberFieldView }
        XCTAssertEqual(numbers.count, 4)
        numbers[2].commit("300")
        XCTAssertEqual(recorder.sent, [.value(.rect(Rect(
            origin: Point(x: 1, y: 2), size: Size(width: 300, height: 4))), continuous: false)])
    }

    // MARK: - Found in review

    /// Clicking into a field and leaving it sent the shown, rounded number.
    @MainActor
    func test_C_ATTR_05_leavingAFieldWithoutTypingSendsNothing() throws {
        let (number, numbers) = editor(.double(0.333333), kind: .double)
        var window = inWindow(number)
        var field = try XCTUnwrap(fields(in: number).first)
        XCTAssertEqual(field.stringValue, "0.3333")
        XCTAssertTrue(window.makeFirstResponder(field))
        window.makeFirstResponder(nil)
        XCTAssertEqual(numbers.sent, [], "the number shown is rounded; nothing was typed")

        let (color, colors) = editor(
            .color(Color(red: 1, green: 0, blue: 0, alpha: 0.5)), kind: .color)
        window = inWindow(color)
        field = try XCTUnwrap(
            views(AttributeEditField.self, AttributeEditorView.hexIdentifier, in: color).first)
        XCTAssertTrue(window.makeFirstResponder(field))
        window.makeFirstResponder(nil)
        XCTAssertEqual(colors.sent, [], "a hex code holds 8 bits; nothing was typed")
    }

    /// After Return the field keeps its field editor, and the answer never reached it.
    @MainActor
    func test_C_ATTR_06_theAnswerReachesAFieldAfterReturn() throws {
        let (editor, recorder) = editor(.double(1), kind: .double)
        let window = inWindow(editor)
        let field = try XCTUnwrap(fields(in: editor).first)
        XCTAssertTrue(window.makeFirstResponder(field))
        Self.type("5", into: field)
        let text = try XCTUnwrap(field.currentEditor() as? NSTextView)
        text.insertNewline(nil)
        XCTAssertEqual(recorder.sent, [.value(.double(5), continuous: false)])
        // The app clamps it (P-SET-04): the field shows what came back, and Esc goes to it.
        editor.show(.double(1))
        XCTAssertEqual(field.stringValue, "1")
        XCTAssertEqual((field.currentEditor() as? NSTextView)?.string ?? field.stringValue, "1")
        field.cancelTyping()
        XCTAssertEqual(field.stringValue, "1")
    }

    /// An integer too big for a Double to hold exactly crashed the app.
    @MainActor
    func test_C_ATTR_05_anIntegerBeyondWhatCanBeSentExactlyIsRefused() throws {
        let (editor, recorder) = editor(.integer(1), kind: .integer)
        let number = try XCTUnwrap(AppListViewTests.descendants(of: editor) {
            $0 is NumberFieldView
        }.first as? NumberFieldView)
        XCTAssertEqual(number.commit("9223372036854775807"), .refused(reason: "The number is too large."))
        XCTAssertEqual(number.commit("9007199254740993"), .refused(reason: "The number is too large."))  // 2^53 + 1
        XCTAssertEqual(number.commit("1e30"), .refused(reason: "The number is too large."))
        XCTAssertEqual(recorder.sent, [])
        XCTAssertEqual(number.field.stringValue, "1")
        number.commit("9007199254740992")
        XCTAssertEqual(recorder.sent, [.value(.integer(9_007_199_254_740_992), continuous: false)])
    }

    /// A value on its way carries its raw value alone; the menu emptied until the answer came.
    @MainActor
    func test_C_ATTR_05_theMenuKeepsItsCasesWhileAChangeIsOnItsWay() throws {
        let (editor, _) = editor(
            .enumeration(EnumValue(
                value: 0, cases: ["left", "center", "right", "justified", "natural"], caseName: "left",
                caseValues: [0, 1, 2, 3, 4])),
            kind: .enumeration)
        let popUp = try XCTUnwrap(
            views(NSPopUpButton.self, AttributeEditorView.popUpIdentifier, in: editor).first)
        editor.show(.enumeration(EnumValue(value: 2, cases: [], caseName: nil)))
        XCTAssertEqual(popUp.itemTitles, ["left", "center", "right", "justified", "natural"])
        XCTAssertEqual(popUp.indexOfSelectedItem, 2)
    }

    /// An editor that went away during the colour panel's pause left its change open.
    @MainActor
    func test_C_ATTR_07_aColourChangeEndsEvenWhenItsEditorIsGone() async throws {
        let recorder = Recorder()
        weak var gone: AttributeEditorView?
        do {
            let editor = AttributeEditorView(
                attribute: Attribute(
                    id: "a", title: "A", value: nil, editable: true, acceptsNil: true,
                    valueKind: .color),
                onSet: { value, continuous in
                    recorder.sent.append(.value(value, continuous: continuous))
                },
                onFinish: { recorder.sent.append(.finished) }, colorPauseDelay: 0.05)
            let well = try XCTUnwrap(
                views(NSColorWell.self, AttributeEditorView.wellIdentifier, in: editor).first)
            well.color = .red
            editor.colorChanged(well)
            gone = editor
        }
        let finished = await Wait.until { @MainActor in recorder.sent.last == .finished }
        XCTAssertTrue(finished)
        XCTAssertNil(gone)
    }

    /// The colour panel stayed attached to the well of a row that went away with the
    /// selection, and went on changing the layer selected before (found in review).
    @MainActor
    func test_C_ATTR_07_aColourWellLetsThePanelGoWhenItsRowGoesAway() throws {
        let (editor, recorder) = editor(nil, kind: .color, acceptsNil: true, colorPauseDelay: 0.05)
        let window = inWindow(editor)
        defer { NSColorPanel.shared.orderOut(nil) }
        let well = try XCTUnwrap(
            views(NSColorWell.self, AttributeEditorView.wellIdentifier, in: editor).first)
        well.activate(true)
        XCTAssertTrue(well.isActive)
        // Another layer is selected: the panel's rows are built anew.
        window.contentView = NSView()
        XCTAssertFalse(well.isActive)
        well.color = .blue
        editor.colorChanged(well)
        XCTAssertEqual(recorder.sent, [], "the layer selected before is left alone")
    }

    /// Every colour row kept its hex field alive: its commit held it.
    @MainActor
    func test_C_ATTR_05_aColourEditorLetsItsFieldGo() {
        weak var field: NSTextField?
        autoreleasepool {
            let (editor, _) = editor(.color(.zero), kind: .color)
            field = views(AttributeEditField.self, AttributeEditorView.hexIdentifier, in: editor)
                .first
            XCTAssertNotNil(field)
        }
        XCTAssertNil(field)
    }

    // MARK: - Reported by the user: text, spinner and failures

    /// The nearest box a view sits in.
    @MainActor
    private static func box(around view: NSView) -> NSBox? {
        var current = view.superview
        while let candidate = current, !(candidate is NSBox) { current = candidate.superview }
        return current as? NSBox
    }

    /// The middle of a view, in its window.
    @MainActor
    private static func midY(_ view: NSView) -> CGFloat {
        view.convert(view.bounds, to: nil).midY
    }

    // MARK: - C-SCALE-02

    /// An editor that goes, with the panel or a new selection, takes all its controls with it:
    /// the attribute panel builds new ones each time (C-SCALE-02).
    @MainActor
    func test_C_SCALE_02_anEditorThatGoesTakesItsControlsWithIt() {
        let values: [(AttributeValue?, AttributeValueKind)] = [
            (.bool(true), .bool), (.integer(3), .integer), (.double(0.5), .double),
            (.string("a"), .string), (.color(Color(red: 1, green: 0, blue: 0, alpha: 1)), .color),
            (.point(Point(x: 1, y: 2)), .point), (.size(Size(width: 1, height: 2)), .size),
            (.rect(Rect(origin: Point(x: 1, y: 2), size: Size(width: 3, height: 4))), .rect),
            (.transform(.identity), .transform),
        ]
        for (value, kind) in values {
            var controls: [() -> NSView?] = []
            autoreleasepool {
                let (editor, _) = editor(value, kind: kind)
                let window = inWindow(editor)
                var pending: [NSView] = [editor]
                while let view = pending.popLast() {
                    weak let weakView = view
                    controls.append { weakView }
                    pending += view.subviews
                }
                window.contentView = nil
            }
            // AppKit keeps every NSTextView alive in a test, even one made and dropped at once
            // without a window; the text area and everything of ours around it still go.
            let left = controls.compactMap { $0() }.map { String(describing: Swift.type(of: $0)) }
                .filter { $0 != "NSTextView" }
            XCTAssertEqual(left, [], "\(kind)")
        }
    }
}
