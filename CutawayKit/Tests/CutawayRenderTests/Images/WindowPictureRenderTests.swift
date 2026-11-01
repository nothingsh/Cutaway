import CutawayRender
import CutawayScene
import Metal
import XCTest

/// How a window is drawn as its picture (C-REND-13), on the `hierarchy` fixture with the
/// `layer-details` images and the `layer-details-composited` group of layer 1: the picture, with
/// the layers' outlines over it and none of their images.
final class WindowPictureRenderTests: XCTestCase {
    private var renderer: Renderer!
    private var textures: TextureCache!
    private let viewport = RenderFixtures.portrait

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        renderer = try Renderer(device: device)
        textures = TextureCache(device: device)
    }

    private func list(composited: Bool, selected: UInt64? = nil) throws -> DrawList {
        var keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        let window = try RenderFixtures.storeDetails(
            scenario: "layer-details-composited", in: textures)[1]
        keys[1, default: LayerTextures()].group = window?.group
        keys[1, default: LayerTextures()].groupIsComposited = composited
        return RenderFixtures.layout(try RenderFixtures.hierarchyLayers(textures: keys))
            .replacingTextures(keys)
            .project(camera: .flat, viewport: viewport, selected: selected, hovered: nil)
    }

    private func render(_ list: DrawList) throws -> RenderedImage {
        try renderer.renderImage(
            list, textures: textures, style: .standard, pixelWidth: Int(viewport.width),
            pixelHeight: Int(viewport.height))
    }

    func test_C_REND_13_theLayersImagesGiveWayToThePicture() throws {
        let layers = try list(composited: false)
        let four = try RenderFixtures.item(layers, 4)
        assertPixel(
            try render(layers).pixel(at: four.center), RenderFixtures.pixel(SIMD4<Float>(0, 1, 0, 1)),
            "layer 4's green image")
        assertPixel(
            try render(try list(composited: true)).pixel(at: four.center),
            RenderFixtures.pixel(SIMD4<Float>(0xF2, 0xF2, 0xF2, 0xFF) / 255), "the picture's gray")
    }

    /// The picture a person approves (`Baselines/`), with layer 3 selected.
    func test_C_REND_13_thePictureMatchesTheBaseline() throws {
        try assertMatchesBaseline(
            try render(try list(composited: true, selected: 3)), named: "C-REND-13-window-picture")
    }
}
