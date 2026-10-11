import CutawayTestSupport
import CutawayWire
import XCTest

/// C-WIRE-03. Pixels are premultiplied BGRA, rows top to bottom (P-IMG-01).
final class ImageTests: XCTestCase {
    private func details(_ scenario: String, _ file: String) throws -> [LayerDetail] {
        let frame = try FrameCodec.decode(try Fixtures.data(scenario: scenario, file: file))
        guard case .layerDetailsChunk(let chunk) = frame.body else {
            XCTFail("not a chunk")
            return []
        }
        return chunk.details
    }

    private func appIcon() throws -> EncodedImage {
        let frame = try FrameCodec.decode(
            try Fixtures.data(scenario: "app-icon", file: "02-s2c-app-icon.bin"))
        guard case .appIcon(let icon) = frame.body else { throw CocoaError(.coderInvalidValue) }
        return try XCTUnwrap(icon.image)
    }

    /// Asserts that every row of `bitmap` repeats `pixel` across its meaningful bytes.
    private func assertSolid(
        _ bitmap: Bitmap, _ pixel: [UInt8], file: StaticString = #filePath, line: UInt = #line
    ) {
        let expectedRow = Data((0..<bitmap.pixelWidth).flatMap { _ in pixel })
        for y in 0..<bitmap.pixelHeight where bitmap.row(y) != expectedRow {
            XCTFail("row \(y) is not solid \(pixel)", file: file, line: line)
            return
        }
    }

    func test_C_WIRE_03_appIconDecodesToItsFourPixels() throws {
        let bitmap = try appIcon().decoded()
        XCTAssertEqual(bitmap.pixelWidth, 2)
        XCTAssertEqual(bitmap.pixelHeight, 2)
        XCTAssertEqual(bitmap.bytesPerRow, 8)
        XCTAssertEqual(bitmap.scale, 1)
        XCTAssertEqual(
            [UInt8](bitmap.pixels),
            [
                0x00, 0x00, 0xFF, 0xFF,  // top left: opaque red
                0x00, 0xFF, 0x00, 0xFF,  // top right: opaque green
                0xFF, 0x00, 0x00, 0xFF,  // bottom left: opaque blue
                0x00, 0x00, 0x00, 0x00,  // bottom right: transparent
            ])
    }

    func test_C_WIRE_03_paddedRowsKeepTheirPaddingOutOfTheWay() throws {
        let image = try XCTUnwrap(
            try details("layer-details-edge", "02-s2c-chunk-0.bin")[1].group)
        let bitmap = try image.decoded()
        XCTAssertEqual(bitmap.pixelWidth, 60)
        XCTAssertEqual(bitmap.pixelHeight, 30)
        XCTAssertEqual(bitmap.bytesPerRow, 256)
        XCTAssertEqual(bitmap.pixels.count, 256 * 30)
        XCTAssertEqual(bitmap.row(0)?.count, 240)
        // Opaque orange. The 16 padding bytes of each row are 0xAA and are not part of row(_:).
        assertSolid(bitmap, [0x00, 0x80, 0xFF, 0xFF])
    }

    func test_C_WIRE_03_solidLayerImagesDecode() throws {
        let red = try XCTUnwrap(try details("layer-details", "02-s2c-chunk-0.bin")[0].group)
        assertSolid(try red.decoded(), [0x00, 0x00, 0xFF, 0xFF])

        let layer4 = try details("layer-details", "03-s2c-chunk-1.bin")[0]
        assertSolid(try XCTUnwrap(layer4.solo).decoded(), [0x00, 0xFF, 0x00, 0xFF])
        assertSolid(try XCTUnwrap(layer4.group).decoded(), [0x00, 0xFF, 0x00, 0xFF])

        // Half-transparent blue, premultiplied.
        let blue = try XCTUnwrap(
            try details("layer-details-cancelled", "02-s2c-chunk-0.bin")[0].group)
        let bitmap = try blue.decoded()
        XCTAssertEqual(bitmap.bytesPerRow, 1572)
        assertSolid(bitmap, [0x80, 0x00, 0x00, 0x80])
    }

    func test_C_WIRE_03_anImageWithNoPixelsDecodesToAnEmptyBitmap() throws {
        let empty = EncodedImage(
            encoding: .bgra8PremultipliedLzfse, pixelWidth: 0, pixelHeight: 0, bytesPerRow: 0,
            scale: 2, data: Data())
        XCTAssertEqual(
            try empty.decoded(),
            Bitmap(pixelWidth: 0, pixelHeight: 0, bytesPerRow: 0, scale: 2, pixels: Data()))
    }

    func test_C_WIRE_03_rejectsRowsShorterThanTheirPixels() throws {
        var image = try appIcon()
        image.bytesPerRow = 7  // 2 pixels need 8 bytes (P-IMG-02)
        XCTAssertThrowsError(try image.decoded()) { error in
            XCTAssertEqual(error as? ImageError, .rowTooShort(bytesPerRow: 7, pixelWidth: 2))
        }
    }

    func test_C_WIRE_03_rejectsDataThatDoesNotMatchTheHeader() throws {
        var image = try appIcon()
        image.pixelHeight = 3  // the data holds 2 rows
        XCTAssertThrowsError(try image.decoded()) { error in
            XCTAssertEqual(error as? ImageError, .sizeMismatch(expected: 24, actual: 16))
        }
    }

    func test_C_WIRE_03_rejectsImagesOverTheSizeLimitWithoutDecompressing() throws {
        XCTAssertEqual(EncodedImage.maximumDecodedByteCount, 67_108_864)
        var image = try appIcon()
        image.pixelWidth = 5000
        image.pixelHeight = 5000
        image.bytesPerRow = 20000  // 100,000,000 bytes
        XCTAssertThrowsError(try image.decoded()) { error in
            XCTAssertEqual(error as? ImageError, .tooLarge(byteCount: 100_000_000))
        }
    }

    func test_C_WIRE_03_rejectsAHeaderWhoseSizeOverflows() throws {
        // bytes_per_row × pixel_height does not fit in an Int. With a width of 0 the row check
        // passes, so the product is the first thing that can go wrong.
        var image = try appIcon()
        image.pixelWidth = 0
        image.pixelHeight = .max
        image.bytesPerRow = .max
        XCTAssertThrowsError(try image.decoded()) { error in
            guard case .tooLarge = error as? ImageError else { return XCTFail("threw \(error)") }
        }
    }

    func test_C_WIRE_03_rejectsDataThatIsNotLZFSE() throws {
        var image = try appIcon()
        image.data = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01, 0x02, 0x03])
        XCTAssertThrowsError(try image.decoded()) { error in
            XCTAssertEqual(error as? ImageError, .corruptData)
        }
    }

    // MARK: - A limit on what is decompressed

    func test_C_WIRE_03_dataThatDecompressesToMoreThanTheHeaderSaysStopsAtTheHeader() throws {
        // A few kilobytes that decompress to 32 MiB, under a header that promises 16 bytes.
        let zeros = Data(count: 32 * 1_048_576)
        let compressed = try (zeros as NSData).compressed(using: .lzfse) as Data
        XCTAssertLessThan(compressed.count, 100_000)
        let image = EncodedImage(
            encoding: .bgra8PremultipliedLzfse, pixelWidth: 2, pixelHeight: 2, bytesPerRow: 8,
            scale: 1, data: compressed)
        XCTAssertThrowsError(try image.decoded()) { error in
            // Stopped one byte past what the header describes, not after 32 MiB.
            XCTAssertEqual(error as? ImageError, .tooMuchData(expected: 16))
        }
    }

    func test_C_WIRE_03_dataThatDecompressesToLessThanTheHeaderSaysIsRefused() throws {
        let compressed = try (Data(count: 8) as NSData).compressed(using: .lzfse) as Data
        let image = EncodedImage(
            encoding: .bgra8PremultipliedLzfse, pixelWidth: 2, pixelHeight: 2, bytesPerRow: 8,
            scale: 1, data: compressed)
        XCTAssertThrowsError(try image.decoded()) { error in
            XCTAssertEqual(error as? ImageError, .sizeMismatch(expected: 16, actual: 8))
        }
    }
}
