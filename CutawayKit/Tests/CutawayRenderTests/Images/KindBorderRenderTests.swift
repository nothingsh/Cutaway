import CutawayRender
import CutawayScene
import Metal
import XCTest

/// Borders by kind (C-REND-10, C-PREV-17), sampled on the edges of the `hierarchy` fixture's
/// layers: node 4 (`Demo.CardView`, the app's own class), node 3 (`UILabel`, the system's)
/// and node 8 (a layer alone).
final class KindBorderRenderTests: XCTestCase {
    /// The kinds' colours in the dark appearance, as the interface gives them (sRGB).
    static let windowColor = RenderStyle.premultiplied(94 / 255, 92 / 255, 230 / 255, 1)
    static let controllerColor = RenderStyle.premultiplied(255 / 255, 159 / 255, 10 / 255, 1)
    static let textColor = RenderStyle.premultiplied(10 / 255, 132 / 255, 255 / 255, 1)
    static let scrollColor = RenderStyle.premultiplied(191 / 255, 90 / 255, 242 / 255, 1)
    static let containerColor = RenderStyle.premultiplied(152 / 255, 152 / 255, 157 / 255, 1)
    static let virtualColor = RenderStyle.premultiplied(0 / 255, 218 / 255, 195 / 255, 1)

    /// The standard style with the borders by kind, as the interface sets them for the
    /// fixture: strong for the app's own classes (the controller's root view 2, the card 4,
    /// its virtual nodes 10 to 12, the payment card 13), faint for the system's, the layers
    /// alone (5, 8) left plain.
    static var byKind: RenderStyle {
        var style = RenderStyle.standard
        style.borderColors = [
            1: windowColor * 0.42, 2: controllerColor * 0.95, 3: textColor * 0.42,
            4: containerColor * 0.95, 6: scrollColor * 0.42, 7: textColor * 0.42,
            9: containerColor * 0.42, 10: virtualColor * 0.95, 11: virtualColor * 0.95,
            12: virtualColor * 0.95, 13: containerColor * 0.95, 14: textColor * 0.42,
        ]
        style.bordersRecede = true
        return style
    }

    private var renderer: Renderer!
    private var textures: TextureCache!
    private let viewport = RenderFixtures.portrait

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        renderer = try Renderer(device: device)
        textures = TextureCache(device: device)
    }

    /// The `hierarchy` layers with the `layer-details` images, layer 6 selected and layer 7
    /// hovered unless `highlights` is false.
    private func list(marks: [SceneMark] = [], highlights: Bool = true) throws -> DrawList {
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        return RenderFixtures.layout(try RenderFixtures.hierarchyLayers(textures: keys))
            .project(
                camera: .flat, viewport: viewport, selected: highlights ? 6 : nil,
                hovered: highlights ? 7 : nil, marks: marks)
    }

    /// The picture a person approves (`Baselines/`): the `hierarchy` fixture in 3D, by kind.
    func test_C_REND_10_bordersByKindMatchTheBaseline() throws {
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        let list = RenderFixtures.layout(try RenderFixtures.hierarchyLayers(textures: keys))
            .project(
                camera: .standard3D, viewport: RenderFixtures.square, selected: nil, hovered: nil)
        try assertMatchesBaseline(
            try renderer.renderImage(
                list, textures: textures, style: Self.byKind,
                pixelWidth: Int(RenderFixtures.square.width),
                pixelHeight: Int(RenderFixtures.square.height)),
            named: "C-REND-10-borders-by-kind")
    }
}
