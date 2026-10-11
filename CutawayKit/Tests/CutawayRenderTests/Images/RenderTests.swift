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

    func test_C_REND_01_texturedLayersShowTheirImagesIn2D() throws {
        let list = try layerDetailsList(camera: .flat, viewport: RenderFixtures.portrait)
        let image = try render(list, RenderFixtures.portrait)
        assertPixel(image.pixel(at: try center(list, 3)), RenderFixtures.red, "layer 3")
        assertPixel(image.pixel(at: try center(list, 4)), RenderFixtures.green, "layer 4")
    }

    func test_C_REND_01_texturedLayersShowTheirImagesIn3D() throws {
        let list = try layerDetailsList(camera: .standard3D, viewport: RenderFixtures.square)
        let image = try render(list, RenderFixtures.square)
        assertPixel(image.pixel(at: try center(list, 3)), RenderFixtures.red, "layer 3")
        assertPixel(image.pixel(at: try center(list, 4)), RenderFixtures.green, "layer 4")
    }

    func test_C_REND_01_aLayerWithoutATextureIsNotFilledButOutlined() throws {
        let list = try layerDetailsList(camera: .flat, viewport: RenderFixtures.portrait)
        let image = try render(list, RenderFixtures.portrait)

        // Inside the scroll view (6), clear of its label (7): only the background.
        let inside = try RenderFixtures.flatPoint(list, x: 100, y: 650)
        assertPixel(image.pixel(at: inside), RenderFixtures.pixel(style.background), "inside 6")

        // On the scroll view's left edge, halfway down: the border over the background, on
        // one of the pixels the line can fall on.
        let corners = try RenderFixtures.item(list, 6).points
        let edge = ScenePoint(
            x: (corners[0].x + corners[2].x) / 2, y: (corners[0].y + corners[2].y) / 2)
        let expected = RenderFixtures.pixel(RenderFixtures.over(style.border, style.background))
        let candidates = (-1...1).map { dx in
            image.pixel(x: Int(edge.x.rounded(.down)) + dx, y: Int(edge.y.rounded(.down)))
        }
        XCTAssertTrue(
            candidates.contains { !differ($0, expected) },
            "no border \(expected) among \(candidates)")
    }

    func test_C_REND_01_aPaddedImageIsDrawnWithoutItsPadding() throws {
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details-edge", in: textures)
        let list = RenderFixtures.layout(try RenderFixtures.hierarchyLayers(textures: keys))
            .project(camera: .flat, viewport: RenderFixtures.portrait, selected: nil, hovered: nil)
        let image = try render(list, RenderFixtures.portrait)
        assertPixel(image.pixel(at: try center(list, 8)), RenderFixtures.orange, "layer 8")
        assertPixel(image.pixel(at: try center(list, 3)), RenderFixtures.red, "layer 3")
    }

    func test_C_REND_01_anImageOfAnotherSizeStillCoversTheBounds() throws {
        // A 2x image of layer 3: 400 × 48 red pixels on a 200 × 24 point layer.
        let key = TextureKey(layerID: 3, kind: .group, revision: 1)
        let redPixels = (0..<(400 * 48)).flatMap { _ -> [UInt8] in [0x00, 0x00, 0xFF, 0xFF] }
        textures.store(
            TextureImage(pixelWidth: 400, pixelHeight: 48, bytesPerRow: 1600, bytes: Data(redPixels)),
            for: key)
        let list = RenderFixtures.layout(
            try RenderFixtures.hierarchyLayers(textures: [3: LayerTextures(group: key)])
        ).project(camera: .flat, viewport: RenderFixtures.portrait, selected: nil, hovered: nil)
        let image = try render(list, RenderFixtures.portrait)
        let corners = try RenderFixtures.item(list, 3).points
        // Three pixels in from each corner, towards the middle, clear of the border.
        for (corner, inward) in zip(corners, [(3.0, 3.0), (-3.0, 3.0), (3.0, -3.0), (-3.0, -3.0)]) {
            let point = ScenePoint(x: corner.x + inward.0, y: corner.y + inward.1)
            assertPixel(image.pixel(at: point), RenderFixtures.red, "near \(corner)")
        }
    }

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

    func test_C_REND_01_anEmptyListDrawsTheBackground() throws {
        let image = try renderer.renderImage(
            .empty, textures: textures, style: style, pixelWidth: 4, pixelHeight: 3)
        XCTAssertEqual(image.bytes.count, 4 * 3 * 4)
        for y in 0..<3 {
            for x in 0..<4 {
                assertPixel(image.pixel(x: x, y: y), RenderFixtures.pixel(style.background))
            }
        }
    }

    /// The app's preview follows the system's appearance; the standard style, which the
    /// baselines are drawn with, stays as it was.
    func test_C_REND_01_thePreviewsBackgroundFollowsTheAppearance() throws {
        let expected = [
            true: Pixel(blue: 27, green: 25, red: 25, alpha: 255),
            false: Pixel(blue: 233, green: 230, red: 230, alpha: 255),
        ]
        for (dark, pixel) in expected {
            let image = try renderer.renderImage(
                .empty, textures: textures, style: .preview(dark: dark),
                pixelWidth: 2, pixelHeight: 2)
            assertPixel(image.pixel(x: 1, y: 1), pixel, tolerance: 1, "dark: \(dark)")
        }
        XCTAssertEqual(RenderStyle.standard.background, RenderStyle.premultiplied(0.165, 0.165, 0.176, 1))
    }

    func test_C_REND_01_onALightPreviewTheBordersAreDark() {
        let light = RenderStyle.preview(dark: false)
        let dark = RenderStyle.preview(dark: true)
        // Premultiplied: the colour over its alpha.
        XCTAssertLessThan(light.border.x / light.border.w, 0.2)
        XCTAssertEqual(dark.border, RenderStyle.standard.border)
        for style in [light, dark] {
            XCTAssertEqual(style.selectedFill, RenderStyle.standard.selectedFill)
            XCTAssertEqual(style.selectedBorder, RenderStyle.standard.selectedBorder)
            XCTAssertEqual(style.hoveredFill, RenderStyle.standard.hoveredFill)
            XCTAssertEqual(style.hoveredBorder, RenderStyle.standard.hoveredBorder)
            XCTAssertEqual(style.ghostFill, RenderStyle.standard.ghostFill)
            XCTAssertEqual(style.ghostBorder, RenderStyle.standard.ghostBorder)
            XCTAssertTrue(style.drawsBorders)
        }
        XCTAssertFalse(RenderStyle.preview(dark: true, drawsBorders: false).drawsBorders)
    }

    func test_C_REND_01_aTargetWithoutPixelsIsRefused() {
        XCTAssertThrowsError(
            try renderer.renderImage(
                .empty, textures: textures, style: style, pixelWidth: 0, pixelHeight: 10)
        ) { error in
            XCTAssertEqual(error as? RenderError, .invalidSize(width: 0, height: 10))
        }
    }

    func test_C_REND_01_aTargetLargerThanATextureIsRefused() {
        let side = Renderer.maxTextureDimension(of: renderer.device) + 1
        XCTAssertThrowsError(
            try renderer.renderImage(
                .empty, textures: textures, style: style, pixelWidth: side, pixelHeight: 1)
        ) { error in
            XCTAssertEqual(error as? RenderError, .invalidSize(width: side, height: 1))
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

    func test_C_REND_02_opacityScalesTheImage() throws {
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        var layers = try RenderFixtures.hierarchyLayers(textures: keys)
        layers[2].opacity = 0.5
        let list = RenderFixtures.layout(layers)
            .project(camera: .flat, viewport: RenderFixtures.portrait, selected: nil, hovered: nil)
        let image = try render(list, RenderFixtures.portrait)
        assertPixel(
            image.pixel(at: try center(list, 3)),
            RenderFixtures.pixel(
                RenderFixtures.over(RenderFixtures.opaqueRed * 0.5, style.background)))
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

    // MARK: - C-REND-03: highlights

    func test_C_REND_03_selectedHoveredAndPlainDiffer() throws {
        var samples: [Pixel] = []
        let states: [(selected: UInt64?, hovered: UInt64?)] = [(nil, nil), (4, nil), (nil, 4)]
        for state in states {
            let list = try layerDetailsList(
                camera: .flat, viewport: RenderFixtures.portrait, selected: state.selected,
                hovered: state.hovered)
            let image = try render(list, RenderFixtures.portrait)
            samples.append(image.pixel(at: try center(list, 4)))
        }
        assertPixel(samples[0], RenderFixtures.green, "plain")
        XCTAssertTrue(differ(samples[0], samples[1]), "plain \(samples[0]), selected \(samples[1])")
        XCTAssertTrue(differ(samples[0], samples[2]), "plain \(samples[0]), hovered \(samples[2])")
        XCTAssertTrue(differ(samples[1], samples[2]), "selected \(samples[1]), hovered \(samples[2])")
        let green = SIMD4<Float>(0, 1, 0, 1)
        assertPixel(
            samples[1], RenderFixtures.pixel(RenderFixtures.over(style.selectedFill, green)),
            "selected")
        assertPixel(
            samples[2], RenderFixtures.pixel(RenderFixtures.over(style.hoveredFill, green)),
            "hovered")
    }

    // MARK: - C-REND-06: ghosts and borders

    func test_C_REND_06_aGhostDiffersFromTheLayerShownAndFromTheBackground() throws {
        let viewport = RenderFixtures.portrait
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        let layers = try RenderFixtures.hierarchyLayers(textures: keys)
        let ghosts = SceneLayout(
            layers: layers, expanded: Set(layers.map(\.id)), showsHidden: true)
            .project(camera: .flat, viewport: viewport, selected: nil, hovered: nil)
        var shownLayers = layers
        let five = try XCTUnwrap(shownLayers.firstIndex { $0.id == 5 })
        shownLayers[five].isHidden = false
        let shown = RenderFixtures.layout(shownLayers)
            .project(camera: .flat, viewport: viewport, selected: nil, hovered: nil)

        let point = try center(ghosts, 5)
        XCTAssertEqual(point, try center(shown, 5), "the same place either way")
        let asGhost = try render(ghosts, viewport).pixel(at: point)
        let asShown = try render(shown, viewport).pixel(at: point)
        XCTAssertTrue(differ(asGhost, asShown), "\(asGhost) and \(asShown)")
        XCTAssertTrue(differ(asGhost, RenderFixtures.pixel(style.background)))
    }

    func test_C_REND_06_aGhostWithAnImageShowsItHalfAsStrong() throws {
        // Layer 3 (red) made hidden: its image at half strength over the background.
        let viewport = RenderFixtures.portrait
        let keys = try RenderFixtures.storeDetails(scenario: "layer-details", in: textures)
        var layers = try RenderFixtures.hierarchyLayers(textures: keys)
        let three = try XCTUnwrap(layers.firstIndex { $0.id == 3 })
        layers[three].isHidden = true
        let list = SceneLayout(layers: layers, expanded: Set(layers.map(\.id)), showsHidden: true)
            .project(camera: .flat, viewport: viewport, selected: nil, hovered: nil)
        let image = try render(list, viewport)
        let halfRed = RenderFixtures.over(
            RenderStyle.premultiplied(1, 0, 0, style.ghostImageOpacity), style.background)
        let expected = RenderFixtures.pixel(RenderFixtures.over(style.ghostFill, halfRed))
        assertPixel(image.pixel(at: try center(list, 3)), expected)
    }

    func test_C_PREV_09_withoutBordersOnlyTheHighlightsAreOutlined() throws {
        var plain = style
        plain.drawsBorders = false
        let list = try layerDetailsList(
            camera: .flat, viewport: RenderFixtures.portrait, selected: 8)
        let image = try render(list, RenderFixtures.portrait, style: plain)

        // Layer 6's left edge, halfway down, over layers without images: only background.
        let corners = try RenderFixtures.item(list, 6).points
        let edge = ScenePoint(
            x: (corners[0].x + corners[2].x) / 2, y: (corners[0].y + corners[2].y) / 2)
        for dx in -1...1 {
            assertPixel(
                image.pixel(x: Int(edge.x.rounded(.down)) + dx, y: Int(edge.y.rounded(.down))),
                RenderFixtures.pixel(style.background), "dx \(dx)")
        }
        // The selected layer 8 keeps its border.
        let selected = try RenderFixtures.item(list, 8).points
        let selectedEdge = ScenePoint(
            x: (selected[0].x + selected[2].x) / 2, y: (selected[0].y + selected[2].y) / 2)
        let bordered = (-1...1).map { dx in
            image.pixel(
                x: Int(selectedEdge.x.rounded(.down)) + dx, y: Int(selectedEdge.y.rounded(.down)))
        }
        // The border itself, not the selection's tint beside it.
        let border = RenderFixtures.pixel(style.selectedBorder)
        XCTAssertTrue(
            bordered.contains { !differ($0, border) }, "no border \(border) among \(bordered)")
    }

    /// Four corners in a draw item's order, from a list of them.
    private func quad<Point>(_ corners: [Point]) -> Corners<Point> {
        Corners(corners[0], corners[1], corners[2], corners[3])
    }
}
