import AppKit
import CutawayModel
import CutawayWire
import XCTest

@testable import CutawayUI

/// Units (C-ATTR-20), and the colour field, the insets box and the segments of a short enum
/// (C-ATTR-22), one editor at a time. What an editor sends is caught where the panel would hand
/// it to the model.
final class AttributeValueControlsTests: XCTestCase {
    @MainActor
    private final class Recorder {
        var sent: [AttributeValue?] = []
    }

    @MainActor
    private func editor(
        _ value: AttributeValue?, kind: AttributeValueKind, unit: AttributeUnit = .unspecified,
        limits: [NumberLimit]? = nil, isReadOnly: Bool = false
    ) -> (AttributeEditorView, Recorder) {
        let recorder = Recorder()
        let attribute = Attribute(
            id: "a", title: "A", value: value, editable: true, valueKind: kind, limits: limits,
            unit: unit)
        let editor = AttributeEditorView(
            attribute: attribute, isReadOnly: isReadOnly,
            onSet: { value, _ in recorder.sent.append(value) })
        return (editor, recorder)
    }

    @MainActor
    private func views<View: NSView>(_ type: View.Type, in view: NSView) -> [View] {
        AppListViewTests.descendants(of: view) { $0 is View }.compactMap { $0 as? View }
    }

    @MainActor
    private func view(_ identifier: String, in view: NSView) -> NSView? {
        AppListViewTests.descendants(of: view) { $0.accessibilityIdentifier() == identifier }.first
    }

    @MainActor
    private func inWindow(_ view: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 200), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentView = view
        window.layoutIfNeeded()
        return window
    }

    private static let proportion = [NumberLimit(minimum: 0, maximum: 1)]

    // MARK: - C-ATTR-20

    @MainActor
    func test_C_ATTR_20_aFractionIsShownAndTypedInPercent() throws {
        let (editor, recorder) = editor(.double(1), kind: .double, unit: .fraction, limits: Self.proportion)
        let number = try XCTUnwrap(views(NumberFieldView.self, in: editor).first)
        XCTAssertEqual(number.field.stringValue, "100")
        XCTAssertEqual(number.shownUnit, "%")

        XCTAssertEqual(number.commit("40"), .accepted)
        XCTAssertEqual(recorder.sent, [.double(0.4)], "sent as a proportion")
        XCTAssertEqual(number.field.stringValue, "40")

        XCTAssertEqual(number.commit("140"), .refused(reason: "Must be between 0% and 100%."))
        XCTAssertEqual(recorder.sent.count, 1, "outside the limits: not sent")

        editor.show(.double(0.375))
        XCTAssertEqual(number.field.stringValue, "37.5")
        editor.show(.double(0.123456))
        XCTAssertEqual(number.field.stringValue, "12.35", "at most two decimals")
    }

    @MainActor
    func test_C_ATTR_20_anIntegerIsNeverInPercent() throws {
        let (editor, recorder) = editor(.integer(1), kind: .integer, unit: .fraction)
        let number = try XCTUnwrap(views(NumberFieldView.self, in: editor).first)
        XCTAssertEqual(number.field.stringValue, "1")
        XCTAssertNil(number.shownUnit)
        number.commit("2")
        XCTAssertEqual(recorder.sent, [.integer(2)])
    }

    // MARK: - C-ATTR-22

    @MainActor
    private func hex(in editor: NSView) throws -> AttributeEditField {
        try XCTUnwrap(view(AttributeEditorView.hexIdentifier, in: editor) as? AttributeEditField)
    }

    @MainActor
    private func alpha(in editor: NSView) throws -> NSTextField {
        try XCTUnwrap(view(AttributeEditorView.alphaIdentifier, in: editor) as? NSTextField)
    }

    /// Six digits keep the opacity shown beside them; eight set it too.
    @MainActor
    func test_C_ATTR_22_sixDigitsKeepTheOpacity() throws {
        let (editor, recorder) = editor(
            .color(Color(red: 1, green: 0, blue: 0, alpha: 0.5)), kind: .color)
        let field = try hex(in: editor)
        XCTAssertEqual(field.onCommit("3366CC", true), .accepted)
        XCTAssertEqual(field.onCommit("#33669980", true), .accepted)
        XCTAssertEqual(recorder.sent, [
            .color(Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.5)),
            .color(Color(red: 0.2, green: 0.4, blue: 0.6, alpha: Float(0x80) / 255)),
        ])
    }

    @MainActor
    func test_C_ATTR_22_insetsAreABoxWithTheLayersSizeInTheMiddle() throws {
        let (editor, recorder) = editor(
            .insets(Insets(top: 8, left: 20, bottom: 16, right: 4)), kind: .insets, unit: .points,
            limits: [NumberLimit(minimum: 0)])
        let window = inWindow(editor)
        XCTAssertNotNil(view(AttributeEditorView.insetsIdentifier, in: editor))
        let numbers = views(NumberFieldView.self, in: editor)
        XCTAssertEqual(numbers.map(\.field.stringValue), ["8", "20", "16", "4"])
        XCTAssertEqual(numbers.map(\.shownUnit), [nil, nil, nil, nil])

        // Top in the middle above, bottom below, left and right at the sides.
        let frames = numbers.map { $0.convert($0.bounds, to: nil) }
        XCTAssertGreaterThan(frames[0].minY, frames[2].maxY, "top above bottom")
        XCTAssertEqual(frames[0].midX, frames[2].midX, accuracy: 0.5)
        XCTAssertLessThan(frames[1].maxX, frames[0].minX, "left at the left")
        XCTAssertGreaterThan(frames[3].minX, frames[0].maxX, "right at the right")

        let size = try XCTUnwrap(view(AttributeEditorView.insetsSizeIdentifier, in: editor) as? NSTextField)
        XCTAssertEqual(size.stringValue, "")
        editor.show(layerSize: "200 × 24")
        XCTAssertEqual(size.stringValue, "200 × 24")

        numbers[1].commit("12")
        XCTAssertEqual(recorder.sent, [.insets(Insets(top: 8, left: 12, bottom: 16, right: 4))])
        XCTAssertEqual(numbers[3].commit("-1"), .refused(reason: "Right must be 0 or more."))

        let (readOnly, _) = self.editor(
            .insets(Insets(top: 1, left: 2, bottom: 3, right: 4)), kind: .insets, isReadOnly: true)
        let box = try XCTUnwrap(view(AttributeEditorView.insetsIdentifier, in: readOnly))
        XCTAssertLessThan(box.alphaValue, 1, "a read-only box is faint")
        XCTAssertTrue(views(NumberFieldView.self, in: readOnly).allSatisfy(\.isReadOnly))
        withExtendedLifetime(window) {}
    }

    private static func enumeration(_ cases: [String], value: Int64 = 0) -> AttributeValue {
        .enumeration(EnumValue(
            value: value, cases: cases, caseName: nil, caseValues: cases.indices.map { Int64($0) * 10 }))
    }

    @MainActor
    func test_C_ATTR_22_aShortEnumIsSegments() throws {
        XCTAssertTrue(AttributeEditorView.fitsSegments(Self.enumeration(["start", "center", "end"])))
        XCTAssertTrue(AttributeEditorView.fitsSegments(Self.enumeration(["a", "b"])))
        XCTAssertFalse(AttributeEditorView.fitsSegments(Self.enumeration(["a"])), "one case")
        XCTAssertFalse(
            AttributeEditorView.fitsSegments(Self.enumeration(["left", "center", "right", "justified", "natural"])),
            "five cases")
        XCTAssertFalse(
            AttributeEditorView.fitsSegments(Self.enumeration(["scaleToFill", "center"])), "a long name")
        XCTAssertFalse(
            AttributeEditorView.fitsSegments(
                .enumeration(EnumValue(value: 0, cases: ["a", "b"], caseName: nil, caseValues: []))),
            "no raw values")
        XCTAssertFalse(
            AttributeEditorView.fitsSegments(Self.enumeration(["a", "b"], value: 5)), "a value not among them")

        let (editor, recorder) = editor(Self.enumeration(["start", "center", "end"], value: 10), kind: .enumeration)
        XCTAssertNil(view(AttributeEditorView.popUpIdentifier, in: editor))
        let control = try XCTUnwrap(
            view(AttributeEditorView.segmentedIdentifier, in: editor) as? NSSegmentedControl)
        XCTAssertEqual((0..<control.segmentCount).map { control.label(forSegment: $0) }, ["start", "center", "end"])
        XCTAssertEqual(control.selectedSegment, 1)
        control.selectedSegment = 2
        editor.segmentChosen(control)
        XCTAssertEqual(recorder.sent, [.enumeration(EnumValue(value: 20, cases: [], caseName: nil))])

        let (long, _) = self.editor(
            Self.enumeration(["left", "center", "right", "justified", "natural"]), kind: .enumeration)
        XCTAssertNotNil(view(AttributeEditorView.popUpIdentifier, in: long))
        XCTAssertNil(view(AttributeEditorView.segmentedIdentifier, in: long))

        let (readOnly, _) = self.editor(Self.enumeration(["a", "b"]), kind: .enumeration, isReadOnly: true)
        let disabled = try XCTUnwrap(
            view(AttributeEditorView.segmentedIdentifier, in: readOnly) as? NSSegmentedControl)
        XCTAssertFalse(disabled.isEnabled)
    }
}
