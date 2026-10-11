import CutawayRender
import CutawayScene
import Metal
import XCTest

/// Measuring two layers, sampled where the scene says the lines are (C-REND-08).
final class MeasurementRenderTests: XCTestCase {
    private var renderer: Renderer!
    private var textures: TextureCache!
    private let style = RenderStyle.standard
    private let viewport = RenderFixtures.portrait

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        renderer = try Renderer(device: device)
        textures = TextureCache(device: device)
    }

    /// The `hierarchy` layers with the `layer-details` images, layer 3 selected, layer 8
    /// hovered and measured to.
    private func list(measuring: UInt64? = 8) throws -> DrawList {
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        return RenderFixtures.layout(try RenderFixtures.hierarchyLayers(textures: keys))
            .project(
                camera: .flat, viewport: viewport, selected: 3, hovered: 8, measuring: measuring)
    }

    private func render(_ list: DrawList, style: RenderStyle? = nil) throws -> RenderedImage {
        try renderer.renderImage(
            list, textures: textures, style: style ?? self.style,
            pixelWidth: Int(viewport.width), pixelHeight: Int(viewport.height))
    }

    private func along(_ segment: DrawSegment, _ distance: Double) -> ScenePoint {
        let dx = segment.to.x - segment.from.x, dy = segment.to.y - segment.from.y
        let length = (dx * dx + dy * dy).squareRoot()
        return ScenePoint(
            x: segment.from.x + dx * distance / length, y: segment.from.y + dy * distance / length)
    }

    private func middle(_ segment: DrawSegment) -> ScenePoint {
        ScenePoint(x: (segment.from.x + segment.to.x) / 2, y: (segment.from.y + segment.to.y) / 2)
    }

    /// The pixels around a point: a one-pixel line through it is among them.
    private func around(_ point: ScenePoint) -> [(x: Int, y: Int)] {
        let x = Int(point.x.rounded(.down)), y = Int(point.y.rounded(.down))
        return (-1...1).flatMap { dy in (-1...1).map { dx in (x + dx, y + dy) } }
    }

    private var measurePixel: Pixel { RenderFixtures.pixel(style.measure) }

    private func assertMeasured(
        _ point: ScenePoint, in image: RenderedImage, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let pixels = around(point).map { image.pixel(x: $0.x, y: $0.y) }
        XCTAssertTrue(
            pixels.contains { !differ($0, measurePixel) },
            "\(message): no \(measurePixel) among \(pixels)", file: file, line: line)
    }

    func test_C_REND_08_theLinesTicksAndBoxesAreInTheMeasuringColour() throws {
        let list = try list()
        let drawn = try XCTUnwrap(list.measurement)
        let image = try render(list)
        // Lines 0 to 7 are the boxes' edges; 8 is the distance across, 9 and 10 its ticks.
        assertMeasured(middle(drawn.lines[8]), in: image, "the line across")
        // The lower half of the tick at the start of the line across, clear of the
        // extension that ends there; without the ticks it is not the measuring colour.
        let tick = along(drawn.lines[9], 5)
        assertMeasured(tick, in: image, "a tick")
        var noTicks = list
        noTicks.measurement?.lines.removeSubrange(9...10)
        let withoutTicks = try render(noTicks)
        for p in around(tick) {
            XCTAssertTrue(
                differ(withoutTicks.pixel(x: p.x, y: p.y), measurePixel),
                "the measuring colour at \(p) without the ticks")
        }
        assertMeasured(middle(drawn.lines[4]), in: image, "the other layer's box")
        assertMeasured(middle(drawn.lines[1]), in: image, "the selected layer's box")
        assertMeasured(middle(drawn.lines[11]), in: image, "the line down")
    }

    func test_C_REND_08_theMeasuringColourDiffersFromTheBackgroundAndTheLayers() throws {
        let list = try list()
        let plain = try render(try self.list(measuring: nil))
        // Without measuring: every pixel around the selected (3), hovered (8) and a plain
        // (6) layer's left edge, a layout guide's and a view's mark, and the background.
        var others: [(String, Pixel)] = [
            ("background", RenderFixtures.pixel(style.background)),
            ("view's mark", RenderFixtures.pixel(style.endBorder)),
            ("guide's mark", RenderFixtures.pixel(style.guideBorder)),
        ]
        for (id, name) in [(UInt64(3), "selected"), (8, "hovered"), (6, "plain")] {
            let corners = try RenderFixtures.item(list, id).points
            let edge = ScenePoint(
                x: (corners[0].x + corners[2].x) / 2, y: (corners[0].y + corners[2].y) / 2)
            others += around(edge).map { (name, plain.pixel(x: $0.x, y: $0.y)) }
        }
        // Inside layer 3, its image under the selection's tint.
        others.append(("layer 3", plain.pixel(at: try RenderFixtures.item(list, 3).center)))
        for (name, pixel) in others {
            XCTAssertTrue(differ(pixel, measurePixel), "\(name) \(pixel) is the measuring colour")
        }
    }

    func test_C_REND_08_extensionsAreDashed() throws {
        let list = try list()
        let drawn = try XCTUnwrap(list.measurement)
        let image = try render(list)
        let plain = try render(try self.list(measuring: nil))
        // 4 points on, 3 off, from the start of the line.
        let dash = drawn.dashes[0]
        assertMeasured(along(dash, 2), in: image, "on a dash")
        for p in around(along(dash, 5.5)) {
            XCTAssertFalse(
                differ(image.pixel(x: p.x, y: p.y), plain.pixel(x: p.x, y: p.y)),
                "drawn in the gap at \(p)")
        }
    }

    func test_C_REND_08_withoutBordersTheMeasurementIsStillDrawn() throws {
        var noBorders = style
        noBorders.drawsBorders = false
        let list = try list()
        let image = try render(list, style: noBorders)
        assertMeasured(middle(try XCTUnwrap(list.measurement).lines[8]), in: image, "the line")
    }

    func test_C_REND_08_theMeasuringColourFollowsTheAppearance() {
        XCTAssertEqual(
            RenderStyle.preview(dark: true).measure,
            RenderStyle.premultiplied(255 / 255, 55 / 255, 95 / 255, 1))
        XCTAssertEqual(
            RenderStyle.preview(dark: false).measure,
            RenderStyle.premultiplied(224 / 255, 35 / 255, 78 / 255, 1))
        XCTAssertEqual(RenderStyle.standard.measure, RenderStyle.preview(dark: true).measure)
    }
}
