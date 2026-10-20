import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayUI

/// A colour that resolves differently in light and dark (C-ATTR-25, P-ATTR-17): a swatch in two
/// halves, the half in effect underlined, and both codes in the tooltip. The halves are checked
/// in the row as drawn off screen.
@MainActor
final class DualColorTests: XCTestCase {
    private static let blue = Color(red: 0, green: 0.47843137, blue: 1, alpha: 1)
    private static let darkBlue = Color(red: 0.039215688, green: 0.5176471, blue: 1, alpha: 1)

    private static func layerThree(_ groups: [AttributeGroup]? = nil) throws -> [Attribute] {
        try (groups ?? Fixtures.attributes(of: 3, scenario: "layer-details")).flatMap(\.attributes)
    }

    private static func attribute(_ id: String, in attributes: [Attribute]) throws -> Attribute {
        try XCTUnwrap(attributes.first { $0.id == id }, id)
    }

    /// A read-only row of the attribute, as the panel shows it once the names are in, in a
    /// window that is never shown, laid out 300 points wide.
    private func row(_ attribute: Attribute) -> (AttributeRowView, NSWindow) {
        let row = AttributeRowView(
            title: attribute.title ?? "", value: attribute.value, kind: attribute.valueKind)
        row.show(attribute.value, names: ValueNames(attribute, index: nil))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 60), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = row
        window.layoutIfNeeded()
        return (row, window)
    }

    private func hex(in view: NSView) throws -> AttributeEditField {
        try XCTUnwrap(AppListViewTests.descendants(
            of: view, identifier: AttributeEditorView.hexIdentifier).first as? AttributeEditField)
    }

    private func swatch(in view: NSView) throws -> ColorSwatch {
        try XCTUnwrap(AppListViewTests.firstDescendant(of: view) { $0 is ColorSwatch } as? ColorSwatch)
    }

    /// The row drawn off screen, and the colour at a point of one of its views, as sRGB.
    private func color(
        at point: NSPoint, in view: NSView, of row: NSView
    ) throws -> NSColor {
        let rep = try XCTUnwrap(row.bitmapImageRepForCachingDisplay(in: row.bounds))
        row.cacheDisplay(in: row.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / row.bounds.width
        let inRow = view.convert(point, to: row)
        let fromTop = row.isFlipped ? inRow.y : row.bounds.height - inRow.y
        let color = try XCTUnwrap(rep.colorAt(x: Int(inRow.x * scale), y: Int(fromTop * scale)))
        return try XCTUnwrap(color.usingColorSpace(.sRGB))
    }

    /// A point across the swatch's square, in its middle, or just under it.
    private static func point(_ across: CGFloat, of swatch: ColorSwatch, under: Bool = false) -> NSPoint {
        let square = swatch.square
        let x = square.minX + square.width * across
        guard under else { return NSPoint(x: x, y: square.midY) }
        return NSPoint(x: x, y: swatch.isFlipped ? square.maxY + 2 : square.minY - 2)
    }

    private func isClose(_ a: NSColor, _ b: NSColor, within: CGFloat = 1 / 255) -> Bool {
        abs(a.redComponent - b.redComponent) <= within
            && abs(a.greenComponent - b.greenComponent) <= within
            && abs(a.blueComponent - b.blueComponent) <= within
    }

    // MARK: - Tooltip

    func test_C_ATTR_25_aDynamicColourNamesBothAppearancesInItsTooltip() throws {
        let tint = try Self.attribute("view.tintColor", in: Self.layerThree())
        XCTAssertEqual(tint.appearanceColors, AppearanceColors(light: Self.blue, dark: Self.darkBlue))
        let (row, window) = row(tint)
        // The code, as for any named colour, then the two appearances.
        XCTAssertEqual(try hex(in: row).toolTip, "#007AFF · Light 007AFF · Dark 0A84FF")
        withExtendedLifetime(window) {}
    }

    func test_C_ATTR_25_aDynamicColourWithoutANameStillSaysBoth() throws {
        var tint = try Self.attribute("view.tintColor", in: Self.layerThree())
        tint.systemColorName = nil
        tint.appearanceColors = AppearanceColors(
            light: Color(red: 0, green: 0, blue: 0, alpha: 0.5), dark: Color(red: 1, green: 1, blue: 1, alpha: 1))
        let (row, window) = row(tint)
        XCTAssertEqual(try hex(in: row).toolTip, "Light 000000 50% · Dark FFFFFF")
        withExtendedLifetime(window) {}
    }

    func test_C_ATTR_25_aStaticColourKeepsItsTooltip() throws {
        // A CGColor never has the two appearances; a 1.1 server sends none.
        let border = try Self.attribute("layer.borderColor", in: Self.layerThree())
        XCTAssertNil(border.appearanceColors)
        let (borderRow, borderWindow) = row(border)
        XCTAssertNil(try hex(in: borderRow).toolTip)
        XCTAssertNil(try swatch(in: borderRow).appearanceColors)

        let tint = try Self.attribute(
            "view.tintColor",
            in: Self.layerThree(Fixtures.withoutProtocol12(Fixtures.attributes(of: 3, scenario: "layer-details"))))
        let (tintRow, tintWindow) = row(tint)
        XCTAssertEqual(try hex(in: tintRow).toolTip, "#007AFF")
        XCTAssertNil(try swatch(in: tintRow).appearanceColors)
        withExtendedLifetime([borderWindow, tintWindow]) {}
    }

    // MARK: - Drawing

    func test_C_ATTR_25_theHalvesOfADynamicSwatchDiffer() throws {
        let tint = try Self.attribute("view.tintColor", in: Self.layerThree())
        let (row, window) = row(tint)
        let swatch = try swatch(in: row)
        let left = try color(at: Self.point(0.25, of: swatch), in: swatch, of: row)
        let right = try color(at: Self.point(0.75, of: swatch), in: swatch, of: row)
        // A read-only value is drawn faint, so the halves are compared with each other: the
        // dark blue has more red and green than the light one.
        XCTAssertLessThan(left.redComponent + 2 / 255, right.redComponent, "left \(left), right \(right)")
        XCTAssertLessThan(left.greenComponent + 2 / 255, right.greenComponent)

        // A static colour is one block.
        var plain = tint
        plain.appearanceColors = nil
        let (plainRow, plainWindow) = self.row(plain)
        let plainSwatch = try self.swatch(in: plainRow)
        let plainLeft = try color(at: Self.point(0.25, of: plainSwatch), in: plainSwatch, of: plainRow)
        let plainRight = try color(at: Self.point(0.75, of: plainSwatch), in: plainSwatch, of: plainRow)
        XCTAssertTrue(isClose(plainLeft, plainRight), "\(plainLeft), \(plainRight)")
        withExtendedLifetime([window, plainWindow]) {}
    }

    func test_C_ATTR_25_theUnderlineMarksTheAppearanceInEffect() throws {
        let black = Color(red: 0, green: 0, blue: 0, alpha: 1)
        let white = Color(red: 1, green: 1, blue: 1, alpha: 1)
        let grey = Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        var label = Attribute(
            id: "label.textColor", title: "Color", value: .color(white), valueKind: .color)
        label.appearanceColors = AppearanceColors(light: black, dark: white)
        let cases: [(AttributeValue, ColorSwatch.Half?)] = [
            (.color(white), .dark), (.color(black), .light), (.color(grey), nil),
        ]
        for (value, expected) in cases {
            label.value = value
            let (row, window) = row(label)
            let swatch = try swatch(in: row)
            XCTAssertEqual(swatch.underlined, expected, "\(value)")
            let left = try color(at: Self.point(0.25, of: swatch, under: true), in: swatch, of: row)
            let right = try color(at: Self.point(0.75, of: swatch, under: true), in: swatch, of: row)
            XCTAssertEqual(left != right, expected != nil, "a line under one half only: \(value)")
            withExtendedLifetime(window) {}
        }
    }

    // MARK: - Editing

    func test_C_ATTR_25_editingWritesOnlyTheValueAndTheReplyIsOneBlock() throws {
        var sent: [AttributeValue?] = []
        let tint = try Self.attribute("view.tintColor", in: Self.layerThree())
        let editor = AttributeEditorView(attribute: tint, onSet: { value, _ in sent.append(value) })
        editor.show(tint.value, names: ValueNames(tint, index: nil))
        let swatch = try swatch(in: editor)
        XCTAssertNotNil(swatch.appearanceColors)
        let well = try XCTUnwrap(AppListViewTests.descendants(
            of: editor, identifier: AttributeEditorView.wellIdentifier).first as? NSColorWell)
        well.color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        editor.colorChanged(well)
        XCTAssertEqual(sent.count, 1)
        guard case .color(let picked)?? = sent.first else {
            XCTFail("a colour")
            return
        }
        XCTAssertEqual(picked.red, 0.2, accuracy: 0.001)
        // The app answers with the colour it now has, a static one: no halves.
        var reply = tint
        reply.value = .color(picked)
        reply.appearanceColors = nil
        reply.systemColorName = nil
        editor.show(reply.value, names: ValueNames(reply, index: nil))
        XCTAssertNil(swatch.appearanceColors)
        XCTAssertNil(swatch.underlined)
        editor.colorPause?.cancel()
    }
}
