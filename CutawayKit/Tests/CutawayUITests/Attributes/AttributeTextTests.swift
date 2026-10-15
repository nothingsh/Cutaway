import CutawayWire
import XCTest

@testable import CutawayUI

/// How every kind of attribute value reads in the panel (C-ATTR-02), and what stands in for a
/// missing title (C-WIRE-04).
final class AttributeTextTests: XCTestCase {
    func test_C_ATTR_02_numbersWithoutAPlainValue() {
        XCTAssertEqual(AttributeText.number(-0.0), "0")
        XCTAssertEqual(AttributeText.number(-0.00001), "0", "rounds to zero, shown without a sign")
        XCTAssertEqual(AttributeText.number(.nan), "nan")
        XCTAssertEqual(AttributeText.number(.infinity), "inf")
        XCTAssertEqual(AttributeText.number(-.infinity), "-inf")
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
