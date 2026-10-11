import CutawayWire
import XCTest

@testable import CutawayUI

/// How every kind of attribute value reads in the panel (C-ATTR-02), and what stands in for a
/// missing title (C-WIRE-04).
final class AttributeTextTests: XCTestCase {
    /// "None", which an empty string does not read as (C-ATTR-02 as changed on 2026-10-04).
    func test_C_ATTR_02_aNilValueReadsAsNone() {
        XCTAssertEqual(AttributeText.lines(of: nil), ["None"])
        XCTAssertEqual(AttributeText.text(of: nil), "None")
        XCTAssertNotEqual(AttributeText.text(of: .string("")), AttributeText.text(of: nil))
    }

    func test_C_ATTR_02_booleansIntegersAndStrings() {
        XCTAssertEqual(AttributeText.text(of: .bool(true)), "Yes")
        XCTAssertEqual(AttributeText.text(of: .bool(false)), "No")
        XCTAssertEqual(AttributeText.text(of: .integer(-3)), "-3")
        XCTAssertEqual(AttributeText.text(of: .integer(.min)), "-9223372036854775808")
        XCTAssertEqual(AttributeText.text(of: .string("Hello")), "Hello")
        XCTAssertEqual(AttributeText.text(of: .string("")), "")
    }

    func test_C_ATTR_02_numbersHaveAtMostFourDecimals() {
        XCTAssertEqual(AttributeText.text(of: .double(0.5)), "0.5")
        XCTAssertEqual(AttributeText.number(1), "1")
        XCTAssertEqual(AttributeText.number(100), "100")
        XCTAssertEqual(AttributeText.number(196.5), "196.5")
        XCTAssertEqual(AttributeText.number(-3), "-3")
        XCTAssertEqual(AttributeText.number(0.8660254037844387), "0.866")
        XCTAssertEqual(AttributeText.number(2.71828), "2.7183")
        XCTAssertEqual(AttributeText.number(1e20), "100000000000000000000")
    }

    func test_C_ATTR_02_numbersWithoutAPlainValue() {
        XCTAssertEqual(AttributeText.number(-0.0), "0")
        XCTAssertEqual(AttributeText.number(-0.00001), "0", "rounds to zero, shown without a sign")
        XCTAssertEqual(AttributeText.number(.nan), "nan")
        XCTAssertEqual(AttributeText.number(.infinity), "inf")
        XCTAssertEqual(AttributeText.number(-.infinity), "-inf")
    }

    func test_C_ATTR_02_geometry() {
        XCTAssertEqual(AttributeText.text(of: .point(Point(x: 196.5, y: 120))), "196.5, 120")
        XCTAssertEqual(AttributeText.text(of: .size(Size(width: 0, height: -3))), "0 × -3")
        XCTAssertEqual(
            AttributeText.text(of: .rect(Rect(
                origin: Point(x: 96.5, y: 108), size: Size(width: 200, height: 24)))),
            "96.5, 108, 200, 24")
        XCTAssertEqual(
            AttributeText.text(of: .insets(Insets(top: 8, left: 16, bottom: 8, right: 16))),
            "top 8, left 16, bottom 8, right 16")
    }

    func test_C_ATTR_02_aColourReadsAsItsComponents() {
        XCTAssertEqual(
            AttributeText.text(of: .color(Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))),
            "0.2 0.4 0.6 1")
        XCTAssertEqual(AttributeText.text(of: .color(Color(red: 0, green: 0, blue: 0, alpha: 1))),
                       "0 0 0 1")
    }

    func test_C_ATTR_02_theIdentityReadsAsAWord() {
        XCTAssertEqual(AttributeText.lines(of: .transform(.identity)), ["Identity"])
    }

    func test_C_ATTR_02_anyOtherTransformTakesFourLines() {
        var rotated = Transform3D.identity
        rotated.m11 = 0.8660254037844387
        rotated.m12 = 0.5
        rotated.m21 = -0.5
        rotated.m22 = 0.8660254037844387
        XCTAssertEqual(AttributeText.lines(of: .transform(rotated)), [
            "0.866  0.5  0  0",
            "-0.5  0.866  0  0",
            "0  0  1  0",
            "0  0  0  1",
        ])
        XCTAssertEqual(
            AttributeText.text(of: .transform(rotated)),
            "0.866  0.5  0  0\n-0.5  0.866  0  0\n0  0  1  0\n0  0  0  1")

        var translated = Transform3D.identity
        translated.m42 = 100
        XCTAssertEqual(AttributeText.lines(of: .transform(translated)).count, 4,
                       "one entry off the identity is enough")
    }

    func test_C_ATTR_02_aVeryLargeNumberIsWrittenOut() {
        let text = AttributeText.text(of: .double(1e300))
        XCTAssertFalse(text.contains("e"), text)
        XCTAssertEqual(text.count, 301, "every digit, no decimals")
    }

    func test_C_ATTR_02_aTransformWithNaNShowsItsMatrix() {
        var broken = Transform3D.identity
        broken.m11 = .nan
        XCTAssertEqual(AttributeText.lines(of: .transform(broken)), [
            "nan  0  0  0",
            "0  1  0  0",
            "0  0  1  0",
            "0  0  0  1",
        ])
    }

    func test_C_ATTR_02_anEnumReadsAsTheNameOfItsCase() {
        let cases = ["left", "center", "right"]
        XCTAssertEqual(
            AttributeText.text(of: .enumeration(EnumValue(value: 1, cases: cases, caseName: "center"))),
            "center")
        // Without a name, the name of the case at the value; without that, the value.
        XCTAssertEqual(
            AttributeText.text(of: .enumeration(EnumValue(value: 2, cases: cases, caseName: nil))),
            "right")
        XCTAssertEqual(
            AttributeText.text(of: .enumeration(EnumValue(value: 7, cases: cases, caseName: nil))),
            "7")
        XCTAssertEqual(
            AttributeText.text(of: .enumeration(EnumValue(value: -1, cases: cases, caseName: nil))),
            "-1")
    }

    func test_C_WIRE_04_aMissingTitleFallsBackToTheID() {
        XCTAssertEqual(AttributeText.title("Opacity", id: "layer.opacity"), "Opacity")
        XCTAssertEqual(AttributeText.title(nil, id: "layer.opacity"), "layer.opacity")
        XCTAssertEqual(AttributeText.title(nil, id: nil), "")
        XCTAssertEqual(AttributeText.title("", id: "layer.opacity"), "", "an empty title is a title")
    }

    func test_C_ATTR_02_aColourReadsAsAHexadecimalCode() {
        XCTAssertEqual(AttributeText.hexRGB(of: Color(red: 1, green: 0.5, blue: 0, alpha: 1)), "#FF8000")
        XCTAssertEqual(AttributeText.hexRGB(of: Color(red: 0, green: 0, blue: 0, alpha: 0)), "#000000")
        // Extended sRGB and NaN have no code.
        XCTAssertNil(AttributeText.hexRGB(of: Color(red: 1.01, green: 0, blue: 0, alpha: 1)))
        XCTAssertNil(AttributeText.hexRGB(of: Color(red: -0.1, green: 0, blue: 0, alpha: 1)))
        XCTAssertNil(AttributeText.hexRGB(of: Color(red: .nan, green: 0, blue: 0, alpha: 1)))
        XCTAssertNil(AttributeText.alpha(of: Color(red: 0, green: 0, blue: 0, alpha: 1)))
        XCTAssertEqual(AttributeText.alpha(of: Color(red: 0, green: 0, blue: 0, alpha: 0.25)), "α 0.25")
    }
}
