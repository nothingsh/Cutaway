import AppKit
import CutawayRender
import CutawayWire
import ImageIO
import UniformTypeIdentifiers

extension Bitmap {
    /// An image of the bitmap, sized in points. Nil for a bitmap that has no pixels, or whose
    /// data is shorter than its header says.
    func makeImage() -> NSImage? {
        guard let image = cgImage() else { return nil }
        let pixelsPerPoint = CGFloat(scale > 0 ? scale : 1)
        return NSImage(
            cgImage: image,
            size: NSSize(
                width: CGFloat(pixelWidth) / pixelsPerPoint,
                height: CGFloat(pixelHeight) / pixelsPerPoint))
    }

    /// The bitmap as a PNG file (C-ARCH-06): its pixel size, sRGB, the alpha written
    /// unpremultiplied as PNG has it, without the rows' padding, and a resolution of 72 dots
    /// per inch for each pixel a point has, so that it shows at its size in points. Nil for a
    /// bitmap that `makeImage()` gives no image for.
    func pngData() -> Data? {
        guard let image = cgImage() else { return nil }
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        let dotsPerInch = 72 * Double(scale > 0 ? scale : 1)
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dotsPerInch,
            kCGImagePropertyDPIHeight: dotsPerInch,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// The pixels as they are, premultiplied BGRA in sRGB (P-IMG-01). The rows' padding stays
    /// in the data and out of the image.
    private func cgImage() -> CGImage? {
        let (rowLength, rowOverflowed) = pixelWidth.multipliedReportingOverflow(by: 4)
        let (byteCount, countOverflowed) = bytesPerRow.multipliedReportingOverflow(by: pixelHeight)
        guard pixelWidth > 0, pixelHeight > 0, !rowOverflowed, !countOverflowed,
              bytesPerRow >= rowLength, pixels.count >= byteCount,
              let provider = CGDataProvider(data: pixels as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        // Premultiplied BGRA bytes are a little-endian 32-bit word with alpha first (P-IMG-01).
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))
        return CGImage(
            width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo,
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

extension TextureImage {
    /// The decoded pixels of an image from the wire; both are premultiplied BGRA.
    init(_ bitmap: Bitmap) {
        self.init(
            pixelWidth: bitmap.pixelWidth, pixelHeight: bitmap.pixelHeight,
            bytesPerRow: bitmap.bytesPerRow, bytes: bitmap.pixels)
    }
}
