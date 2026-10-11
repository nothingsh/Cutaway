import AppKit
import CutawayRender

/// The colours of `RenderStyle`, which are sRGB components from 0 to 1, as AppKit, Core
/// Graphics and the rendered image's pixels take them.
extension SIMD4 where Scalar == Float {
    /// This colour as an `NSColor` in sRGB.
    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(x), green: CGFloat(y), blue: CGFloat(z), alpha: CGFloat(w))
    }

    /// This colour as a `CGColor` in sRGB.
    var cgColor: CGColor {
        CGColor(
            srgbRed: CGFloat(x), green: CGFloat(y), blue: CGFloat(z), alpha: CGFloat(w))
    }

    /// This colour as a pixel of a rendered image: each component clamped to 0...1 and
    /// rounded to a byte.
    var pixel: Pixel {
        func byte(_ value: Float) -> UInt8 {
            UInt8((Swift.min(Swift.max(value, 0), 1) * 255).rounded())
        }
        return Pixel(blue: byte(z), green: byte(y), red: byte(x), alpha: byte(w))
    }
}
