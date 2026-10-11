import Compression
import Foundation

/// Decompressed pixels: premultiplied BGRA, 8 bits per channel, sRGB, rows top to bottom
/// (P-IMG-01).
public struct Bitmap: Equatable, Sendable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// At least `pixelWidth * 4`. The bytes beyond that in each row are padding (P-IMG-02).
    public var bytesPerRow: Int
    /// Pixels per point.
    public var scale: Float
    /// `bytesPerRow * pixelHeight` bytes.
    public var pixels: Data

    public init(pixelWidth: Int, pixelHeight: Int, bytesPerRow: Int, scale: Float, pixels: Data) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.bytesPerRow = bytesPerRow
        self.scale = scale
        self.pixels = pixels
    }

    /// The `pixelWidth * 4` meaningful bytes of row `y`, without its padding. Nil for a row
    /// outside the bitmap, or one its pixels do not hold: the initializer checks nothing
    /// (C-WIRE-09).
    public func row(_ y: Int) -> Data? {
        guard y >= 0, y < pixelHeight, pixelWidth >= 0, bytesPerRow >= 0 else { return nil }
        let (offset, overflowed) = y.multipliedReportingOverflow(by: bytesPerRow)
        let (length, tooWide) = pixelWidth.multipliedReportingOverflow(by: 4)
        guard !overflowed, !tooWide, offset <= pixels.count - length else { return nil }
        let start = pixels.startIndex + offset
        return pixels.subdata(in: start..<(start + length))
    }
}

public enum ImageError: Error, Equatable {
    /// `bytes_per_row` is smaller than `pixel_width * 4` (P-IMG-02).
    case rowTooShort(bytesPerRow: Int, pixelWidth: Int)
    /// The header describes more than `EncodedImage.maximumDecodedByteCount` bytes (P-DET-08).
    case tooLarge(byteCount: Int)
    /// The data is not valid LZFSE.
    case corruptData
    /// The data decompressed to less than the header describes.
    case sizeMismatch(expected: Int, actual: Int)
    /// The data holds more than the header describes; decompressing stopped there, so a small
    /// piece of data cannot make a large allocation.
    case tooMuchData(expected: Int)
}

extension EncodedImage {
    /// 64 MiB (P-DET-08).
    public static let maximumDecodedByteCount = 67_108_864

    /// Decompresses the pixels. Checks the header before decompressing and the result after,
    /// and never returns a bitmap that does not match its header.
    public func decoded() throws -> Bitmap {
        let width = Int(pixelWidth)
        let height = Int(pixelHeight)
        let rowBytes = Int(bytesPerRow)

        guard rowBytes >= width * 4 else {
            throw ImageError.rowTooShort(bytesPerRow: rowBytes, pixelWidth: width)
        }
        // Both factors come straight from the wire, so the product may not fit in an Int.
        let (expected, overflowed) = rowBytes.multipliedReportingOverflow(by: height)
        guard !overflowed, expected <= Self.maximumDecodedByteCount else {
            throw ImageError.tooLarge(byteCount: overflowed ? Int.max : expected)
        }
        guard expected > 0 else {
            return Bitmap(
                pixelWidth: width, pixelHeight: height, bytesPerRow: rowBytes, scale: scale,
                pixels: Data())
        }

        let pixels: Data
        switch encoding {
        case .bgra8PremultipliedLzfse:
            pixels = try Self.decompressLZFSE(data, expected: expected)
        }
        guard pixels.count == expected else {
            throw ImageError.sizeMismatch(expected: expected, actual: pixels.count)
        }
        return Bitmap(
            pixelWidth: width, pixelHeight: height, bytesPerRow: rowBytes, scale: scale,
            pixels: pixels)
    }

    /// Decompresses into room for one byte more than the header describes: filling that byte
    /// means the data holds more, and nothing past it is decompressed.
    private static func decompressLZFSE(_ data: Data, expected: Int) throws -> Data {
        guard !data.isEmpty else { throw ImageError.corruptData }
        let capacity = expected + 1
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                guard let output = destination.bindMemory(to: UInt8.self).baseAddress,
                      let input = source.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_decode_buffer(
                    output, capacity, input, data.count, nil, COMPRESSION_LZFSE)
            }
        }
        guard written > 0 else { throw ImageError.corruptData }
        guard written <= expected else { throw ImageError.tooMuchData(expected: expected) }
        output.count = written
        return output
    }
}
