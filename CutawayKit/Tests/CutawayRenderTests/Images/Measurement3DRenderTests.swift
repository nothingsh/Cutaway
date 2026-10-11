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

    /// The same picture with all of the measurement but the links.
    private func withoutLinks(_ list: DrawList) -> DrawList {
        var list = list
        list.measurement?.links = []
        return list
    }

    private func render(_ list: DrawList) throws -> RenderedImage {
        try renderer.renderImage(
            list, textures: textures, style: style, pixelWidth: Int(viewport.width),
            pixelHeight: Int(viewport.height))
    }

    private func along(_ segment: DrawSegment, _ distance: Double) -> ScenePoint {
        let dx = segment.to.x - segment.from.x, dy = segment.to.y - segment.from.y
        let length = (dx * dx + dy * dy).squareRoot()
        return ScenePoint(
            x: segment.from.x + dx * distance / length, y: segment.from.y + dy * distance / length)
    }

    private func length(_ segment: DrawSegment) -> Double {
        let dx = segment.to.x - segment.from.x, dy = segment.to.y - segment.from.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private func pixel(at point: ScenePoint) -> (x: Int, y: Int) {
        (Int(point.x.rounded(.down)), Int(point.y.rounded(.down)))
    }

    /// Whether the pixels around a point are all in the picture.
    private func isInPicture(_ point: ScenePoint) -> Bool {
        point.x >= 2 && point.y >= 2 && point.x < viewport.width - 2
            && point.y < viewport.height - 2
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

    /// Whether the measuring colour is drawn around `point`: some pixel there is mostly that
    /// colour over `plain`. A slanted line is smoothed, so that no pixel need be wholly
    /// covered.
    private func isMeasured(
        around point: ScenePoint, in image: RenderedImage, plain: RenderedImage
    ) -> Bool {
        guard isInPicture(point) else {
            XCTFail("\(point) is outside the picture")
            return false
        }
        return around(point).contains { p in
            coverage(
                of: style.measure, in: image.pixel(x: p.x, y: p.y),
                over: plain.pixel(x: p.x, y: p.y))
                ?? 0 >= 0.5
        }
    }

    func test_C_REND_09_theLinksAreDottedInTheMeasuringColour() throws {
        let list = try list()
        let drawn = try XCTUnwrap(list.measurement)
        XCTAssertEqual(drawn.links.count, 4)
        let image = try render(list)
        let plain = try render(withoutLinks(list))
        for (index, link) in drawn.links.enumerated() {
            XCTAssertGreaterThan(length(link), 24, "link \(index) is long enough to sample")
            // Around the middle: 1.5 points on, 2.5 off, from the start of the line. A gap
            // within 4 points of the last dot is finer than the dashes, which draw 4 in a row.
            let first = (length(link) / 2 / 4).rounded(.down) * 4
            for on in [first + 0.75, first + 4.75] {
                XCTAssertTrue(
                    isMeasured(around: along(link, on), in: image, plain: plain),
                    "link \(index): a dot at \(on)")
            }
            let middle = along(link, first + 2.75)
            guard isInPicture(middle) else {
                XCTFail("link \(index): \(middle) is outside the picture")
                continue
            }
            let gap = pixel(at: middle)
            XCTAssertFalse(
                differ(image.pixel(x: gap.x, y: gap.y), plain.pixel(x: gap.x, y: gap.y)),
                "link \(index): drawn in the gap at \(first + 2.75)")
        }
    }

    func test_C_REND_09_theCopyAndTheLinesAreInTheMeasuringColour() throws {
        let list = try list()
        let drawn = try XCTUnwrap(list.measurement)
        let image = try render(list)
        let plain = try render(try self.list(measuring: nil))
        let extensions = drawn.measurement.distances.flatMap(\.extensions).count
        // The copy of layer 2's box on layer 3's level: dashed, 4 points on and 3 off from the
        // start; sampled on a dash about the middle, away from the links at the corners.
        for edge in drawn.dashes[extensions...] {
            let dash = (length(edge) / 2 / 7).rounded(.down) * 7 + 2
            XCTAssertTrue(
                isMeasured(around: along(edge, dash), in: image, plain: plain), "a copy's edge")
        }
        for (index, line) in drawn.distanceLines.enumerated() {
            let middle = along(line, length(line) / 2)
            XCTAssertTrue(
                isMeasured(around: middle, in: image, plain: plain), "distance \(index)")
        }
    }

    func test_C_REND_09_measurementIn3DMatchesTheBaseline() throws {
        try assertMatchesBaseline(try render(try list()), named: "C-REND-09-measurement-3d")
    }
}
