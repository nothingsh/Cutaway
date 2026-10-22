import AppKit
import Combine
import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// C-ATTR-09: values at the edges of what the wire can carry are shown, and their editors
/// open, without a crash; a number that is not finite cannot be dragged.
@MainActor
final class ExtremeAttributeTests: XCTestCase {
    private static let big = Double.greatestFiniteMagnitude

    private static func transform(_ m34: Double) -> Transform3D {
        Transform3D(
            m11: 1, m12: 0, m13: 0, m14: 0, m21: 0, m22: 1, m23: 0, m24: 0,
            m31: 0, m32: 0, m33: 1, m34: m34, m41: .nan, m42: .infinity, m43: 0, m44: 1)
    }

    /// Each value with the kind its editor is made for.
    private static let numbers: [(AttributeValue, AttributeValueKind)] = {
        var values: [(AttributeValue, AttributeValueKind)] = []
        for x in [Double.nan, .infinity, -.infinity, big, -big] {
            values += [
                (.double(x), .double),
                (.point(Point(x: x, y: 1)), .point),
                (.size(Size(width: 1, height: x)), .size),
                (.rect(Rect(origin: Point(x: x, y: x), size: Size(width: x, height: 2))), .rect),
                (.insets(Insets(top: x, left: 0, bottom: -x, right: 0)), .insets),
                (.transform(transform(x)), .transform),
            ]
        }
        values += [(.integer(.max), .integer), (.integer(.min), .integer)]
        return values
    }()

    private func window(showing view: NSView, width: CGFloat = 260) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 400), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentView = view
        window.layoutIfNeeded()
        return window
    }

    /// The read-only row and the open editor for a value, laid out in windows.
    private func showAndEdit(
        _ value: AttributeValue, _ kind: AttributeValueKind
    ) -> AttributeRowView {
        let row = AttributeRowView(title: "A", value: value, kind: kind)
        _ = window(showing: row)
        let attribute = Attribute(
            id: "a", title: "A", value: value, editable: true, valueKind: kind)
        let editor = AttributeEditorView(attribute: attribute, onSet: { _, _ in }, onFinish: {})
        _ = window(showing: editor)
        return row
    }

    func test_C_ATTR_09_extremeNumbersAreWrittenAndEditable() {
        for (value, kind) in Self.numbers {
            let row = showAndEdit(value, kind)
            XCTAssertFalse(row.plainText.isEmpty, "\(value)")
        }
        XCTAssertEqual(showAndEdit(.double(.nan), .double).plainText, "nan")
        XCTAssertEqual(showAndEdit(.double(.infinity), .double).plainText, "inf")
        XCTAssertEqual(showAndEdit(.double(-.infinity), .double).plainText, "-inf")
        XCTAssertEqual(showAndEdit(.integer(.min), .integer).plainText, "\(Int64.min)")
        // Shown in the read-only field as written.
        let field = AppListViewTests.descendants(
            of: showAndEdit(.double(.nan), .double), identifier: AttributeEditorView.fieldIdentifier)
            .first as? NSTextField
        XCTAssertEqual(field?.stringValue, "nan")
    }

    func test_C_ATTR_09_extremeColoursAreShown() {
        for components: [Float] in [
            [.nan, 0, 0, 1], [0, .infinity, 0, 1], [-0.5, 0, 0, 1], [1.5, 2, 3, 1],
            [0.5, 0.5, 0.5, .nan], [0.5, 0.5, 0.5, -1], [0.5, 0.5, 0.5, 4],
        ] {
            let color = Color(
                red: components[0], green: components[1], blue: components[2], alpha: components[3])
            let row = showAndEdit(.color(color), .color)
            XCTAssertNotNil(
                AppListViewTests.firstDescendant(of: row) { $0 is NSColorWell }, "the well is shown")
            if components.prefix(3).contains(where: { !$0.isFinite || $0 < 0 || $0 > 1 }) {
                XCTAssertNil(AttributeText.hexRGB(of: color), "not written as a hexadecimal code")
            }
        }
    }

    func test_C_ATTR_09_enumerationsOutOfRangeHugeAndEmpty() {
        let many = (0..<10_000).map { "case \($0)" }
        let values: [EnumValue] = [
            EnumValue(value: 99, cases: ["a", "b"], caseName: nil, caseValues: [0, 1]),
            EnumValue(value: -1, cases: ["a", "b"], caseName: nil, caseValues: [0, 1]),
            EnumValue(value: .max, cases: ["a"], caseName: nil, caseValues: [0]),
            EnumValue(
                value: 5_000, cases: many, caseName: "case 5000",
                caseValues: (0..<10_000).map(Int64.init)),
            EnumValue(value: 0, cases: [], caseName: nil, caseValues: []),
        ]
        for value in values {
            let start = ContinuousClock.now
            let row = showAndEdit(.enumeration(value), .enumeration)
            XCTAssertFalse(row.plainText.isEmpty)
            let took = ContinuousClock.now - start
            print("C-ATTR-09: an enumeration of \(value.cases.count) cases took \(took)")
        }
    }

    /// A string of 1 MiB is shown whole in its field of four lines, which scrolls through it.
    func test_C_ATTR_09_aLongStringIsShownWholeAndScrolls() throws {
        let long = String(repeating: "abcdefghij", count: 104_858)  // a little over 1 MiB
        let start = ContinuousClock.now
        let row = showAndEdit(.string(long), .string)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(10), "a generous bound")
        XCTAssertEqual(row.plainText, long, "Copy Value copies the whole of it")
        let area = try XCTUnwrap(
            AppListViewTests.firstDescendant(of: row) { $0 is AttributeTextArea } as? AttributeTextArea)
        XCTAssertEqual(area.textView.string, long)
        XCTAssertEqual(area.shownLines, AttributeTextArea.maximumLines)
    }

    /// A number that is not finite is shown as it is, and can only be typed over.
    @MainActor
    func test_C_ATTR_09_aNonFiniteValueCanOnlyBeTypedOver() {
        for start in [Double.nan, .infinity, -.infinity] {
            let field = NumberFieldView(letter: "X", isInteger: false)
            var sent: [Double] = []
            field.onSet = { sent.append($0) }
            field.show(start)
            XCTAssertEqual(field.field.stringValue, AttributeText.number(start))
            XCTAssertEqual(field.commit("8"), .accepted)
            XCTAssertEqual(sent, [8], "\(start)")
        }
    }
}
