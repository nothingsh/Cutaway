import CutawayRender
import CutawayScene
import Metal
import XCTest

/// How virtual and excluded nodes are drawn (C-REND-11), sampled on the `hierarchy` fixture:
/// the card 4 shows its green `solo`; its virtual nodes 10 to 12 have a dashed border and no
/// fill, so the card shows inside them; the payment card 13 and its label 14 are hatched.
final class VirtualNodeRenderTests: XCTestCase {
    private var renderer: Renderer!
    private var textures: TextureCache!
    private let viewport = RenderFixtures.portrait

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        renderer = try Renderer(device: device)
        textures = TextureCache(device: device)
    }

    private func layers() throws -> [SceneLayer] {
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        return try RenderFixtures.hierarchyLayers(textures: keys)
    }

    private func list(
        _ layers: [SceneLayer], selected: UInt64? = nil, hovered: UInt64? = nil
    ) -> DrawList {
        RenderFixtures.layout(layers)
            .project(camera: .flat, viewport: viewport, selected: selected, hovered: hovered)
    }

    private func render(_ list: DrawList, style: RenderStyle = .standard) throws -> RenderedImage {
        try renderer.renderImage(
            list, textures: textures, style: style, pixelWidth: Int(viewport.width),
            pixelHeight: Int(viewport.height))
    }

    /// `distance` viewport points along an item's top edge from its top left corner, then
    /// `inside` points towards its bottom edge.
    private func onTopEdge(
        _ item: DrawItem, distance: Double, inside: Double = 0
    ) -> ScenePoint {
        let a = item.points.topLeft, b = item.points.topRight, c = item.points.bottomLeft
        func unit(_ dx: Double, _ dy: Double) -> (Double, Double) {
            let length = (dx * dx + dy * dy).squareRoot()
            return (dx / length, dy / length)
        }
        let along = unit(b.x - a.x, b.y - a.y), down = unit(c.x - a.x, c.y - a.y)
        return ScenePoint(
            x: a.x + along.0 * distance + down.0 * inside,
            y: a.y + along.1 * distance + down.1 * inside)
    }

    func test_C_REND_11_aVirtualNodesBorderDiffersFromTwoPointsInside() throws {
        let list = list(try layers())
        // The badge 11 lies inside the card and row 10, away from their edges.
        let badge = try RenderFixtures.item(list, 11)
        XCTAssertNil(badge.texture)
        XCTAssertEqual(badge.content, .drawnByParent)
        let image = try render(list)
        // The dashes start at each corner, 4 points on.
        let border = image.pixel(at: onTopEdge(badge, distance: 2))
        let inside = image.pixel(at: onTopEdge(badge, distance: 2, inside: 2))
        assertPixel(inside, RenderFixtures.green, "the card's image shows inside")
        XCTAssertTrue(differ(border, inside), "\(border) on the border, \(inside) inside")
        // Between two dashes the card shows on the edge too.
        let gap = image.pixel(at: onTopEdge(badge, distance: 5.5))
        XCTAssertTrue(differ(gap, border), "the border is dashed")
    }

    /// The pixels along a row of the payment card 13 that is inside it, above its label 14 and
    /// away from its border, at one pixel per point.
    private func hatchRow(_ image: RenderedImage, _ list: DrawList) throws -> [Pixel] {
        let card = try RenderFixtures.item(list, 13)
        return stride(from: 20.0, to: 280.0, by: 1).map {
            image.pixel(at: onTopEdge(card, distance: $0, inside: 8))
        }
    }

    func test_C_REND_11_anExcludedNodeAlternatesTwoColours() throws {
        let list = list(try layers())
        XCTAssertEqual(try RenderFixtures.item(list, 13).content, .excluded)
        let row = try hatchRow(try render(list), list)
        let style = RenderStyle.standard
        let first = RenderFixtures.pixel(style.hatch), second = RenderFixtures.pixel(style.hatchAlternate)
        XCTAssertTrue(differ(first, second))
        XCTAssertTrue(
            row.allSatisfy { !differ($0, first) || !differ($0, second) },
            "only the two colours: \(Set(row.map { "\($0)" }))")
        var changes = 0
        for (a, b) in zip(row, row.dropFirst()) where differ(a, b) { changes += 1 }
        XCTAssertGreaterThan(changes, 10, "in turn, many times across the card")
    }

    func test_C_REND_11_anExcludedNodeIsNotDrawnAsAFailedCapture() throws {
        var layers = try layers()
        let excluded = list(layers)
        let thirteen = try XCTUnwrap(layers.firstIndex { $0.id == 13 })
        layers[thirteen].content = .captured
        let failed = list(layers)
        let hatched = try hatchRow(try render(excluded), excluded)
        let plain = try hatchRow(try render(failed), failed)
        XCTAssertTrue(zip(hatched, plain).contains { differ($0, $1) })
    }

    func test_C_REND_11_highlightsDrawOverVirtualAndExcludedNodes() throws {
        let layers = try layers()
        for (id, distance) in [(UInt64(10), 120.0), (13, 120.0)] {
            func sample(_ list: DrawList) throws -> Pixel {
                try render(list).pixel(
                    at: onTopEdge(try RenderFixtures.item(list, id), distance: distance, inside: 10))
            }
            let plain = try sample(list(layers))
            let hovered = try sample(list(layers, hovered: id))
            let selected = try sample(list(layers, selected: id))
            XCTAssertTrue(differ(plain, hovered), "node \(id)")
            XCTAssertTrue(differ(plain, selected), "node \(id)")
            XCTAssertTrue(differ(hovered, selected), "node \(id)")
        }
    }

    /// The picture a person approves (`Baselines/`): the fixture in 2D by kind, row 10
    /// selected and row 12 hovered.
    func test_C_REND_11_virtualAndExcludedNodesMatchTheBaseline() throws {
        let list = list(try layers(), selected: 10, hovered: 12)
        try assertMatchesBaseline(
            try render(list, style: KindBorderRenderTests.byKind),
            named: "C-REND-11-virtual-and-excluded")
    }
}
