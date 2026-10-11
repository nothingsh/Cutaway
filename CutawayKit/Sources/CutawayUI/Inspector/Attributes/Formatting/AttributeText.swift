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
