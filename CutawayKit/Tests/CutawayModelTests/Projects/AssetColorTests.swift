import CoreGraphics
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-SRC-04: a colour set's colours as they are compared, and the sets an attribute's colour
/// is.
final class AssetColorTests: XCTestCase {
    private typealias Entry = ColorSet.Entry

    private func entry(
        _ components: [String: String], space: String? = "srgb", luminosity: String? = nil,
        highContrast: Bool = false, idiom: String = "universal"
    ) -> Entry {
        var appearances = luminosity.map { [Entry.Appearance(appearance: "luminosity", value: $0)] } ?? []
        if highContrast { appearances.append(.init(appearance: "contrast", value: "high")) }
        return Entry(
            idiom: idiom, appearances: appearances, colorSpace: space, components: components,
            systemReference: nil)
    }

    private func rgb(_ red: String, _ green: String, _ blue: String, alpha: String = "1.000") -> [String: String] {
        ["red": red, "green": green, "blue": blue, "alpha": alpha]
    }

    private func set(_ name: String, _ entries: Entry...) -> ColorSet {
        ColorSet(name: name, file: "\(name).colorset/Contents.json", entries: entries)
    }

    private static let blue = Color(red: 30 / 255, green: 107 / 255, blue: 1, alpha: 1)

    // MARK: - Reading

    func test_C_SRC_04_theThreeWaysOfWritingComponentsReadAlike() {
        let expected = RoundedColor(Self.blue)
        XCTAssertEqual(AssetColor.color(of: entry(rgb("0.118", "0.420", "1.000"))), expected)
        XCTAssertEqual(AssetColor.color(of: entry(rgb("30", "107", "255"))), expected)
        XCTAssertEqual(AssetColor.color(of: entry(rgb("0x1E", "0x6B", "0xFF"))), expected)
        // Alpha is a decimal even when it is a whole number.
        XCTAssertEqual(AssetColor.color(of: entry(rgb("30", "107", "255", alpha: "1"))), expected)
        XCTAssertEqual(AssetColor.component("0", isAlpha: true), 0)
        XCTAssertEqual(AssetColor.component("1", isAlpha: false), 1.0 / 255)
    }

    func test_C_SRC_04_componentsThatDoNotReadLeaveTheEntryOut() {
        for bad in ["", "red", "0xZZ", "256", "-1", "nan"] {
            XCTAssertNil(AssetColor.color(of: entry(rgb(bad, "0", "0"))), bad)
        }
        XCTAssertNil(AssetColor.color(of: entry(["red": "0", "green": "0"])), "a missing component")
        XCTAssertNil(AssetColor.color(of: entry(rgb("0", "0", "0"), space: "extended-linear-srgb")))
    }

    func test_C_SRC_04_everyColorSpaceIsConvertedToSRGBAndClamped() throws {
        // sRGB, and no colour space at all, are as written.
        XCTAssertEqual(AssetColor.color(of: entry(rgb("0x1E", "0x6B", "0xFF"), space: nil)), RoundedColor(Self.blue))
        // Display P3, by what CoreGraphics makes of it.
        let p3 = try XCTUnwrap(CGColor(
            colorSpace: try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)),
            components: [0.2, 0.4, 0.8, 1]))
        let srgb = try XCTUnwrap(p3.converted(
            to: try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedSRGB)), intent: .defaultIntent, options: nil)?
            .components)
        let expected = RoundedColor(
            red: Double(srgb[0]), green: Double(srgb[1]), blue: Double(srgb[2]), alpha: Double(srgb[3]))
        XCTAssertEqual(AssetColor.color(of: entry(rgb("0.200", "0.400", "0.800"), space: "display-p3")), expected)
        XCTAssertNotEqual(expected, RoundedColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1), "P3 is not sRGB")
        // Gray: white and alpha.
        let gray = AssetColor.color(of: entry(["white": "0.500", "alpha": "1.000"], space: "gray-gamma-22"))
        XCTAssertNotNil(gray)
        XCTAssertEqual(gray?.red, gray?.green)
        XCTAssertEqual(gray?.green, gray?.blue)
        XCTAssertEqual(
            AssetColor.color(of: entry(["white": "1.000", "alpha": "0.500"], space: "extended-gray")),
            RoundedColor(red: 1, green: 1, blue: 1, alpha: 0.5))
        // Extended sRGB beyond 0 to 1 is clamped, as the server clamps (P-ATTR-04).
        XCTAssertEqual(
            AssetColor.color(of: entry(rgb("1.200", "-0.100", "0.500"), space: "extended-srgb")),
            RoundedColor(red: 1, green: 0, blue: 0.5, alpha: 1))
    }

    // MARK: - Matching

    func test_C_SRC_04_oneUnitOfEightBitsApartIsNoMatch() {
        let lookup = ColorAssetLookup([set("Blue", entry(rgb("30", "107", "255")))])
        XCTAssertEqual(lookup.matches(Self.blue), [AssetColorMatch(name: "Blue", appearance: .any)])
        var off = Self.blue
        off.green = 108 / 255
        XCTAssertEqual(lookup.matches(off), [])
    }

    func test_C_SRC_04_theAppearanceThatMatchedIsNamed() {
        let lookup = ColorAssetLookup([
            set("Brand", entry(rgb("0", "0", "0")), entry(rgb("30", "107", "255"), luminosity: "dark")),
            set("Both", entry(rgb("30", "107", "255")), entry(rgb("30", "107", "255"), luminosity: "dark")),
        ])
        XCTAssertEqual(
            lookup.matches(Self.blue),
            [AssetColorMatch(name: "Both", appearance: .any), AssetColorMatch(name: "Brand", appearance: .dark)])
    }

    func test_C_SRC_04_aDynamicColorMustMatchInBothAppearances() {
        let light = Self.blue
        let dark = Color(red: 91 / 255, green: 231 / 255, blue: 1, alpha: 1)
        let both = AppearanceColors(light: light, dark: dark)
        let lookup = ColorAssetLookup([
            set("Brand", entry(rgb("30", "107", "255")), entry(rgb("91", "231", "255"), luminosity: "dark")),
            set("HalfLight", entry(rgb("30", "107", "255")), entry(rgb("0", "0", "0"), luminosity: "dark")),
            // No light colour: any stands for it.
            set("Explicit", entry(rgb("1", "1", "1")), entry(rgb("30", "107", "255"), luminosity: "light"),
                entry(rgb("91", "231", "255"), luminosity: "dark")),
        ])
        XCTAssertEqual(
            lookup.matches(light, appearanceColors: both),
            [AssetColorMatch(name: "Brand", appearance: nil), AssetColorMatch(name: "Explicit", appearance: nil)])
        XCTAssertEqual(
            lookup.matches(light, appearanceColors: AppearanceColors(light: light, dark: .zero)), [],
            "only half matches")
    }

    func test_C_SRC_04_highContrastAndSystemReferencesAreNotCompared() {
        var system = entry([:])
        system.systemReference = "systemBlueColor"
        let lookup = ColorAssetLookup([
            set("Contrast", entry(rgb("30", "107", "255"), highContrast: true)),
            set("System", system),
        ])
        XCTAssertEqual(lookup.matches(Self.blue), [])
    }

    func test_C_SRC_04_severalSetsComeInTheOrderOfTheirNames() {
        let lookup = ColorAssetLookup([
            set("b/Blue", entry(rgb("30", "107", "255"))),
            set("Accent", entry(rgb("30", "107", "255"), idiom: "ipad")),
            set("a", entry(rgb("30", "107", "255"))),
        ])
        XCTAssertEqual(lookup.matches(Self.blue).map(\.name), ["Accent", "a", "b/Blue"])
    }
}
