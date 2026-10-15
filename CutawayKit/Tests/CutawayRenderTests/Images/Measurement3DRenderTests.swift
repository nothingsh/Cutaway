import CutawayRender
import CutawayScene
import Metal
import XCTest

/// Measuring two layers on different levels in 3D, sampled where the scene says the links
/// are (C-REND-09).
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
    private func list(measuring: UInt64? = 2) throws -> DrawList {
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        return RenderFixtures.layout(try RenderFixtures.hierarchyLayers(textures: keys))
            .project(
                camera: Self.camera, viewport: viewport, selected: 3, hovered: 2,
                measuring: measuring)
    }

    private func render(_ list: DrawList) throws -> RenderedImage {
        try renderer.renderImage(
            list, textures: textures, style: style, pixelWidth: Int(viewport.width),
            pixelHeight: Int(viewport.height))
    }

    private func pixel(at point: ScenePoint) -> (x: Int, y: Int) {
        (Int(point.x.rounded(.down)), Int(point.y.rounded(.down)))
    }

    /// The pixels around a point: a one-pixel line through it is among them.
    private func around(_ point: ScenePoint) -> [(x: Int, y: Int)] {
        let (x, y) = pixel(at: point)
        return (-1...1).flatMap { dy in (-1...1).map { dx in (x + dx, y + dy) } }
    }

    private func color(_ pixel: Pixel) -> SIMD4<Float> {
        SIMD4(Float(pixel.red), Float(pixel.green), Float(pixel.blue), Float(pixel.alpha)) / 255
    }

    /// How much of a pixel a line of `color` (premultiplied) covers over `below`; nil when the
    /// pixel is not that colour over that background, within the tolerance.
    private func coverage(of color: SIMD4<Float>, in pixel: Pixel, over below: Pixel) -> Float? {
        let p = self.color(pixel), b = self.color(below)
        // pixel = coverage × color + (1 − coverage × color's alpha) × below, channel by channel.
        let k = SIMD3(color.x, color.y, color.z) - color.w * SIMD3(b.x, b.y, b.z)
        let d = SIMD3(p.x, p.y, p.z) - SIMD3(b.x, b.y, b.z)
        let kk = (k * k).sum()
        guard kk > 0 else { return nil }
        let amount = min(max((d * k).sum() / kk, 0), 1)
        let rest = d - amount * k
        guard max(abs(rest.x), abs(rest.y), abs(rest.z)) <= 3 / 255 else { return nil }
        return amount
    }

    func test_C_REND_09_measurementIn3DMatchesTheBaseline() throws {
        try assertMatchesBaseline(try render(try list()), named: "C-REND-09-measurement-3d")
    }
}
