import CoreGraphics
import CutawayWire
import Foundation

/// The appearance a colour set's colour is for (C-SRC-04).
public enum AssetAppearance: Equatable, Hashable, Sendable {
    case any, light, dark
}

/// A colour as it is compared (C-SRC-04): its four sRGB components, each clamped to 0 to 1
/// (P-ATTR-04) and rounded to 8 bits.
public struct RoundedColor: Equatable, Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = Self.rounded(red)
        self.green = Self.rounded(green)
        self.blue = Self.rounded(blue)
        self.alpha = Self.rounded(alpha)
    }

    public init(_ color: Color) {
        self.init(
            red: Double(color.red), green: Double(color.green), blue: Double(color.blue),
            alpha: Double(color.alpha))
    }

    private static func rounded(_ component: Double) -> UInt8 {
        guard component.isFinite else { return 0 }
        return UInt8((min(max(component, 0), 1) * 255).rounded())
    }
}

/// How the colours of a colour set's `Contents.json` read (C-SRC-04, Apple's Asset Catalog
/// Format Reference).
enum AssetColor {
    /// The entry's appearance and colour; nil for an entry that is not compared: a high
    /// contrast one, one that refers to a system colour, one in a colour space not read here,
    /// or one whose components do not read.
    static func resolve(_ entry: ColorSet.Entry) -> (AssetAppearance, RoundedColor)? {
        guard entry.systemReference == nil,
              !entry.appearances.contains(where: { $0.appearance == "contrast" && $0.value == "high" }),
              let appearance = appearance(of: entry),
              let color = color(of: entry)
        else { return nil }
        return (appearance, color)
    }

    private static func appearance(of entry: ColorSet.Entry) -> AssetAppearance? {
        let luminosity = entry.appearances.filter { $0.appearance == "luminosity" }
        switch luminosity.first?.value {
        case nil: return .any
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    /// The colour in sRGB: made in its own space, converted by CoreGraphics to extended sRGB,
    /// then clamped, as the server does (P-ATTR-04).
    static func color(of entry: ColorSet.Entry) -> RoundedColor? {
        let space = entry.colorSpace ?? "srgb"
        let gray = space == "gray-gamma-22" || space == "extended-gray"
        let names = gray ? ["white", "alpha"] : ["red", "green", "blue", "alpha"]
        var components: [CGFloat] = []
        for name in names {
            guard let text = entry.components[name],
                  let value = component(text, isAlpha: name == "alpha")
            else { return nil }
            components.append(CGFloat(value))
        }
        guard let source = colorSpace(named: space),
              let extended = CGColorSpace(name: CGColorSpace.extendedSRGB),
              let made = CGColor(colorSpace: source, components: components),
              let converted = made.converted(to: extended, intent: .defaultIntent, options: nil),
              let rgba = converted.components, rgba.count == 4
        else { return nil }
        return RoundedColor(
            red: Double(rgba[0]), green: Double(rgba[1]), blue: Double(rgba[2]), alpha: Double(rgba[3]))
    }

    private static func colorSpace(named name: String) -> CGColorSpace? {
        switch name {
        case "srgb": CGColorSpace(name: CGColorSpace.sRGB)
        case "extended-srgb": CGColorSpace(name: CGColorSpace.extendedSRGB)
        case "display-p3": CGColorSpace(name: CGColorSpace.displayP3)
        case "gray-gamma-22": CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)
        case "extended-gray": CGColorSpace(name: CGColorSpace.extendedGray)
        default: nil
        }
    }

    /// A component as Xcode writes it: a decimal from 0 to 1 (`0.200`), hexadecimal from 0 to
    /// 255 (`0x33`), or an integer from 0 to 255 (`51`). Alpha is always a decimal, so its
    /// whole numbers 0 and 1 are read as such. Nil for one that does not read.
    static func component(_ text: String, isAlpha: Bool) -> Double? {
        let text = text.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("0x") {
            return UInt8(text.dropFirst(2), radix: 16).map { Double($0) / 255 }
        }
        if text.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }) {
            return Double(text).flatMap { $0.isFinite ? $0 : nil }
        }
        guard let integer = Int(text), (0...255).contains(integer) else { return nil }
        if isAlpha, integer <= 1 { return Double(integer) }
        return Double(integer) / 255
    }
}
