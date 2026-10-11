import CutawayModel
import CutawayRender
import CutawayScene
import CutawayTestSupport
import CutawayWire
import XCTest

enum RenderFixtures {
    static let portrait = Viewport(width: 480, height: 900)
    static let square = Viewport(width: 900, height: 900)

    static func textureImage(_ bitmap: Bitmap) -> TextureImage {
        TextureImage(
            pixelWidth: bitmap.pixelWidth, pixelHeight: bitmap.pixelHeight,
            bytesPerRow: bitmap.bytesPerRow, bytes: bitmap.pixels)
    }

    /// Stores the images of a details scenario in `textures` and says which layer has which.
    static func storeDetails(
        scenario: String, in textures: TextureCache
    ) throws -> [UInt64: LayerTextures] {
        var keys: [UInt64: LayerTextures] = [:]
        for detail in try Fixtures.layerDetails(scenario: scenario) where detail.status == .ok {
            var entry = LayerTextures()
            if let solo = detail.solo {
                let key = TextureKey(layerID: detail.layerID, kind: .solo, revision: 1)
                textures.store(textureImage(try solo.decoded()), for: key)
                entry.solo = key
            }
            if let group = detail.group {
                let key = TextureKey(layerID: detail.layerID, kind: .group, revision: 1)
                textures.store(textureImage(try group.decoded()), for: key)
                entry.group = key
            }
            keys[detail.layerID] = entry
        }
        return keys
    }

    /// The `hierarchy` fixture's layers.
    static func hierarchyLayers(textures: [UInt64: LayerTextures]) throws -> [SceneLayer] {
        try LayerTree(try Fixtures.hierarchy()).sceneLayers(textures: textures)
    }

    /// The layers with every node expanded.
    static func layout(_ layers: [SceneLayer]) -> SceneLayout {
        SceneLayout(layers: layers, expanded: Set(layers.map(\.id)))
    }

    static func item(_ list: DrawList, _ id: UInt64) throws -> DrawItem {
        try XCTUnwrap(list.items.first { $0.layerID == id }, "layer \(id) is not drawn")
    }

    /// A window point under the flat camera, from where a layer covering the whole 393 × 852
    /// window was drawn: layer 1 of the `hierarchy` fixture unless told otherwise.
    static func flatPoint(
        _ list: DrawList, x: Double, y: Double, window id: UInt64 = 1
    ) throws -> ScenePoint {
        let window = try item(list, id).points
        return ScenePoint(
            x: window[0].x + x / 393 * (window[1].x - window[0].x),
            y: window[0].y + y / 852 * (window[2].y - window[0].y))
    }

    /// An opaque red layer, and a larger translucent blue one drawn over it (C-REND-02).
    static func blendingList(red: TextureKey, blue: TextureKey) -> DrawList {
        layout(blendingLayers(red: red, blue: blue))
            .project(camera: .flat, viewport: portrait, selected: nil, hovered: nil)
    }

    static func blendingLayers(red: TextureKey, blue: TextureKey) -> [SceneLayer] {
        [
            SceneLayer(
                id: 1, parentID: 0, bounds: SceneRect(x: 0, y: 0, width: 200, height: 24),
                position: ScenePoint(x: 50, y: 100), anchorPoint: .zero, group: red),
            SceneLayer(
                id: 2, parentID: 0, bounds: SceneRect(x: 0, y: 0, width: 393, height: 852),
                position: .zero, anchorPoint: .zero, group: blue),
        ]
    }

    /// Stores the red and blue images of C-REND-02 and gives their keys.
    static func storeBlendingImages(
        in textures: TextureCache
    ) throws -> (red: TextureKey, blue: TextureKey) {
        let red = TextureKey(layerID: 1, kind: .group, revision: 1)
        let blue = TextureKey(layerID: 2, kind: .group, revision: 1)
        let redImage = try XCTUnwrap(
            try Fixtures.layerDetails(scenario: "layer-details").first { $0.layerID == 3 }?.group)
        let blueImage = try XCTUnwrap(
            try Fixtures.layerDetails(scenario: "layer-details-cancelled")
                .first { $0.layerID == 2 }?.group)
        textures.store(textureImage(try redImage.decoded()), for: red)
        textures.store(textureImage(try blueImage.decoded()), for: blue)
        return (red, blue)
    }

    /// Premultiplied `top` over `bottom`, the way the blending stores it.
    static func over(_ top: SIMD4<Float>, _ bottom: SIMD4<Float>) -> SIMD4<Float> {
        top + bottom * (1 - top.w)
    }

    static func pixel(_ color: SIMD4<Float>) -> Pixel {
        func byte(_ value: Float) -> UInt8 { UInt8((min(max(value, 0), 1) * 255).rounded()) }
        return Pixel(
            blue: byte(color.z), green: byte(color.y), red: byte(color.x), alpha: byte(color.w))
    }

    static let red = Pixel(blue: 0, green: 0, red: 255, alpha: 255)
    static let green = Pixel(blue: 0, green: 255, red: 0, alpha: 255)
    static let orange = Pixel(blue: 0x00, green: 0x80, red: 0xFF, alpha: 0xFF)
    /// 0x80 0x00 0x00 0x80 from `layer-details-cancelled`, as 0–1 premultiplied RGBA.
    static let translucentBlue = SIMD4<Float>(0, 0, 128.0 / 255, 128.0 / 255)
    static let opaqueRed = SIMD4<Float>(1, 0, 0, 1)
}

extension RenderedImage {
    /// The pixel that holds a viewport point, at one pixel per point.
    func pixel(at point: ScenePoint) -> Pixel {
        pixel(x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down)))
    }
}

func assertPixel(
    _ actual: Pixel, _ expected: Pixel, tolerance: Int = 2, _ message: String = "",
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertFalse(
        differ(actual, expected, tolerance: tolerance),
        "\(actual) is not \(expected) within \(tolerance). \(message)", file: file, line: line)
}

/// Whether two pixels differ by more than the tolerance in some channel.
func differ(_ a: Pixel, _ b: Pixel, tolerance: Int = 2) -> Bool {
    abs(Int(a.blue) - Int(b.blue)) > tolerance || abs(Int(a.green) - Int(b.green)) > tolerance
        || abs(Int(a.red) - Int(b.red)) > tolerance || abs(Int(a.alpha) - Int(b.alpha)) > tolerance
}
