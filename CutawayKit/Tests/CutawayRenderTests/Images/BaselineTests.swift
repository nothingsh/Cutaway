import CutawayRender
import CutawayScene
import Metal
import XCTest

/// The approved pictures in `Baselines/`, each drawn again and compared with its file.
final class BaselineTests: XCTestCase {
    private var renderer: Renderer!
    private var textures: TextureCache!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        renderer = try Renderer(device: device)
        textures = TextureCache(device: device)
    }

    private func render(_ list: DrawList, _ viewport: Viewport) throws -> RenderedImage {
        try renderer.renderImage(
            list, textures: textures, style: .standard, pixelWidth: Int(viewport.width),
            pixelHeight: Int(viewport.height))
    }

    private func layerDetails(
        _ camera: Camera, _ viewport: Viewport, selected: UInt64? = nil, hovered: UInt64? = nil
    ) throws -> RenderedImage {
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        let list = RenderFixtures.layout(try RenderFixtures.hierarchyLayers(textures: keys))
            .project(camera: camera, viewport: viewport, selected: selected, hovered: hovered)
        return try render(list, viewport)
    }

    func test_C_REND_01_theLayerDetailsMatchTheBaselineIn2D() throws {
        try assertMatchesBaseline(
            try layerDetails(.flat, RenderFixtures.portrait), named: "C-REND-01-layer-details-2d")
    }

    func test_C_REND_01_theLayerDetailsMatchTheBaselineIn3D() throws {
        try assertMatchesBaseline(
            try layerDetails(.standard3D, RenderFixtures.square),
            named: "C-REND-01-layer-details-3d")
    }

    func test_C_REND_02_blendingMatchesTheBaseline() throws {
        let keys = try RenderFixtures.storeBlendingImages(in: textures)
        try assertMatchesBaseline(
            try render(
                RenderFixtures.blendingList(red: keys.red, blue: keys.blue),
                RenderFixtures.portrait),
            named: "C-REND-02-blending")
    }

    func test_C_REND_03_highlightsMatchTheBaseline() throws {
        try assertMatchesBaseline(
            try layerDetails(.flat, RenderFixtures.portrait, selected: 3, hovered: 4),
            named: "C-REND-03-highlights")
    }

    func test_C_REND_07_constraintEndsMatchTheBaseline() throws {
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        let list = RenderFixtures.layout(try RenderFixtures.hierarchyLayers(textures: keys))
            .project(
                camera: .flat, viewport: RenderFixtures.portrait, selected: 3, hovered: 6,
                marks: ConstraintEndRenderTests.layer3Ends)
        try assertMatchesBaseline(
            try render(list, RenderFixtures.portrait), named: "C-REND-07-constraint-ends")
    }

    func test_C_REND_08_measurementMatchesTheBaseline() throws {
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        let list = RenderFixtures.layout(try RenderFixtures.hierarchyLayers(textures: keys))
            .project(
                camera: .flat, viewport: RenderFixtures.portrait, selected: 3, hovered: 8,
                measuring: 8)
        try assertMatchesBaseline(
            try render(list, RenderFixtures.portrait), named: "C-REND-08-measurement")
    }

    /// The comparison itself: a PNG written and read back is the same image, so a baseline
    /// can only differ because the drawing changed.
    func test_C_REND_01_aPictureSurvivesBeingWrittenAndRead() throws {
        let image = try layerDetails(.flat, RenderFixtures.portrait, selected: 3, hovered: 4)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cutaway-baseline-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try pngData(image).write(to: url)
        XCTAssertEqual(try readPNG(url), image)
    }

    func test_C_REND_06_ghostsMatchTheBaseline() throws {
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        let layers = try RenderFixtures.hierarchyLayers(textures: keys)
        let list = SceneLayout(layers: layers, expanded: Set(layers.map(\.id)), showsHidden: true)
            .project(camera: .flat, viewport: RenderFixtures.portrait, selected: nil, hovered: nil)
        try assertMatchesBaseline(
            try render(list, RenderFixtures.portrait), named: "C-REND-06-hidden-layers")
    }

    func test_C_REND_06_noBordersMatchesTheBaseline() throws {
        var plain = RenderStyle.standard
        plain.drawsBorders = false
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        let list = RenderFixtures.layout(try RenderFixtures.hierarchyLayers(textures: keys))
            .project(camera: .flat, viewport: RenderFixtures.portrait, selected: nil, hovered: nil)
        try assertMatchesBaseline(
            try renderer.renderImage(
                list, textures: textures, style: plain,
                pixelWidth: Int(RenderFixtures.portrait.width),
                pixelHeight: Int(RenderFixtures.portrait.height)),
            named: "C-REND-06-no-borders")
    }
}
