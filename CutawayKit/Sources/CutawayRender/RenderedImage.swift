import Foundation

/// One pixel as it is stored: premultiplied BGRA.
public struct Pixel: Equatable, Sendable, CustomStringConvertible {
    public var blue: UInt8
    public var green: UInt8
    public var red: UInt8
    public var alpha: UInt8

    public init(blue: UInt8, green: UInt8, red: UInt8, alpha: UInt8) {
        self.blue = blue
        self.green = green
        self.red = red
        self.alpha = alpha
    }

    public var description: String { "(B \(blue), G \(green), R \(red), A \(alpha))" }
}

/// Pixels read back from a render target: BGRA, rows top to bottom, no padding.
public struct RenderedImage: Equatable, Sendable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// `pixelWidth * 4 * pixelHeight` bytes.
    public var bytes: Data

    public init(pixelWidth: Int, pixelHeight: Int, bytes: Data) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.bytes = bytes
    }

    public func pixel(x: Int, y: Int) -> Pixel {
        let offset = bytes.startIndex + (y * pixelWidth + x) * 4
        return Pixel(
            blue: bytes[offset], green: bytes[offset + 1], red: bytes[offset + 2],
            alpha: bytes[offset + 3])
    }
}
