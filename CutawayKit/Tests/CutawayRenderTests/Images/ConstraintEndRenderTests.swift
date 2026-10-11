import CutawayRender
import CutawayScene
import Metal
import XCTest

/// The marks on the other ends of the selected layer's constraints, sampled where the scene
/// says they are (C-REND-07).
final class ConstraintEndRenderTests: XCTestCase {
    /// The safe area of layer 2 in the `layout-constraints` fixture.
    static let safeArea = SceneRect(x: 0, y: 59, width: 393, height: 759)
    /// Layer 3's ends in the `layout-constraints` fixture.
    static let layer3Ends: [SceneMark] = [.layer(2), .area(safeArea, in: 2), .layer(4)]

    private var renderer: Renderer!
    private var textures: TextureCache!
    private let style = RenderStyle.standard
    private let viewport = RenderFixtures.portrait

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        renderer = try Renderer(device: device)
        textures = TextureCache(device: device)
    }

    /// The `hierarchy` layers with the `layer-details` images, layer 3 selected and layer 6
    /// hovered.
    private func list(marks: [SceneMark] = layer3Ends) throws -> DrawList {
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        return RenderFixtures.layout(try RenderFixtures.hierarchyLayers(textures: keys))
            .project(camera: .flat, viewport: viewport, selected: 3, hovered: 6, marks: marks)
    }

    private func render(_ list: DrawList, style: RenderStyle? = nil) throws -> RenderedImage {
        try renderer.renderImage(
            list, textures: textures, style: style ?? self.style,
            pixelWidth: Int(viewport.width), pixelHeight: Int(viewport.height))
    }

    /// The point `distance` viewport points from `from` towards `to`.
    private func along(_ from: ScenePoint, _ to: ScenePoint, _ distance: Double) -> ScenePoint {
        let length = ((to.x - from.x) * (to.x - from.x) + (to.y - from.y) * (to.y - from.y))
            .squareRoot()
        return ScenePoint(
            x: from.x + (to.x - from.x) * distance / length,
            y: from.y + (to.y - from.y) * distance / length)
    }

    private func midpoint(_ a: ScenePoint, _ b: ScenePoint) -> ScenePoint {
        ScenePoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// The pixels around a point: a one-pixel line through it is among them.
    private func around(_ point: ScenePoint) -> [(x: Int, y: Int)] {
        let x = Int(point.x.rounded(.down)), y = Int(point.y.rounded(.down))
        return (-1...1).flatMap { dy in (-1...1).map { dx in (x + dx, y + dy) } }
    }

    private func color(_ pixel: Pixel) -> SIMD4<Float> {
        SIMD4(Float(pixel.red), Float(pixel.green), Float(pixel.blue), Float(pixel.alpha)) / 255
    }

    /// What the guide's border makes of a pixel. The one-pixel line on the guide's edge may
    /// fall just inside its tint or just outside it.
    private func guideBorder(over pixel: Pixel) -> [Pixel] {
        [
            RenderFixtures.pixel(RenderFixtures.over(style.guideBorder, color(pixel))),
            RenderFixtures.pixel(
                RenderFixtures.over(
                    style.guideBorder, RenderFixtures.over(style.guideFill, color(pixel)))),
        ]
    }

    /// How much of a pixel a line of `color` (premultiplied) covers over `below`: 1 for the
    /// whole pixel, less where a smoothed line crosses only part of it. Nil when the pixel is
    /// not that colour over that background, within the tolerance.
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

    /// Whether a view's mark is drawn around `point`: some pixel there is mostly the mark's
    /// colour over the picture without marks. A slanted line is smoothed, so that no pixel
    /// need be wholly covered.
    private func isViewEnd(
        around point: ScenePoint, in image: RenderedImage, plain: RenderedImage
    ) -> Bool {
        around(point).contains { p in
            coverage(
                of: style.endBorder, in: image.pixel(x: p.x, y: p.y),
                over: plain.pixel(x: p.x, y: p.y)) ?? 0 >= 0.75
        }
    }

    private func guideFill(over pixel: Pixel) -> Pixel {
        RenderFixtures.pixel(RenderFixtures.over(style.guideFill, color(pixel)))
    }

    /// Whether the pixel at `p` is the guide's border, judged against the picture without
    /// marks.
    private func isGuideBorder(
        _ p: (x: Int, y: Int), in image: RenderedImage, plain: RenderedImage
    ) -> Bool {
        let pixel = image.pixel(x: p.x, y: p.y)
        return guideBorder(over: plain.pixel(x: p.x, y: p.y)).contains { !differ(pixel, $0) }
    }

    func test_C_REND_07_theEndsDifferFromTheSelectedHoveredAndPlainBordersAndFromEachOther()
        throws
    {
        let list = try list()
        let image = try render(list)
        let plain = try render(try self.list(marks: []))
        XCTAssertEqual(list.marks.count, 3)

        // Layer 4's mark: the middle of its top edge, which is slanted.
        let four = list.marks[2].points
        let viewEnd = RenderFixtures.pixel(style.endBorder)
        let top = midpoint(four[0], four[1])
        XCTAssertTrue(
            isViewEnd(around: top, in: image, plain: plain),
            "no \(viewEnd) among \(around(top).map { image.pixel(x: $0.x, y: $0.y) })")

        // The safe area's top edge, on a dash: 72 points from its top left (dashes are 4
        // points on, 3 off, from each edge's start).
        let guide = list.marks[1].points
        let dash = try XCTUnwrap(
            around(along(guide[0], guide[1], 72)).first {
                isGuideBorder($0, in: image, plain: plain)
            },
            "no dash of the guide's border")
        let guidePixel = image.pixel(x: dash.x, y: dash.y)
        XCTAssertTrue(differ(guidePixel, viewEnd), "guide \(guidePixel), view \(viewEnd)")

        // Every pixel around the selected (3), hovered (6) and a plain (8) layer's left edge.
        for (id, name) in [(UInt64(3), "selected"), (6, "hovered"), (8, "plain")] {
            let corners = try RenderFixtures.item(list, id).points
            for p in around(midpoint(corners[0], corners[2])) {
                let pixel = image.pixel(x: p.x, y: p.y)
                XCTAssertTrue(differ(pixel, viewEnd), "\(name) \(pixel) at \(p) is the view's mark")
                XCTAssertTrue(differ(pixel, guidePixel), "\(name) \(pixel) at \(p) is the guide's mark")
            }
        }
    }

    func test_C_REND_07_aGuidesBorderIsDashedOverItsFill() throws {
        let list = try list()
        let image = try render(list)
        let plain = try render(try self.list(marks: []))
        let guide = list.marks[1].points

        // 75.5 points along the top edge is in a gap: no border there, and the tint just
        // inside the edge.
        let gap = along(guide[0], guide[1], 75.5)
        for p in around(gap) {
            XCTAssertFalse(isGuideBorder(p, in: image, plain: plain), "border at \(p)")
        }
        let below = ScenePoint(x: gap.x, y: gap.y + 3)
        assertPixel(image.pixel(at: below), guideFill(over: plain.pixel(at: below)), "below the gap")
        // Inside the guide, over layer 3, the fill is over the layers.
        let inside = try RenderFixtures.item(list, 3).center
        assertPixel(
            image.pixel(at: inside), guideFill(over: plain.pixel(at: inside)), "over layer 3")
    }

    func test_C_REND_07_aMarkIsDrawnOverTheLayersAboveItsOwn() throws {
        // The red layer 1 is under the translucent blue layer 2; its mark is not.
        let keys = try RenderFixtures.storeBlendingImages(in: textures)
        let list = RenderFixtures.layout(
            RenderFixtures.blendingLayers(red: keys.red, blue: keys.blue))
            .project(camera: .flat, viewport: viewport, selected: nil, hovered: nil, marks: [.layer(1)])
        let image = try render(list)
        let one = list.marks[0].points
        let viewEnd = RenderFixtures.pixel(style.endBorder)
        let pixels = around(midpoint(one[0], one[1])).map { image.pixel(x: $0.x, y: $0.y) }
        XCTAssertTrue(pixels.contains { !differ($0, viewEnd) }, "no \(viewEnd) among \(pixels)")
    }

    func test_C_REND_07_withoutBordersTheEndsAreStillMarked() throws {
        var noBorders = style
        noBorders.drawsBorders = false
        let list = try list()
        let image = try render(list, style: noBorders)
        let plain = try render(try self.list(marks: []), style: noBorders)
        let four = list.marks[2].points
        let top = midpoint(four[0], four[1])
        XCTAssertTrue(
            isViewEnd(around: top, in: image, plain: plain),
            "no \(style.endBorder) among \(around(top).map { image.pixel(x: $0.x, y: $0.y) })")
    }

    func test_C_REND_07_theMarksFollowTheAppearance() {
        let purple = (dark: SIMD3<Float>(191, 90, 242) / 255, light: SIMD3<Float>(154, 63, 208) / 255)
        for (dark, rgb, fill) in [(true, purple.dark, Float(0.12)), (false, purple.light, 0.1)] {
            let style = RenderStyle.preview(dark: dark)
            XCTAssertEqual(style.endBorder, RenderStyle.premultiplied(rgb.x, rgb.y, rgb.z, 1))
            XCTAssertEqual(style.guideFill, RenderStyle.premultiplied(rgb.x, rgb.y, rgb.z, fill))
            XCTAssertEqual(style.guideBorder, RenderStyle.premultiplied(rgb.x, rgb.y, rgb.z, 0.8))
        }
        XCTAssertEqual(RenderStyle.standard.endBorder, RenderStyle.preview(dark: true).endBorder)
        XCTAssertNotEqual(RenderStyle.preview(dark: true), RenderStyle.preview(dark: false))
    }
}
