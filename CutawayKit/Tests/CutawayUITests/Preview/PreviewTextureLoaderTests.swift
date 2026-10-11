import CutawayRender
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import Metal
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// The preview's textures, without a preview: arriving pixels are uploaded and not kept
/// (C-DET-08), only the drawn images' textures are kept and those lacking are asked for
/// (C-SCALE-02), and an image the cache refused is not offered again (C-REND-05).
final class PreviewTextureLoaderTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    /// A model with the `hierarchy` fixture and the `layer-details` images.
    @MainActor
    private func model() async throws -> InspectionStore {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details"))
        return model
    }

    @MainActor
    private final class Counter {
        var count = 0
    }

    private func cache() throws -> TextureCache {
        TextureCache(device: try XCTUnwrap(MTLCreateSystemDefaultDevice()))
    }

    /// A 2 × 2 image, opaque red.
    private static let red = Bitmap(
        pixelWidth: 2, pixelHeight: 2, bytesPerRow: 8, scale: 1,
        pixels: Data(Array(repeating: [UInt8]([0, 0, 255, 255]), count: 4).flatMap { $0 }))

    /// An image without pixels, which the cache refuses.
    private static let empty = Bitmap(
        pixelWidth: 0, pixelHeight: 0, bytesPerRow: 0, scale: 1, pixels: Data())

    private static func key(_ id: UInt64, revision: UInt64 = 1) -> TextureKey {
        TextureKey(layerID: id, kind: .solo, revision: revision)
    }

    @MainActor
    func test_C_DET_08_arrivingPixelsAreUploadedOnce() async throws {
        let textures = try cache()
        let loader = PreviewTextureLoader(
            store: try await model(), textures: textures, onLateTextures: {})
        XCTAssertTrue(loader.upload([Self.key(3): Self.red]))
        XCTAssertEqual(textures.keys, [Self.key(3)])
        // A texture already there is not made again.
        XCTAssertFalse(loader.upload([Self.key(3): Self.red]))
        XCTAssertEqual(textures.count, 1)
    }

    @MainActor
    func test_C_REND_05_anImageTheCacheRefusedIsNotOfferedAgain() async throws {
        let textures = try cache()
        let model = try await model()
        let loader = PreviewTextureLoader(store: model, textures: textures, onLateTextures: {})
        XCTAssertFalse(loader.upload([Self.key(99): Self.empty]))
        XCTAssertEqual(textures.refusedCount, 1)
        XCTAssertFalse(loader.upload([Self.key(99): Self.empty]))
        XCTAssertEqual(textures.refusedCount, 1, "not offered again")

        // Once the model no longer holds the image, a new one of that key is offered again.
        loader.follow(changedLayers: [99])
        XCTAssertFalse(loader.upload([Self.key(99): Self.empty]))
        XCTAssertEqual(textures.refusedCount, 2)
    }

    @MainActor
    func test_C_SCALE_02_onlyTheDrawnTexturesAreKeptAndThoseLackingAreAskedFor() async throws {
        let textures = try cache()
        let model = try await model()
        let late = Counter()
        let loader = PreviewTextureLoader(
            store: model, textures: textures, onLateTextures: { late.count += 1 })
        let drawn = model.layout.drawnTextures
        XCTAssertFalse(drawn.isEmpty)
        // Something not drawn is dropped.
        loader.upload([Self.key(99): Self.red])

        loader.keepDrawnTextures(drawn)
        XCTAssertTrue(textures.keys.isEmpty, "the drawn images come once decompressed")
        await loader.settled()
        XCTAssertEqual(textures.keys, drawn)
        XCTAssertEqual(late.count, 1, "new textures are new content")

        // Kept again: nothing is lacking, nothing is asked for.
        loader.keepDrawnTextures(drawn)
        await loader.settled()
        XCTAssertEqual(late.count, 1)
        let one = try XCTUnwrap(drawn.first)
        loader.keepDrawnTextures([one])
        XCTAssertEqual(textures.keys, [one])
    }
}
