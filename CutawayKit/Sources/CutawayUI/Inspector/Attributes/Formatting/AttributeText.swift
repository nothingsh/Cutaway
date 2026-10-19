import CutawayWire
import Foundation

/// How attributes read in the attribute panel (C-ATTR-02). Every member of `AttributeValue`
/// has a way to be shown; a nil value reads as "None", and its row stays.
enum AttributeText {
    /// The lines that show a value: one, except for a transform that is not the identity,
    /// which shows its matrix a row per line.
    static func lines(of value: AttributeValue?) -> [String] {
        guard let value else { return [localized("attributes.value.none")] }
        switch value {
        case .bool(let bool):
            return [bool ? localized("attributes.value.yes") : localized("attributes.value.no")]
        case .integer(let integer):
            return [String(integer)]
        case .double(let double):
            return [number(double)]
        case .string(let string):
            return [string]
        case .color(let color):
            return [[color.red, color.green, color.blue, color.alpha]
                .map { number(Double($0)) }.joined(separator: " ")]
        case .point(let point):
            return ["\(number(point.x)), \(number(point.y))"]
        case .size(let size):
            return ["\(number(size.width)) × \(number(size.height))"]
        case .rect(let rect):
            return [[rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
                .map(number).joined(separator: ", ")]
        case .insets(let insets):
            return ["top \(number(insets.top)), left \(number(insets.left)), "
                + "bottom \(number(insets.bottom)), right \(number(insets.right))"]
        case .transform(let transform):
            guard transform != .identity else { return [localized("attributes.value.identity")] }
            let t = transform
            return [
                [t.m11, t.m12, t.m13, t.m14], [t.m21, t.m22, t.m23, t.m24],
                [t.m31, t.m32, t.m33, t.m34], [t.m41, t.m42, t.m43, t.m44],
            ].map { $0.map(number).joined(separator: "  ") }
        case .enumeration(let enumeration):
            return [caseName(of: enumeration)]
        case .references(let references):
            // Names until C-ATTR-28 makes them chips; no objects reads as no value.
            guard !references.isEmpty else { return [localized("attributes.value.none")] }
            return [references.map(\.displayClassName).joined(separator: ", ")]
        }
    }

    /// "#RRGGBB" for a colour whose components are all within 0 to 1; nil for one in
    /// extended sRGB, which a hexadecimal code cannot write.
    static func hexRGB(of color: Color) -> String? {
        let components = [color.red, color.green, color.blue]
        guard components.allSatisfy({ $0 >= 0 && $0 <= 1 }) else { return nil }
        return "#" + components.map { String(format: "%02X", Int(($0 * 255).rounded())) }
            .joined()
    }

    /// "α 0.5" for a colour that is not opaque, nil for one that is.
    static func alpha(of color: Color) -> String? {
        color.alpha >= 1 ? nil : "α " + number(Double(color.alpha))
    }

    /// The lines of a value as one string.
    static func text(of value: AttributeValue?) -> String {
        lines(of: value).joined(separator: "\n")
    }

    /// A number with at most four decimals and no trailing zeros. Zero has no sign.
    static func number(_ value: Double) -> String {
        if value.isNaN { return "nan" }
        if value.isInfinite { return value < 0 ? "-inf" : "inf" }
        var text = String(format: "%.4f", value)
        // "%.4f" always writes a point: the zeros removed are decimals.
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    /// A proportion as a percentage (C-ATTR-20): 1 is "100", 0.375 is "37.5", with at most two
    /// decimals. A number that is not finite is written as `number` writes it.
    static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return number(fraction) }
        return number((fraction * 10000).rounded() / 100)
    }

    /// A number as its unit reads (C-ATTR-20): "40%" for a proportion, "8 pt" for points, the
    /// number alone otherwise.
    static func number(_ value: Double, unit: AttributeUnit) -> String {
        switch unit {
        case .fraction: percent(value) + "%"
        case .points: number(value) + " pt"
        case .unspecified: number(value)
        }
    }

    /// A value as a sentence names it (C-ATTR-21): a number with its unit, anything else as
    /// `text(of:)` writes it.
    static func text(of value: AttributeValue?, unit: AttributeUnit) -> String {
        switch value {
        case .double(let double): number(double, unit: unit)
        case .integer(let integer) where unit == .points: number(Double(integer), unit: unit)
        default: text(of: value)
        }
    }

    /// The name of a UIKit system colour as people read it (C-ATTR-22): the words of the
    /// property's name, each capitalised: "systemBlue" is "System Blue".
    static func systemColorName(_ name: String) -> String {
        var words: [String] = []
        for character in name {
            if character.isUppercase || words.isEmpty {
                words.append(String(character).uppercased())
            } else {
                words[words.count - 1].append(character)
            }
        }
        return words.joined(separator: " ")
    }

    /// What a transform does, in a line (C-ATTR-19): "Identity"; for a 2D one of moving,
    /// turning and scaling, the parts it has, as "Rotate −4° · Scale 1.02 · Move 10, −4";
    /// otherwise "Custom" (3D, perspective, shear).
    static func summary(of t: Transform3D) -> String {
        guard t != .identity else { return localized("attributes.value.identity") }
        let flat = [t.m13, t.m14, t.m23, t.m24, t.m31, t.m32, t.m34, t.m43].allSatisfy { $0 == 0 }
            && t.m33 == 1 && t.m44 == 1
        let entries = [t.m11, t.m12, t.m21, t.m22, t.m41, t.m42]
        let tolerance = 1e-6
        // The two axes stay at right angles unless there is shear.
        guard flat, entries.allSatisfy(\.isFinite), abs(t.m11 * t.m21 + t.m12 * t.m22) < tolerance
        else { return localized("attributes.value.custom") }
        let scaleX = (t.m11 * t.m11 + t.m12 * t.m12).squareRoot()
        guard scaleX > tolerance else { return localized("attributes.value.custom") }
        let scaleY = (t.m11 * t.m22 - t.m12 * t.m21) / scaleX
        let degrees = (atan2(t.m12, t.m11) * 180 / .pi * 10).rounded() / 10
        var parts: [String] = []
        if degrees != 0 { parts.append(localized("attributes.value.rotate", number(degrees))) }
        if abs(scaleX - 1) > tolerance || abs(scaleY - 1) > tolerance {
            parts.append(abs(scaleX - scaleY) < tolerance
                ? localized("attributes.value.scale", number(scaleX))
                : localized("attributes.value.scaleXY", number(scaleX), number(scaleY)))
        }
        if t.m41 != 0 || t.m42 != 0 {
            parts.append(localized("attributes.value.move", number(t.m41), number(t.m42)))
        }
        return parts.isEmpty ? localized("attributes.value.identity") : parts.joined(separator: " · ")
    }

    /// An object's address as the panel writes it (C-ATTR-11): "0x" and lowercase hexadecimal,
    /// not padded.
    static func address(_ address: UInt64) -> String {
        "0x" + String(address, radix: 16)
    }

    /// What a group or an attribute is called: its title as the app sent it, or its ID when
    /// it has no title (C-WIRE-04).
    static func title(_ title: String?, id: String?) -> String {
        title ?? id ?? ""
    }

    /// The name of the current case: as sent, or looked up among the cases, or the value.
    private static func caseName(of enumeration: EnumValue) -> String {
        if let name = enumeration.caseName { return name }
        if enumeration.value >= 0, enumeration.value < Int64(enumeration.cases.count) {
            return enumeration.cases[Int(enumeration.value)]
        }
        return String(enumeration.value)
    }
}
