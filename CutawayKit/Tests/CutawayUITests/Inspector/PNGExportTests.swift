import CoreGraphics
import CutawayTestSupport
import CutawayWire
import Foundation
import ImageIO
import XCTest

@testable import CutawayUI

/// C-ARCH-06: a layer's screenshot as a PNG file.
final class PNGExportTests: XCTestCase {
    private func image(_ scenario: String, layer: UInt64, solo: Bool = false) throws -> Bitmap {
        let detail = try XCTUnwrap(
            try Fixtures.layerDetails(scenario: scenario).first { $0.layerID == layer })
        return try XCTUnwrap(solo ? detail.solo : detail.group).decoded()
    }

    private func icon() throws -> Bitmap {
        guard case .appIcon(let icon) = try FrameCodec.decode(
            try Fixtures.data(scenario: "app-icon", file: "02-s2c-app-icon.bin")).body
        else { throw CocoaError(.fileReadCorruptFile) }
        return try XCTUnwrap(icon.image).decoded()
    }

    /// The PNG read back and drawn into premultiplied BGRA, the form the bitmap was in.
    private func readBack(_ png: Data) throws -> (width: Int, height: Int, pixels: [UInt8]) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, "public.png")
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let info = CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.premultipliedFirst.rawValue
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space, bitmapInfo: info)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (width, height, pixels)
    }

    private func assertPixels(
        _ pixels: [UInt8], at index: Int, equal expected: [UInt8],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let actual = Array(pixels[(index * 4)..<(index * 4 + 4)])
        for channel in 0..<4 {
            XCTAssertLessThanOrEqual(
                abs(Int(actual[channel]) - Int(expected[channel])), 2,
                "pixel \(index) is \(actual), not \(expected)", file: file, line: line)
        }
    }

    func test_C_ARCH_06_aPNGHasTheImagesPixelsAndNoPadding() throws {
        // Layer 8 of layer-details-edge: 60 × 30 orange, 256 bytes to a row.
        let bitmap = try image("layer-details-edge", layer: 8)
        XCTAssertEqual(bitmap.bytesPerRow, 256)
        let png = try XCTUnwrap(bitmap.pngData())
        let (width, height, pixels) = try readBack(png)
        XCTAssertEqual(width, 60)
        XCTAssertEqual(height, 30)
        for index in 0..<(width * height) {
            assertPixels(pixels, at: index, equal: [0x00, 0x80, 0xFF, 0xFF])
        }

        // Layer 4's solo of layer-details: 300 × 180 green.
        let green = try readBack(try XCTUnwrap(
            try image("layer-details", layer: 4, solo: true).pngData()))
        XCTAssertEqual(green.width, 300)
        XCTAssertEqual(green.height, 180)
        assertPixels(green.pixels, at: 0, equal: [0x00, 0xFF, 0x00, 0xFF])
    }

    func test_C_ARCH_06_transparencyIsKeptAndUnpremultiplied() throws {
        // The icon: red, green, blue, and a clear pixel at the bottom right.
        let icon = try readBack(try XCTUnwrap(try icon().pngData()))
        assertPixels(icon.pixels, at: 0, equal: [0x00, 0x00, 0xFF, 0xFF])
        assertPixels(icon.pixels, at: 3, equal: [0x00, 0x00, 0x00, 0x00])

        // Half-transparent blue: written unpremultiplied, it reads back as it was. Written
        // premultiplied as if it were not, it would come back at half the blue.
        let blue = try image("layer-details-cancelled", layer: 2)
        let png = try XCTUnwrap(blue.pngData())
        let back = try readBack(png)
        assertPixels(back.pixels, at: 0, equal: [0x80, 0x00, 0x00, 0x80])

        // The file itself holds full blue at half alpha.
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let stored = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertTrue(
            [.last, .first].contains(stored.alphaInfo),
            "the PNG is decoded as \(stored.alphaInfo.rawValue), not with straight alpha")
    }

    func test_C_ARCH_06_theResolutionFollowsTheScale() throws {
        var bitmap = try image("layer-details", layer: 3)
        bitmap.scale = 3
        let png = try XCTUnwrap(bitmap.pngData())
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 0, 216, accuracy: 0.5)
        XCTAssertEqual((properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue ?? 0, 216, accuracy: 0.5)
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 200)
    }

    func test_C_ARCH_06_aBitmapWithoutPixelsGivesNoPNG() {
        let empty = Bitmap(pixelWidth: 0, pixelHeight: 0, bytesPerRow: 0, scale: 1, pixels: Data())
        XCTAssertNil(empty.pngData())
    }
}
