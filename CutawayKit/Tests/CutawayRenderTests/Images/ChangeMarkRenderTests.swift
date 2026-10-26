import CutawayRender
import CutawayScene
import Metal
import XCTest

/// How what the last refresh changed is drawn (C-REND-12), on the `hierarchy` fixture with the
/// `layer-details` images: a tint over the layer's image and an edge, at the list's strength;
/// under the selection's.
final class ChangeMarkRenderTests: XCTestCase {
    private var renderer: Renderer!
    private var textures: TextureCache!
    private let viewport = RenderFixtures.portrait

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        renderer = try Renderer(device: device)
        textures = TextureCache(device: device)
    }

    private func list(camera: Camera = .flat, selected: UInt64? = nil) throws -> DrawList {
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        return RenderFixtures.layout(try RenderFixtures.hierarchyLayers(textures: keys))
            .project(camera: camera, viewport: viewport, selected: selected, hovered: nil)
    }

    private func render(_ list: DrawList) throws -> RenderedImage {
        try renderer.renderImage(
            list, textures: textures, style: .standard, pixelWidth: Int(viewport.width),
            pixelHeight: Int(viewport.height))
    }

    /// The middle of the item's top edge.
    private func topEdge(_ item: DrawItem) -> ScenePoint {
        ScenePoint(
            x: (item.points.topLeft.x + item.points.topRight.x) / 2,
            y: (item.points.topLeft.y + item.points.topRight.y) / 2)
    }

    func test_C_REND_12_aNewLayersImageTakesTheTintAtTheListsStrength() throws {
        let plain = try list()
        let four = try RenderFixtures.item(plain, 4)
        let style = RenderStyle.standard
        for strength in [1.0, 0.5] {
            let image = try render(plain.markingChanges(added: [4], changed: [], strength: strength))
            let expected = RenderFixtures.over(
                style.addedFill * Float(strength), SIMD4<Float>(0, 1, 0, 1))
            assertPixel(
                image.pixel(at: four.center), RenderFixtures.pixel(expected),
                "layer 4's green image under the tint at \(strength)")
        }
    }

    func test_C_REND_12_marksFadedOutDrawNothing() throws {
        let plain = try list()
        let faded = plain.markingChanges(added: [4], changed: [3, 7], strength: 0)
        XCTAssertEqual(try render(faded).bytes, try render(plain).bytes)
    }

    func test_C_REND_12_theSelectionsEdgeDrawsOverAChange() throws {
        let selected = try list(selected: 3)
        let three = try RenderFixtures.item(selected, 3)
        let unmarked = try render(selected)
        let marked = try render(selected.markingChanges(added: [], changed: [3], strength: 1))
        let edge = topEdge(three)
        assertPixel(
            marked.pixel(at: edge), unmarked.pixel(at: edge), "the selection's opaque edge on top")
        XCTAssertTrue(
            differ(marked.pixel(at: three.center), unmarked.pixel(at: three.center)),
            "the change's tint shows through the selection's")
    }

    /// The pictures a person approves (`Baselines/`): layers 6 and 8 new, layers 3 and 7 changed,
    /// layer 3 selected, at full strength, in 2D and 3D.
    func test_C_REND_12_theMarksMatchTheBaselineIn2D() throws {
        let list = try list(selected: 3).markingChanges(added: [6, 8], changed: [3, 7], strength: 1)
        try assertMatchesBaseline(try render(list), named: "C-REND-12-changes-2d")
    }

    func test_C_REND_12_theMarksMatchTheBaselineIn3D() throws {
        let list = try list(camera: .standard3D, selected: 3)
            .markingChanges(added: [6, 8], changed: [3, 7], strength: 1)
        try assertMatchesBaseline(try render(list), named: "C-REND-12-changes-3d")
    }
}
