import CutawayRender
import CutawayScene
import CutawayTestSupport
import CutawayWire
import Metal
import XCTest

/// The texture cache that the drawing reads images from (C-REND-01).
final class TextureCacheTests: XCTestCase {
    private func cache() throws -> TextureCache {
        TextureCache(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()))
    }

    private func solid(width: Int, height: Int, bytesPerRow: Int? = nil) -> TextureImage {
        let rowBytes = bytesPerRow ?? width * 4
        return TextureImage(
            pixelWidth: width, pixelHeight: height, bytesPerRow: rowBytes,
            bytes: Data(repeating: 0xFF, count: rowBytes * height))
    }

    private let key = TextureKey(layerID: 3, kind: .group, revision: 1)

    func test_C_REND_01_aStoredImageIsFoundByItsKey() throws {
        let textures = try cache()
        textures.store(solid(width: 4, height: 2), for: key)

        let texture = try XCTUnwrap(textures.texture(for: key))
        XCTAssertEqual(texture.width, 4)
        XCTAssertEqual(texture.height, 2)
        XCTAssertEqual(texture.pixelFormat, .bgra8Unorm)
        XCTAssertNil(textures.texture(for: TextureKey(layerID: 3, kind: .solo, revision: 1)))
        XCTAssertNil(textures.texture(for: TextureKey(layerID: 3, kind: .group, revision: 2)))
    }

    func test_C_REND_01_retainingDropsTheOtherTextures() throws {
        let textures = try cache()
        let other = TextureKey(layerID: 4, kind: .solo, revision: 1)
        textures.store(solid(width: 1, height: 1), for: key)
        textures.store(solid(width: 1, height: 1), for: other)
        XCTAssertEqual(textures.count, 2)

        textures.retain(only: [other])
        XCTAssertEqual(textures.count, 1)
        XCTAssertNil(textures.texture(for: key))
        XCTAssertNotNil(textures.texture(for: other))
    }

    func test_C_REND_01_anImageWithoutPixelsIsNotStored() throws {
        let textures = try cache()
        textures.store(solid(width: 0, height: 0), for: key)
        XCTAssertNil(textures.texture(for: key))
        XCTAssertEqual(textures.count, 0)
    }

    func test_C_REND_05_theLimitIsTheLongestSideOfATextureOnThisGPU() throws {
        // Apple's Metal feature set tables: 16,384 on Apple3 and later, and on Mac2.
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let expected = device.supportsFamily(.apple3) || device.supportsFamily(.mac2)
            ? 16_384 : 8_192
        XCTAssertEqual(Renderer.maxTextureDimension(of: device), expected)
    }

    func test_C_REND_05_anImageBeyondTheLimitIsRefused() throws {
        let textures = try cache()
        let limit = Renderer.maxTextureDimension(of: try XCTUnwrap(MTLCreateSystemDefaultDevice()))
        XCTAssertTrue(textures.store(solid(width: limit, height: 1), for: key))
        XCTAssertNotNil(textures.texture(for: key))
        XCTAssertEqual(textures.refusedCount, 0)

        let wide = TextureKey(layerID: 3, kind: .group, revision: 2)
        XCTAssertFalse(textures.store(solid(width: limit + 1, height: 1), for: wide))
        XCTAssertNil(textures.texture(for: wide))
        XCTAssertEqual(textures.refusedCount, 1)
    }

    func test_C_REND_01_anImageWhoseByteCountOverflowsIsRefused() throws {
        let cache = try cache()
        let image = TextureImage(
            pixelWidth: 1, pixelHeight: 2, bytesPerRow: .max, bytes: Data(count: 8))
        XCTAssertFalse(cache.store(image, for: key))
    }

    func test_C_REND_01_everyRefusalIsCounted() throws {
        let textures = try cache()
        XCTAssertFalse(textures.store(solid(width: 0, height: 0), for: key))
        XCTAssertFalse(textures.store(solid(width: 4, height: 4, bytesPerRow: 8), for: key))
        XCTAssertEqual(textures.refusedCount, 2)
    }

    func test_C_REND_01_aPaddedImageIsStoredWithoutItsPadding() throws {
        // layer-details-edge, layer 8: 60 × 30 orange, 256 bytes a row (P-IMG-02).
        let detail = try XCTUnwrap(
            try Fixtures.layerDetails(scenario: "layer-details-edge").first { $0.layerID == 8 })
        let bitmap = try XCTUnwrap(detail.group).decoded()
        XCTAssertEqual(bitmap.bytesPerRow, 256)
        let textures = try cache()
        textures.store(
            TextureImage(
                pixelWidth: bitmap.pixelWidth, pixelHeight: bitmap.pixelHeight,
                bytesPerRow: bitmap.bytesPerRow, bytes: bitmap.pixels),
            for: key)

        let texture = try XCTUnwrap(textures.texture(for: key))
        var row = [UInt8](repeating: 0, count: 60 * 4)
        texture.getBytes(
            &row, bytesPerRow: 60 * 4, from: MTLRegionMake2D(0, 29, 60, 1), mipmapLevel: 0)
        for pixel in stride(from: 0, to: row.count, by: 4) {
            XCTAssertEqual(Array(row[pixel..<(pixel + 4)]), [0x00, 0x80, 0xFF, 0xFF], "byte \(pixel)")
        }
    }

    func test_C_REND_01_theFixturesGiveTheirDetailsInOrder() throws {
        let details = try Fixtures.layerDetails(scenario: "layer-details")
        XCTAssertEqual(details.map(\.layerID), [3, 4, 99])
        XCTAssertEqual(details.map(\.status), [.ok, .ok, .layerNotFound])
    }
}
