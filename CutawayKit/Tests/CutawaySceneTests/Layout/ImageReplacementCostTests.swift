import CutawayTestSupport
import XCTest

@testable import CutawayScene

/// C-SCALE-02: new images for a few layers change what those layers are drawn with and
/// nothing else, so the layout with them shares its geometry with the one before, and copies
/// a part of the images that does not grow with the layers.
final class ImageReplacementCostTests: XCTestCase {
    /// `count` layers side by side under a root, each with a solo and a group image.
    private func layers(_ count: Int) -> [SceneLayer] {
        let root = SceneLayer(
            id: 1, parentID: 0, bounds: SceneRect(x: 0, y: 0, width: 1000, height: 1000),
            position: ScenePoint(x: 500, y: 500))
        return [root] + (0..<UInt64(count)).map { offset in
            let id = offset + 2
            return SceneLayer(
                id: id, parentID: 1, bounds: SceneRect(x: 0, y: 0, width: 10, height: 10),
                position: ScenePoint(x: Double(offset % 100) * 10 + 5, y: Double(offset / 100) * 10 + 5),
                solo: TextureKey(layerID: id, kind: .solo, revision: 1),
                group: TextureKey(layerID: id, kind: .group, revision: 1))
        }
    }

    func test_C_SCALE_02_newImagesForAFewLayersLeaveTheGeometryShared() {
        let layers = layers(10000)
        let layout = SceneLayout(layers: layers, expanded: Set(layers.map(\.id)))
        let changed: [UInt64] = [2, 5000, 10001]
        let textures = Dictionary(uniqueKeysWithValues: changed.map {
            ($0, LayerTextures(group: TextureKey(layerID: $0, kind: .group, revision: 2)))
        })
        let next = layout.replacingTextures(textures, of: changed)

        XCTAssertTrue(next.sharesGeometry(with: layout), "the layers' places are not copied")
        XCTAssertLessThanOrEqual(
            next.imagesCopied(since: layout), changed.count * 64 + layers.count / 64 + 1,
            "only the parts of the images that changed are copied")
        // The changed layers draw their new images; the others keep theirs.
        XCTAssertEqual(next.texture(of: 5000), TextureKey(layerID: 5000, kind: .group, revision: 2))
        XCTAssertEqual(next.texture(of: 5001), TextureKey(layerID: 5001, kind: .group, revision: 1))
        XCTAssertEqual(layout.texture(of: 5000), TextureKey(layerID: 5000, kind: .group, revision: 1))
    }
}
