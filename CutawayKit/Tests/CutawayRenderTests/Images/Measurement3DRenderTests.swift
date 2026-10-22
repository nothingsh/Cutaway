import CutawayRender
import CutawayScene
import Metal
import XCTest

/// Measuring two layers on different levels in 3D, compared with its baseline (C-REND-09).
final class Measurement3DRenderTests: XCTestCase {
    private var renderer: Renderer!
    private var textures: TextureCache!
    private let style = RenderStyle.standard
    private let viewport = RenderFixtures.square

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        renderer = try Renderer(device: device)
        textures = TextureCache(device: device)
    }

    /// The fixed 3D view from higher up, with the levels three times as far apart, so that the
    /// links between the levels are long and stand clear of the boxes' edges; zoomed out, as
    /// the view is fitted to the layers and the copy on a higher level reaches beyond them.
    private static let camera: Camera = {
        var camera = Camera.standard3D
        camera.pitch = .pi / 5
        camera.layerSpacing = 150
        camera.zoom = 0.8
        return camera
    }()

    /// The `hierarchy` layers with the `layer-details` images, layer 3 selected, layer 2 (a
    /// level below) hovered and measured to.
    private func list() throws -> DrawList {
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        return RenderFixtures.layout(try RenderFixtures.hierarchyLayers(textures: keys))
            .project(
                camera: Self.camera, viewport: viewport, selected: 3, hovered: 2, measuring: 2)
    }

    private func render(_ list: DrawList) throws -> RenderedImage {
        try renderer.renderImage(
            list, textures: textures, style: style, pixelWidth: Int(viewport.width),
            pixelHeight: Int(viewport.height))
    }

    func test_C_REND_09_measurementIn3DMatchesTheBaseline() throws {
        try assertMatchesBaseline(try render(try list()), named: "C-REND-09-measurement-3d")
    }
}
