import CutawayRender
import CutawayScene
import CutawayTestSupport
import Metal
import XCTest

/// Offscreen drawing, sampled where the scene says the layers are (C-REND-01 to 03).
final class RenderTests: XCTestCase {
    private var renderer: Renderer!
    private var textures: TextureCache!
    private let style = RenderStyle.standard

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        renderer = try Renderer(device: device)
        textures = TextureCache(device: device)
    }

    private func render(
        _ list: DrawList, _ viewport: Viewport, style: RenderStyle? = nil
    ) throws -> RenderedImage {
        try renderer.renderImage(
            list, textures: textures, style: style ?? self.style,
            pixelWidth: Int(viewport.width), pixelHeight: Int(viewport.height))
    }

    /// The `hierarchy` layers with the `layer-details` images.
    private func layerDetailsList(
        camera: Camera, viewport: Viewport, selected: UInt64? = nil, hovered: UInt64? = nil
    ) throws -> DrawList {
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        return RenderFixtures.layout(try RenderFixtures.hierarchyLayers(textures: keys))
            .project(camera: camera, viewport: viewport, selected: selected, hovered: hovered)
    }

    private func center(_ list: DrawList, _ id: UInt64) throws -> ScenePoint {
        try RenderFixtures.item(list, id).center
    }

    // MARK: - C-REND-01: images and borders

    func test_C_REND_01_aShrunkenImageIsAveragedInsteadOfShowingMoire() throws {
        // A checkerboard of single black and white pixels, 256 × 256, drawn about 3.6 times
        // smaller than its pixels: every pixel should come out the board's average grey.
        let key = TextureKey(layerID: 1, kind: .solo, revision: 1)
        let side = 256
        var board = Data(count: side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let value: UInt8 = (x + y).isMultiple(of: 2) ? 0xFF : 0x00
                let at = (y * side + x) * 4
                board[at] = value
                board[at + 1] = value
                board[at + 2] = value
                board[at + 3] = 0xFF
            }
        }
        textures.store(
            TextureImage(pixelWidth: side, pixelHeight: side, bytesPerRow: side * 4, bytes: board),
            for: key)
        let target = 80, inset = 0.9
        let clip = [(-inset, inset), (inset, inset), (-inset, -inset), (inset, -inset)]
        let points = clip.map { x, y in
            ScenePoint(x: (x + 1) / 2 * Double(target), y: (1 - y) / 2 * Double(target))
        }
        let item = DrawItem(
            layerID: 1, corners: quad(clip.map { ClipPoint(x: $0.0, y: $0.1, z: 0.5, w: 1) }),
            points: quad(points), texture: key, opacity: 1, highlight: .none)
        let image = try renderer.renderImage(
            DrawList(items: [item]), textures: textures, style: style, pixelWidth: target,
            pixelHeight: target)

        // Inside the layer, clear of its border.
        let first = Int(points[0].x) + 4, last = Int(points[3].x) - 4
        var farthest = 0
        for y in first...last {
            for x in first...last {
                farthest = max(farthest, abs(Int(image.pixel(x: x, y: y).green) - 128))
            }
        }
        XCTAssertLessThanOrEqual(farthest, 12, "a pixel strays \(farthest) from grey")
    }

    func test_C_REND_01_anImageShrunkenOneWayStaysSharpTheOtherWay() throws {
        // Black and white bands 2 pixels tall, 512 × 128, drawn 8 times narrower but at full
        // height, as a layer seen from the side: the bands must stay apart, not turn grey.
        let key = TextureKey(layerID: 1, kind: .solo, revision: 1)
        let width = 512, height = 128
        var bands = Data(count: width * height * 4)
        for y in 0..<height {
            let value: UInt8 = (y / 2).isMultiple(of: 2) ? 0xFF : 0x00
            for x in 0..<width {
                let at = (y * width + x) * 4
                bands[at] = value
                bands[at + 1] = value
                bands[at + 2] = value
                bands[at + 3] = 0xFF
            }
        }
        textures.store(
            TextureImage(pixelWidth: width, pixelHeight: height, bytesPerRow: width * 4, bytes: bands),
            for: key)
        let targetWidth = 80, targetHeight = 160, inset = 0.8
        let clip = [(-inset, inset), (inset, inset), (-inset, -inset), (inset, -inset)]
        let points = clip.map { x, y in
            ScenePoint(
                x: (x + 1) / 2 * Double(targetWidth), y: (1 - y) / 2 * Double(targetHeight))
        }
        let item = DrawItem(
            layerID: 1, corners: quad(clip.map { ClipPoint(x: $0.0, y: $0.1, z: 0.5, w: 1) }),
            points: quad(points), texture: key, opacity: 1, highlight: .none)
        let image = try renderer.renderImage(
            DrawList(items: [item]), textures: textures, style: style, pixelWidth: targetWidth,
            pixelHeight: targetHeight)

        // Down the middle column, clear of the border: the bands' black and white both show.
        let column = targetWidth / 2
        let greens = (Int(points[0].y) + 4...Int(points[3].y) - 4).map {
            Int(image.pixel(x: column, y: $0).green)
        }
        XCTAssertGreaterThanOrEqual(greens.max() ?? 0, 200, "no white band: \(greens)")
        XCTAssertLessThanOrEqual(greens.min() ?? 255, 55, "no black band: \(greens)")
    }

    func test_C_REND_01_aTextureMissingFromTheCacheLeavesTheLayerUnfilled() throws {
        let key = TextureKey(layerID: 3, kind: .group, revision: 1)  // never stored
        let list = RenderFixtures.layout(
            try RenderFixtures.hierarchyLayers(textures: [3: LayerTextures(group: key)])
        ).project(camera: .flat, viewport: RenderFixtures.portrait, selected: nil, hovered: nil)
        let image = try render(list, RenderFixtures.portrait)
        assertPixel(image.pixel(at: try center(list, 3)), RenderFixtures.pixel(style.background))
    }

    func test_C_REND_01_aTargetWithoutPixelsOrLargerThanATextureIsRefused() {
        let tooLong = Renderer.maxTextureDimension(of: renderer.device) + 1
        for (width, height) in [(0, 10), (tooLong, 1)] {
            XCTAssertThrowsError(
                try renderer.renderImage(
                    .empty, textures: textures, style: style, pixelWidth: width,
                    pixelHeight: height)
            ) { error in
                XCTAssertEqual(error as? RenderError, .invalidSize(width: width, height: height))
            }
        }
    }

    func test_C_REND_01_twoThousandLayersAreDrawnWithinASecond() throws {
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
        // Nested full-screen views and small leaves, untextured: three draws each at most.
        var layers = [
            SceneLayer(
                id: 1, parentID: 0, bounds: SceneRect(x: 0, y: 0, width: 393, height: 852),
                position: .zero, anchorPoint: .zero),
        ]
        for index in 0..<20 {
            layers.append(
                SceneLayer(
                    id: UInt64(2 + index), parentID: UInt64(1 + index),
                    bounds: SceneRect(x: 0, y: 0, width: 393, height: 852), position: .zero,
                    anchorPoint: .zero))
        }
        for index in 0..<1979 {
            layers.append(
                SceneLayer(
                    id: UInt64(22 + index), parentID: 21,
                    bounds: SceneRect(x: 0, y: 0, width: 8, height: 8),
                    position: ScenePoint(x: Double(index % 40) * 9.8, y: Double(index / 40) * 9.8),
                    anchorPoint: .zero))
        }
        let list = RenderFixtures.layout(layers)
            .project(camera: .standard3D, viewport: RenderFixtures.square, selected: 3, hovered: 4)
        XCTAssertEqual(list.items.count, 2000)

        let start = ContinuousClock.now
        _ = try render(list, RenderFixtures.square)
        let elapsed = ContinuousClock.now - start
        print("RenderTests: drew 2000 layers in \(elapsed)")
        XCTAssertLessThan(elapsed, .seconds(1))
    }

    func test_C_REND_01_aListCommittedToAPassIsDrawn() throws {
        let device = renderer.device
        try XCTSkipUnless(device.supportsFamily(.apple7), "reads back a shared texture")
        let list = try layerDetailsList(camera: .flat, viewport: RenderFixtures.portrait)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Renderer.pixelFormat, width: 480, height: 900, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared
        let target = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = style.clearColor
        pass.colorAttachments[0].storeAction = .store

        let commands = try renderer.commit(
            list, textures: textures, style: style, to: pass, presenting: nil)
        commands.waitUntilCompleted()
        XCTAssertNil(commands.error)

        var bytes = Data(count: 480 * 900 * 4)
        bytes.withUnsafeMutableBytes { raw in
            target.getBytes(
                raw.baseAddress!, bytesPerRow: 480 * 4, from: MTLRegionMake2D(0, 0, 480, 900),
                mipmapLevel: 0)
        }
        let image = RenderedImage(pixelWidth: 480, pixelHeight: 900, bytes: bytes)
        assertPixel(image.pixel(at: try center(list, 3)), RenderFixtures.red, "layer 3")
        assertPixel(image.pixel(at: try center(list, 4)), RenderFixtures.green, "layer 4")
    }

    // MARK: - C-REND-02: premultiplied blending

    func test_C_REND_02_translucentBlueOverOpaqueRedBlendsPremultiplied() throws {
        let keys = try RenderFixtures.storeBlendingImages(in: textures)
        let list = RenderFixtures.blendingList(red: keys.red, blue: keys.blue)
        let image = try render(list, RenderFixtures.portrait)

        // 0x80 + 0 × (1 − 128/255), 0, 255 × (1 − 128/255), 128 + 255 × (1 − 128/255).
        assertPixel(
            image.pixel(at: try center(list, 1)),
            Pixel(blue: 128, green: 0, red: 127, alpha: 255), "blue over red")
        let beside = try RenderFixtures.flatPoint(list, x: 300, y: 500, window: 2)
        assertPixel(
            image.pixel(at: beside),
            RenderFixtures.pixel(
                RenderFixtures.over(RenderFixtures.translucentBlue, style.background)),
            "blue over the background")
    }

    func test_C_REND_02_opacityBeyondOneIsTakenAsOne() throws {
        // A translucent image shows the clamp: at opacity 3 unclamped, its premultiplied blue
        // would saturate to 255.
        let keys = try RenderFixtures.storeBlendingImages(in: textures)
        var layers = RenderFixtures.blendingLayers(red: keys.red, blue: keys.blue)
        layers[1].opacity = 3
        layers[0].opacity = -1
        let list = RenderFixtures.layout(layers)
            .project(camera: .flat, viewport: RenderFixtures.portrait, selected: nil, hovered: nil)
        let image = try render(list, RenderFixtures.portrait)
        let beside = try RenderFixtures.flatPoint(list, x: 300, y: 500, window: 2)
        assertPixel(
            image.pixel(at: beside),
            RenderFixtures.pixel(
                RenderFixtures.over(RenderFixtures.translucentBlue, style.background)),
            "opacity 3 is 1")
        // Opacity below 0 draws nothing of the red image; only the blue over the background.
        assertPixel(
            image.pixel(at: try center(list, 1)),
            RenderFixtures.pixel(
                RenderFixtures.over(RenderFixtures.translucentBlue, style.background)),
            "opacity −1 is 0")
    }

    func test_C_REND_01_theImagesCornersGoWithTheBoundsCorners() throws {
        // Four colours, one to a quarter, as in the app-icon fixture: red top left, green top
        // right, blue bottom left, clear bottom right; each quarter 2 × 2 pixels, so the
        // image is 4 × 4 on a 200 × 24 point layer: another size than the layer as well.
        let quarters: [[UInt8]] = [
            [0x00, 0x00, 0xFF, 0xFF], [0x00, 0xFF, 0x00, 0xFF],
            [0xFF, 0x00, 0x00, 0xFF], [0x00, 0x00, 0x00, 0x00],
        ]
        var bytes: [UInt8] = []
        for y in 0..<4 {
            for x in 0..<4 { bytes += quarters[(y / 2) * 2 + x / 2] }
        }
        let key = TextureKey(layerID: 3, kind: .group, revision: 1)
        textures.store(
            TextureImage(pixelWidth: 4, pixelHeight: 4, bytesPerRow: 16, bytes: Data(bytes)),
            for: key)
        let layers = try RenderFixtures.hierarchyLayers(textures: [3: LayerTextures(group: key)])
        for (camera, viewport) in [
            (Camera.flat, RenderFixtures.portrait), (Camera.standard3D, RenderFixtures.square),
        ] {
            let list = RenderFixtures.layout(layers)
                .project(camera: camera, viewport: viewport, selected: nil, hovered: nil)
            let image = try render(list, viewport)
            let item = try RenderFixtures.item(list, 3)
            // Where on the projected layer a point of the image lands, by the perspective-
            // correct mapping: weights by 1/w, then divide.
            func point(u: Double, v: Double) -> ScenePoint {
                let weights = [(1 - u) * (1 - v), u * (1 - v), (1 - u) * v, u * v]
                var x = 0.0, y = 0.0, total = 0.0
                for (weight, (p, c)) in zip(weights, zip(item.points, item.corners)) {
                    x += weight * p.x / c.w
                    y += weight * p.y / c.w
                    total += weight / c.w
                }
                return ScenePoint(x: x / total, y: y / total)
            }
            let label = "\(camera)"
            assertPixel(image.pixel(at: point(u: 0.12, v: 0.25)), RenderFixtures.red, "top left, \(label)")
            assertPixel(image.pixel(at: point(u: 0.88, v: 0.25)), RenderFixtures.green, "top right, \(label)")
            assertPixel(
                image.pixel(at: point(u: 0.12, v: 0.75)), Pixel(blue: 255, green: 0, red: 0, alpha: 255),
                "bottom left, \(label)")
            assertPixel(
                image.pixel(at: point(u: 0.88, v: 0.75)), RenderFixtures.pixel(style.background),
                "bottom right, \(label)")
        }
    }

    // MARK: - C-REND-06: ghosts and borders

    /// Four corners in a draw item's order, from a list of them.
    private func quad<Point>(_ corners: [Point]) -> Corners<Point> {
        Corners(corners[0], corners[1], corners[2], corners[3])
    }
}
