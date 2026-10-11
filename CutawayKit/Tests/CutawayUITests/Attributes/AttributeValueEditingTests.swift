import CutawayWire
import XCTest

@testable import CutawayUI

/// The reading and arithmetic of the attribute editors, without the editors: C-ATTR-05,
/// C-ATTR-07, C-ATTR-09.
final class AttributeValueEditingTests: XCTestCase {
    // MARK: - Components

    func test_C_ATTR_05_aValueComesApartIntoItsComponentsAndBack() {
        let rect = AttributeValue.rect(
            Rect(origin: Point(x: 1, y: 2), size: Size(width: 3, height: 4)))
        XCTAssertEqual(AttributeValueEditing.components(of: rect), [1, 2, 3, 4])
        XCTAssertEqual(AttributeValueEditing.value(.rect, [1, 2, 300, 4]), .rect(
            Rect(origin: Point(x: 1, y: 2), size: Size(width: 300, height: 4))))
        XCTAssertEqual(
            AttributeValueEditing.components(of: .point(Point(x: 1, y: 2))), [1, 2])
        XCTAssertEqual(
            AttributeValueEditing.components(of: .size(Size(width: 0, height: -3))), [0, -3])
        XCTAssertEqual(
            AttributeValueEditing.components(
                of: .insets(Insets(top: 8, left: 7, bottom: 6, right: 5))),
            [8, 7, 6, 5])
        XCTAssertEqual(
            AttributeValueEditing.value(.insets, [8, 7, 6, 5]),
            .insets(Insets(top: 8, left: 7, bottom: 6, right: 5)))
        XCTAssertNil(AttributeValueEditing.components(of: .double(1)))
        XCTAssertNil(AttributeValueEditing.components(of: nil))
        XCTAssertNil(AttributeValueEditing.value(.double, [1]))
    }

    func test_C_ATTR_05_aTransformIsItsSixteenEntriesInRows() {
        let entries = AttributeValueEditing.entries(of: .identity)
        XCTAssertEqual(entries, [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
        var changed = entries
        changed[12] = 10
        let transform = AttributeValueEditing.transform(changed)
        XCTAssertEqual(transform.m41, 10)
        XCTAssertEqual(AttributeValueEditing.components(of: .transform(transform)), changed)
    }

    // MARK: - Colours

    func test_C_ATTR_05_aColourIsWrittenInHex() {
        XCTAssertEqual(
            AttributeValueEditing.hexRGBA(of: Color(red: 1, green: 0, blue: 0, alpha: 0.5)),
            "#FF000080")
        XCTAssertEqual(
            AttributeValueEditing.hexRGBA(of: Color(red: 1, green: 0.5, blue: 0, alpha: 1)),
            "#FF8000")
        XCTAssertEqual(AttributeText.hexRGB(of: Color(red: 1, green: 0.5, blue: 0, alpha: 0.5)),
                       "#FF8000", "the RGB code leaves the opacity out")
    }

    func test_C_ATTR_09_aColourBeyondSRGBHasNoHex() {
        XCTAssertNil(
            AttributeValueEditing.hexRGBA(of: Color(red: 1.01, green: 0, blue: 0, alpha: 1)))
        XCTAssertNil(
            AttributeValueEditing.hexRGBA(of: Color(red: 0.5, green: 0.5, blue: 0.5, alpha: -1)))
    }

    func test_C_ATTR_05_aColourIsReadFromHex() {
        XCTAssertNil(AttributeValueEditing.color(fromHex: "zz"))
        XCTAssertNil(AttributeValueEditing.color(fromHex: "#12345"))
        XCTAssertEqual(
            AttributeValueEditing.color(fromHex: "#3366CC"),
            Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        XCTAssertEqual(
            AttributeValueEditing.color(fromHex: " 33669980 "),
            Color(red: 0.2, green: 0.4, blue: 0.6, alpha: Float(0x80) / 255))
    }

    // MARK: - Numbers

    func test_C_ATTR_05_onlyAFiniteNumberIsRead() {
        for text in ["abc", "inf", "nan", ""] {
            XCTAssertNil(AttributeValueEditing.number(typed: text, isInteger: false), text)
        }
        XCTAssertEqual(AttributeValueEditing.number(typed: " 0.25 ", isInteger: false), 0.25)
        XCTAssertNil(AttributeValueEditing.number(typed: "2.5", isInteger: true), "not an integer")
        XCTAssertEqual(AttributeValueEditing.number(typed: "3", isInteger: true), 3)
    }

    func test_C_ATTR_05_anIntegerBeyondWhatCanBeSentExactlyIsNotRead() {
        XCTAssertNil(AttributeValueEditing.number(typed: "9223372036854775807", isInteger: true))
        XCTAssertNil(AttributeValueEditing.number(typed: "9007199254740993", isInteger: true))
        XCTAssertEqual(
            AttributeValueEditing.number(typed: "9007199254740992", isInteger: true),
            9_007_199_254_740_992)
    }

    func test_C_ATTR_07_theStepFollowsTheNumber() {
        func step(_ start: Double, integer: Bool = false, tenth: Bool = false, tenfold: Bool = false)
            -> Double
        {
            AttributeValueEditing.step(
                from: start, isInteger: integer, tenth: tenth, tenfold: tenfold)
        }
        XCTAssertEqual(step(1), 0.01)
        XCTAssertEqual(step(-0.5), 0.01)
        XCTAssertEqual(step(12), 1)
        XCTAssertEqual(step(0.5, integer: true), 1)
        XCTAssertEqual(step(12, tenth: true), 0.1)
        XCTAssertEqual(step(12, tenfold: true), 10)
        XCTAssertEqual(step(1, tenth: true), 0.001)
        XCTAssertEqual(step(5, integer: true, tenth: true), 1)
        XCTAssertEqual(step(5, integer: true, tenfold: true), 10)
    }

    func test_C_ATTR_07_aDragIsRoundedToItsStep() {
        XCTAssertEqual(AttributeValueEditing.scrubbed(0.1, by: 20, step: 0.01), 0.3)
        XCTAssertEqual(AttributeValueEditing.scrubbed(1, by: -30, step: 0.01), 0.7)
        XCTAssertEqual(AttributeValueEditing.scrubbed(12, by: 3, step: 10), 42)
    }
}
