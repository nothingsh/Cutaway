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
    private func fields(in editor: AttributeEditorView) -> [AttributeEditField] {
        views(AttributeEditField.self, AttributeEditorView.fieldIdentifier, in: editor)
    }

    // MARK: - One control for each kind

    @MainActor
    func test_C_ATTR_05_eachKindHasItsControl() throws {
        XCTAssertEqual(
            views(NSSwitch.self, AttributeEditorView.switchIdentifier,
                  in: editor(.bool(true), kind: .bool).0).first?.state, .on)
        let number = editor(.double(0.5), kind: .double).0
        XCTAssertEqual(fields(in: number).map(\.stringValue), ["0.5"])
        XCTAssertEqual(views(ScrubHandle.self, AttributeEditorView.handleIdentifier, in: number).count, 1)
        XCTAssertEqual(fields(in: editor(.integer(3), kind: .integer).0).map(\.stringValue), ["3"])
        XCTAssertEqual(fields(in: editor(.string("Hello"), kind: .string).0).map(\.stringValue), ["Hello"])

        let color = editor(
            .color(Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)), kind: .color).0
        XCTAssertEqual(views(NSColorWell.self, AttributeEditorView.wellIdentifier, in: color).count, 1)
        XCTAssertEqual(
            views(AttributeEditField.self, AttributeEditorView.hexIdentifier, in: color)
                .map(\.stringValue), ["#3366CC"])

        let rect = editor(
            .rect(Rect(origin: Point(x: 1, y: 2), size: Size(width: 3, height: 4))), kind: .rect).0
        XCTAssertEqual(fields(in: rect).map(\.stringValue), ["1", "2", "3", "4"])
        XCTAssertEqual(views(ScrubHandle.self, AttributeEditorView.handleIdentifier, in: rect).count, 4)
        XCTAssertEqual(fields(in: editor(.point(Point(x: 5, y: 6)), kind: .point).0).count, 2)
        XCTAssertEqual(fields(in: editor(.size(Size(width: 5, height: 6)), kind: .size).0).count, 2)
        XCTAssertEqual(
            fields(in: editor(.insets(Insets(top: 8, left: 8, bottom: 8, right: 8)), kind: .insets).0)
                .count, 4)

        let transform = editor(.transform(.identity), kind: .transform).0
        XCTAssertEqual(fields(in: transform).count, 16)
        XCTAssertEqual(
            views(NSButton.self, AttributeEditorView.disclosureIdentifier, in: transform).count, 1)

        let enumeration = editor(
            .enumeration(EnumValue(
                value: 1, cases: ["left", "center", "right"], caseName: "center",
                caseValues: [0, 1, 2])),
            kind: .enumeration).0
        let popUp = try XCTUnwrap(
            views(NSPopUpButton.self, AttributeEditorView.popUpIdentifier, in: enumeration).first)
        XCTAssertEqual(popUp.itemTitles, ["left", "center", "right"])
        XCTAssertEqual(popUp.indexOfSelectedItem, 1)
    }

    // MARK: - Typing

    @MainActor
    func test_C_ATTR_05_onlyAFiniteNumberThatChangedIsSent() throws {
        let (editor, recorder) = editor(.double(1), kind: .double)
        let number = try XCTUnwrap(AppListViewTests.descendants(of: editor) { $0 is NumberFieldView }
            .first as? NumberFieldView)
        for text in ["abc", "inf", "nan", "", "1"] {
            number.field.stringValue = text
            number.commit(text)
            XCTAssertEqual(number.field.stringValue, "1", "\(text) goes back to the number")
        }
        XCTAssertEqual(recorder.sent, [])
        number.commit(" 0.25 ")
        XCTAssertEqual(recorder.sent, [.value(.double(0.25), continuous: false)])

        let (integer, integers) = self.editor(.integer(1), kind: .integer)
        let integerField = try XCTUnwrap(AppListViewTests.descendants(of: integer) {
            $0 is NumberFieldView
        }.first as? NumberFieldView)
        integerField.commit("2.5")
        XCTAssertEqual(integers.sent, [], "not an integer")
        integerField.commit("3")
        XCTAssertEqual(integers.sent, [.value(.integer(3), continuous: false)])
    }

    @MainActor
    func test_C_ATTR_05_returnSendsAndEscapePutsTheValueBack() throws {
        let (editor, recorder) = editor(.string("Hello"), kind: .string)
        let window = inWindow(editor)
        let field = try XCTUnwrap(fields(in: editor).first)

        // Typing, then Esc: nothing is sent and the text comes back.
        XCTAssertTrue(window.makeFirstResponder(field))
        let text = try XCTUnwrap(field.currentEditor() as? NSTextView)
        text.string = "Bye"
        text.didChangeText()
        XCTAssertTrue(field.control(
            field, textView: text, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(field.stringValue, "Hello")
        XCTAssertNil(field.currentEditor())
        XCTAssertEqual(recorder.sent, [])

        // Typing, then leaving the field (as Return does): what was typed is sent.
        XCTAssertTrue(window.makeFirstResponder(field))
        Self.type("Bye", into: field)
        window.makeFirstResponder(nil)
        XCTAssertEqual(recorder.sent, [.value(.string("Bye"), continuous: false)])

        // An empty field is an empty string, not nil.
        editor.show(.string("Bye"))
        XCTAssertTrue(window.makeFirstResponder(field))
        Self.type("", into: field)
        window.makeFirstResponder(nil)
        XCTAssertEqual(recorder.sent.last, .value(.string(""), continuous: false))
    }

    @MainActor
    func test_C_ATTR_05_theFieldsKeepNoUndoOfTheirOwn() throws {
        let field = try XCTUnwrap(fields(in: editor(.string("a"), kind: .string).0).first)
        XCTAssertEqual(field.cell?.allowsUndo, false)
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
        XCTAssertEqual(fields(in: empty).first?.placeholderString, "None")
        let window = inWindow(empty)
        let field = try XCTUnwrap(fields(in: empty).first)
        XCTAssertTrue(window.makeFirstResponder(field))
        window.makeFirstResponder(nil)
        XCTAssertEqual(emptySent.sent, [])
    }

    // MARK: - Enum, colour, components

    @MainActor
    func test_C_ATTR_05_aCaseIsSentByItsRawValue() throws {
        let (editor, recorder) = editor(
            .enumeration(EnumValue(
                value: 10, cases: ["left", "center", "right"], caseName: "left",
                caseValues: [10, 20, 30])),
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
        hex.onCommit("zz")
        XCTAssertEqual(recorder.sent, [], "not a colour")
        hex.onCommit("#3366CC")
        hex.onCommit("33669980")
        XCTAssertEqual(recorder.sent, [
            .value(.color(Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)), continuous: false),
            .value(.color(Color(red: 0.2, green: 0.4, blue: 0.6, alpha: Float(0x80) / 255)),
                   continuous: false),
        ])
        XCTAssertEqual(
            AttributeValueEditing.hexRGBA(of: Color(red: 1, green: 0, blue: 0, alpha: 0.5)),
            "#FF000080")
    }

    /// No colour and transparent black show alike (reported by the user): the well is
    /// transparent, as the system draws it, and the hex field shows "None".
    @MainActor
    func test_C_ATTR_05_noColourAndTransparentShowAlike() throws {
        let clear = Color(red: 0, green: 0, blue: 0, alpha: 0)
        for value in [nil, AttributeValue.color(clear)] {
            let (editor, _) = editor(value, kind: .color, acceptsNil: true)
            let hex = try XCTUnwrap(
                views(AttributeEditField.self, AttributeEditorView.hexIdentifier, in: editor).first)
            let well = try XCTUnwrap(
                views(NSColorWell.self, AttributeEditorView.wellIdentifier, in: editor).first)
            XCTAssertEqual(hex.stringValue, "", "\(String(describing: value))")
            XCTAssertEqual(hex.placeholderString, "None")
            XCTAssertEqual(AttributeEditorView.color(of: well.color), clear)
        }
        let (red, _) = editor(.color(Color(red: 1, green: 0, blue: 0, alpha: 1)), kind: .color)
        let hex = try XCTUnwrap(
            views(AttributeEditField.self, AttributeEditorView.hexIdentifier, in: red).first)
        XCTAssertEqual(hex.stringValue, "#FF0000")
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
            hex.onCommit("  ")
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

    // MARK: - Dragging

    @MainActor
    func test_C_ATTR_07_theStepFollowsTheNumber() {
        XCTAssertEqual(NumberFieldView.step(from: 1, isInteger: false, modifiers: []), 0.01)
        XCTAssertEqual(NumberFieldView.step(from: -0.5, isInteger: false, modifiers: []), 0.01)
        XCTAssertEqual(NumberFieldView.step(from: 12, isInteger: false, modifiers: []), 1)
        XCTAssertEqual(NumberFieldView.step(from: 0.5, isInteger: true, modifiers: []), 1)
        XCTAssertEqual(NumberFieldView.step(from: 12, isInteger: false, modifiers: .option), 0.1)
        XCTAssertEqual(NumberFieldView.step(from: 12, isInteger: false, modifiers: .shift), 10)
        XCTAssertEqual(NumberFieldView.step(from: 1, isInteger: false, modifiers: .option), 0.001)
        XCTAssertEqual(NumberFieldView.step(from: 5, isInteger: true, modifiers: .option), 1)
        XCTAssertEqual(NumberFieldView.step(from: 5, isInteger: true, modifiers: .shift), 10)
        XCTAssertEqual(AttributeValueEditing.scrubbed(0.1, by: 20, step: 0.01), 0.3)
        XCTAssertEqual(AttributeValueEditing.scrubbed(1, by: -30, step: 0.01), 0.7)
    }

    @MainActor
    func test_C_ATTR_07_aDragSendsAsItGoesAndItsEnd() throws {
        let (editor, recorder) = editor(.double(1), kind: .double)
        let number = try XCTUnwrap(AppListViewTests.descendants(of: editor) {
            $0 is NumberFieldView
        }.first as? NumberFieldView)
        number.scrub(by: -10, modifiers: [], ended: false)
        number.scrub(by: -30, modifiers: [], ended: false)
        XCTAssertTrue(editor.isBeingEdited)
        editor.show(.double(0.95))
        XCTAssertEqual(number.field.stringValue, "0.7", "an answer does not move a drag")
        number.scrub(by: -50, modifiers: [], ended: true)
        XCTAssertEqual(recorder.sent, [
            .value(.double(0.9), continuous: true), .value(.double(0.7), continuous: true),
            .value(.double(0.5), continuous: false),
        ])
        XCTAssertFalse(editor.isBeingEdited)
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
        number.commit("9223372036854775807")
        number.commit("9007199254740993")  // 2^53 + 1
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
                value: 0, cases: ["left", "center", "right"], caseName: "left",
                caseValues: [0, 1, 2])),
            kind: .enumeration)
        let popUp = try XCTUnwrap(
            views(NSPopUpButton.self, AttributeEditorView.popUpIdentifier, in: editor).first)
        editor.show(.enumeration(EnumValue(value: 2, cases: [], caseName: nil)))
        XCTAssertEqual(popUp.itemTitles, ["left", "center", "right"])
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

    @MainActor
    func test_C_ATTR_05_theControlsAreNamedForAccessibility() {
        let (editor, _) = editor(.point(Point(x: 1, y: 2)), kind: .point)
        XCTAssertEqual(fields(in: editor).map { $0.accessibilityLabel() }, ["A X", "A Y"])
        XCTAssertEqual(
            views(ScrubHandle.self, AttributeEditorView.handleIdentifier, in: editor)
                .map { $0.accessibilityLabel() }, ["Adjust A X", "Adjust A Y"])
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

    /// The hex field sat at the top of its box; the other fields were in the middle.
    @MainActor
    func test_C_ATTR_05_textSitsInTheMiddleOfItsField() throws {
        for (value, kind, identifier) in [
            (AttributeValue.color(.zero), AttributeValueKind.color, AttributeEditorView.hexIdentifier),
            (.string("Hello"), .string, AttributeEditorView.fieldIdentifier),
            (.double(1), .double, AttributeEditorView.fieldIdentifier),
        ] {
            let (editor, _) = editor(value, kind: kind)
            let window = inWindow(editor)
            window.layoutIfNeeded()
            let field = try XCTUnwrap(
                views(AttributeEditField.self, identifier, in: editor).first, "\(kind)")
            let box = try XCTUnwrap(Self.box(around: field), "\(kind)")
            XCTAssertEqual(Self.midY(field), Self.midY(box), accuracy: 1, "\(kind)")
            // A text field draws its text at its top: stretched to the box, the text sits high.
            XCTAssertEqual(
                field.frame.height, field.intrinsicContentSize.height, accuracy: 1,
                "\(kind): the field keeps its own height")
        }
    }

    /// The spinner took width from the fields beside it; it now floats at the end of the field
    /// that was changed.
    @MainActor
    func test_C_ATTR_06_theSpinnerFloatsInTheFieldThatChanged() {
        let (editor, _) = editor(.point(Point(x: 1, y: 2)), kind: .point)
        let window = inWindow(editor)
        window.layoutIfNeeded()
        let numbers = AppListViewTests.descendants(of: editor) { $0 is NumberFieldView }
            .compactMap { $0 as? NumberFieldView }
        let widths = numbers.map(\.frame.width)
        let size = editor.fittingSize

        numbers[1].commit("5")
        editor.showStatus(sending: true, failure: nil)
        window.layoutIfNeeded()
        XCTAssertTrue(numbers[1].badge.isShowingSpinner)
        XCTAssertFalse(numbers[0].badge.isShowingSpinner)
        XCTAssertEqual(numbers.map(\.frame.width), widths, "the fields keep their width")
        XCTAssertEqual(editor.fittingSize, size)
        XCTAssertEqual(editor.isShowingSending, true)

        editor.showStatus(sending: false, failure: nil)
        XCTAssertFalse(numbers[1].badge.isShowingSpinner)
    }

    /// A failure was a line below the value, which made the row taller and flickered while a
    /// drag went back and forth: it is now a warning sign at the end of the field, with the
    /// reason in its tooltip.
    @MainActor
    func test_C_ATTR_06_aFailureIsAWarningSignWithTheReasonOnHover() throws {
        let (editor, _) = editor(.double(1), kind: .double)
        let window = inWindow(editor)
        window.layoutIfNeeded()
        let size = editor.fittingSize
        editor.showStatus(sending: false, failure: "Demo did not accept this value.")
        window.layoutIfNeeded()
        let sign = try XCTUnwrap(
            views(NSImageView.self, AttributeEditorView.failureIdentifier, in: editor).first)
        XCTAssertTrue(AttributeEditingViewTests.isShown(sign))
        XCTAssertEqual(sign.toolTip, "Demo did not accept this value.")
        XCTAssertEqual(sign.accessibilityLabel(), "Demo did not accept this value.")
        XCTAssertEqual(editor.failureText, "Demo did not accept this value.")
        XCTAssertEqual(editor.fittingSize, size, "no room is added for it")

        editor.showStatus(sending: false, failure: nil)
        XCTAssertNil(editor.failureText)
        XCTAssertFalse(AttributeEditingViewTests.isShown(sign))
    }

    // MARK: - Reported by the user: nothing to set a value to nil

    @MainActor
    func test_C_ATTR_05_noRowHasAClearButton() {
        for (value, kind) in [
            (AttributeValue.string("a"), AttributeValueKind.string),
            (.color(.zero), .color),
        ] {
            let (editor, _) = editor(value, kind: kind, acceptsNil: true)
            XCTAssertTrue(
                AppListViewTests.descendants(of: editor) {
                    $0.accessibilityIdentifier() == "attributes.editor.clear"
                }.isEmpty, "\(kind)")
            XCTAssertFalse(
                editor.responds(to: Selector(("setToNone:"))), "\(kind): no Set to None either")
        }
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
            let left = controls.compactMap { $0() }.map { String(describing: Swift.type(of: $0)) }
            XCTAssertEqual(left, [], "\(kind)")
        }
    }
}
