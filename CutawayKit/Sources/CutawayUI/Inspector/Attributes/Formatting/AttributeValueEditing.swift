import CutawayWire
import Foundation

/// The reading and arithmetic of the attribute editors (C-ATTR-05, C-ATTR-07): a value taken
/// apart into numbers and put back together, a colour written and read as a hexadecimal code,
/// a typed number, and the steps of a drag. The editors keep what is on screen and when it is
/// sent.
enum AttributeValueEditing {
    // MARK: - Components

    /// The numbers of a point, size, rectangle, insets or transform, in the order the editor
    /// shows them; nil for any other value.
    static func components(of value: AttributeValue?) -> [Double]? {
        switch value {
        case .point(let point): return [point.x, point.y]
        case .size(let size): return [size.width, size.height]
        case .rect(let rect): return [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
        case .insets(let insets): return [insets.top, insets.left, insets.bottom, insets.right]
        case .transform(let transform): return entries(of: transform)
        default: return nil
        }
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

    /// A colour from "#RRGGBB" or "#RRGGBBAA", the "#" optional.
    static func color(fromHex text: String) -> Color? {
        var digits = text.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6 || digits.count == 8,
              let packed = UInt32(digits, radix: 16)
        else { return nil }
        let full = digits.count == 6 ? packed << 8 | 0xFF : packed
        func component(_ shift: UInt32) -> Float { Float((full >> shift) & 0xFF) / 255 }
        return Color(red: component(24), green: component(16), blue: component(8), alpha: component(0))
    }

    // MARK: - Numbers

    /// What was typed, as a number: a finite one, or for an integer only one a Double holds
    /// exactly; nil when it does not read as one (C-ATTR-05).
    static func number(typed text: String, isInteger: Bool) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if isInteger {
            // Only an integer a Double holds exactly: it travels as one here.
            return Int64(trimmed).flatMap { integer in
                let double = Double(integer)
                return Int64(exactly: double) == integer ? double : nil
            }
        } else {
            return Double(trimmed).flatMap { $0.isFinite ? $0 : nil }
        }
    }

    /// How much one point of a drag changes a number: 1 for an integer; for a decimal 0.01
    /// when it starts within -1 to 1 (an opacity), otherwise 1. `tenth` (Option) makes it a
    /// tenth, `tenfold` (Shift) ten times; an integer never goes below 1.
    static func step(from start: Double, isInteger: Bool, tenth: Bool, tenfold: Bool) -> Double {
        var step = isInteger || abs(start) > 1 ? 1.0 : 0.01
        if tenth { step /= 10 }
        if tenfold { step *= 10 }
        return isInteger ? max(1, step.rounded()) : step
    }

    /// `start` moved by `distance` steps, rounded to the step's decimals, so that a drag does
    /// not give 0.30000000000000004.
    static func scrubbed(_ start: Double, by distance: CGFloat, step: Double) -> Double {
        let decimals = max(0, Int((-log10(step)).rounded(.up)))
        let scale = pow(10, Double(decimals))
        return ((start + Double(distance) * step) * scale).rounded() / scale
    }
}
