import Foundation

public enum ImageEncoding: Sendable { case bgra8PremultipliedLzfse }

/// An image as sent: compressed pixel data plus its description. See `decoded()`.
public struct EncodedImage: Equatable, Sendable {
    public var encoding: ImageEncoding
    public var pixelWidth: UInt32
    public var pixelHeight: UInt32
    /// Of the decompressed pixel data.
    public var bytesPerRow: UInt32
    /// Pixels per point.
    public var scale: Float
    public var data: Data

    public init(
        encoding: ImageEncoding, pixelWidth: UInt32, pixelHeight: UInt32, bytesPerRow: UInt32,
        scale: Float, data: Data
    ) {
        self.encoding = encoding
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.bytesPerRow = bytesPerRow
        self.scale = scale
        self.data = data
    }
}

public struct AppIcon: Equatable, Sendable {
    /// Nil when the app has no icon.
    public var image: EncodedImage?

    public init(image: EncodedImage?) {
        self.image = image
    }
}
