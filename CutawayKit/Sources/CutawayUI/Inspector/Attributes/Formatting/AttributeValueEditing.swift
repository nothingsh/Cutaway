import CutawayModel
import CutawayWire
import Foundation

/// The reading and arithmetic of the attribute editors (C-ATTR-05): a value taken apart into
/// numbers and put back together, a colour written and read as a hexadecimal code, and a
/// typed number. The editors keep what is on screen and when it is
/// sent.
enum AttributeValueEditing {
    // MARK: - Components

    /// The numbers of a point, size, rectangle, insets or transform, in the order the editor
    /// shows them, which is the protocol's (P-ATTR-09); nil for any other value.
    static func components(of value: AttributeValue?) -> [Double]? {
        guard let numbers = value?.numericComponents, numbers.count > 1 else { return nil }
        return numbers
    }

    static func value(_ kind: AttributeValueKind, _ components: [Double]) -> AttributeValue? {
        switch kind {
        case .point: return .point(Point(x: components[0], y: components[1]))
        case .size: return .size(Size(width: components[0], height: components[1]))
        case .rect:
            return .rect(Rect(
                origin: Point(x: components[0], y: components[1]),
                size: Size(width: components[2], height: components[3])))
        case .insets:
            return .insets(Insets(
                top: components[0], left: components[1], bottom: components[2],
                right: components[3]))
        default: return nil
        }
    }

    static func entries(of t: Transform3D) -> [Double] {
        [t.m11, t.m12, t.m13, t.m14, t.m21, t.m22, t.m23, t.m24,
         t.m31, t.m32, t.m33, t.m34, t.m41, t.m42, t.m43, t.m44]
    }

    static func transform(_ e: [Double]) -> Transform3D {
        Transform3D(
            m11: e[0], m12: e[1], m13: e[2], m14: e[3], m21: e[4], m22: e[5], m23: e[6],
            m24: e[7], m31: e[8], m32: e[9], m33: e[10], m34: e[11], m41: e[12], m42: e[13],
            m43: e[14], m44: e[15])
    }

    // MARK: - Colours

    /// "#RRGGBB", or "#RRGGBBAA" for a colour that is not opaque; nil for one in extended
    /// sRGB, which a hexadecimal code cannot write.
    static func hexRGBA(of color: Color) -> String? {
        guard let rgb = AttributeText.hexRGB(of: color) else { return nil }
        guard color.alpha < 1 else { return rgb }
        guard color.alpha >= 0 else { return nil }
        return rgb + String(format: "%02X", Int((color.alpha * 255).rounded()))
    }

    /// A colour from "#RRGGBB" or "#RRGGBBAA", the "#" optional. Six digits take `alpha`
    /// when it is given, the opacity the field shows beside them (C-ATTR-22), and otherwise
    /// make the colour opaque.
    static func color(fromHex text: String, keepingAlpha alpha: Float?) -> Color? {
        guard var color = color(fromHex: text) else { return nil }
        let digits = text.trimmingCharacters(in: .whitespaces).drop { $0 == "#" }
        if digits.count == 6, let alpha { color.alpha = alpha }
        return color
    }

    /// A colour from "#RRGGBB" or "#RRGGBBAA", the "#" optional.
    static func color(fromHex text: String) -> Color? {
        var digits = text.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        // Hex digits only: the integer parser would also take a sign.
        guard digits.count == 6 || digits.count == 8, digits.allSatisfy(\.isHexDigit),
              let packed = UInt32(digits, radix: 16)
        else { return nil }
        let full = digits.count == 6 ? packed << 8 | 0xFF : packed
        func component(_ shift: UInt32) -> Float { Float((full >> shift) & 0xFF) / 255 }
        return Color(red: component(24), green: component(16), blue: component(8), alpha: component(0))
    }

    // MARK: - Numbers

    /// What was typed, as a number: a finite one, or for an integer only one a Double holds
    /// exactly; otherwise why it is not one (C-ATTR-05).
    static func number(typed text: String, isInteger: Bool) -> Result<Double, LimitText.InputProblem> {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if isInteger {
            // Only an integer a Double holds exactly: it travels as one here.
            if let integer = Int64(trimmed) {
                let double = Double(integer)
                return Int64(exactly: double) == integer ? .success(double) : .failure(.tooLarge)
            }
            guard let double = Double(trimmed), double.isFinite else { return .failure(.notANumber) }
            return .failure(double.rounded() == double ? .tooLarge : .notWhole)
        } else {
            guard let double = Double(trimmed), double.isFinite else { return .failure(.notANumber) }
            return .success(double)
        }
    }
}
