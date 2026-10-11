import CutawayScene
import Foundation
import simd
import XCTest

/// The camera and the draw list (C-SCENE-04), and how images map onto layers (C-SCENE-06).
final class CameraTests: XCTestCase {
    private let viewport = Viewport(width: 480, height: 900)

    private func fixtureLayout() throws -> SceneLayout {
        SceneLayout(layers: try SceneFixtures.hierarchyLayers(), expanded: SceneFixtures.allIDs)
    }

    /// Written here, not taken from the code under test: the scale at which the content box
    /// fits the viewport with `Camera.margin` to spare.
    private func fit(_ box: SceneRect, _ viewport: Viewport) -> Double {
        let width = viewport.width - 2 * Camera.margin
        let height = viewport.height - 2 * Camera.margin
        return min(width / box.size.width, height / box.size.height)
    }

    /// An independent version of the projection, with simd matrices: the levels centred in
    /// depth, the camera at the content's half-diagonal over tan(fov / 2), and the projected
    /// corners fitted into the viewport.
    private func referencePoints(
        _ layout: SceneLayout, ids: [UInt64], _ camera: Camera, _ viewport: Viewport
    ) -> [UInt64: [ScenePoint]] {
        let box = layout.contentBox!
        let levels = ids.map { Double(layout.level(of: $0)!) }
        let top = levels.max()!
        let depth = top * camera.layerSpacing
        let radius =
            (box.size.width * box.size.width + box.size.height * box.size.height + depth * depth)
                .squareRoot() / 2
        let distance = radius > 0 ? radius / tan(Camera.fieldOfView / 2) : 1
        let (cy, sy) = (cos(camera.yaw), sin(camera.yaw))
        let (cp, sp) = (cos(camera.pitch), sin(camera.pitch))
        let yaw = simd_double3x3(rows: [SIMD3(cy, 0, sy), SIMD3(0, 1, 0), SIMD3(-sy, 0, cy)])
        let pitch = simd_double3x3(rows: [SIMD3(1, 0, 0), SIMD3(0, cp, sp), SIMD3(0, -sp, cp)])

        var seen: [UInt64: [SIMD2<Double>]] = [:]
        for (id, level) in zip(ids, levels) {
            let quad = layout.quad(of: id)!
            seen[id] = [quad.topLeft, quad.topRight, quad.bottomLeft, quad.bottomRight].map {
                let v = pitch * (yaw * SIMD3(
                    $0.x - box.center.x, $0.y - box.center.y,
                    (level - top / 2) * camera.layerSpacing))
                let factor = camera.projection == .perspective ? distance / (distance - v.z) : 1
                return SIMD2(v.x, v.y) * factor
            }
        }
        let all = seen.values.flatMap { $0 }
        let low = all.reduce(all[0]) { simd_min($0, $1) }
        let high = all.reduce(all[0]) { simd_max($0, $1) }
        let size = high - low
        let middle = (low + high) / 2
        let scale = min(
            (viewport.width - 2 * Camera.margin) / size.x,
            (viewport.height - 2 * Camera.margin) / size.y) * camera.zoom
        return seen.mapValues { points in
            points.map {
                ScenePoint(
                    x: viewport.width / 2 + camera.pan.x + ($0.x - middle.x) * scale,
                    y: viewport.height / 2 + camera.pan.y + ($0.y - middle.y) * scale)
            }
        }
    }

    /// At a viewport point, 1/w of the item's surface: 1/w is affine across the screen, so
    /// it interpolates with plain barycentric weights. Larger is nearer. Nil when the point
    /// is not on the item.
    private func inverseDepth(_ item: DrawItem, at p: ScenePoint) -> Double? {
        for (a, b, c) in [(0, 1, 3), (0, 3, 2)] {
            let pa = item.points[a], pb = item.points[b], pc = item.points[c]
            let det = (pb.x - pa.x) * (pc.y - pa.y) - (pc.x - pa.x) * (pb.y - pa.y)
            guard abs(det) > 1e-9 else { continue }
            let u = ((p.x - pa.x) * (pc.y - pa.y) - (pc.x - pa.x) * (p.y - pa.y)) / det
            let v = ((pb.x - pa.x) * (p.y - pa.y) - (p.x - pa.x) * (pb.y - pa.y)) / det
            guard u >= 0, v >= 0, u + v <= 1 else { continue }
            return (1 - u - v) / item.corners[a].w + u / item.corners[b].w
                + v / item.corners[c].w
        }
        return nil
    }

    private func item(_ list: DrawList, _ id: UInt64) -> DrawItem? {
        list.items.first { $0.layerID == id }
    }

    private func assertClose(
        _ a: ScenePoint, _ b: ScenePoint, accuracy: Double = 1e-6, _ message: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, message, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, message, file: file, line: line)
    }

    // MARK: - Orthographic

    func test_C_SCENE_04_theFlatCameraCentersTheContentWithAMargin() throws {
        let list = try fixtureLayout().project(
            camera: .flat, viewport: viewport, selected: nil, hovered: nil)
        let window = try XCTUnwrap(item(list, 1))
        let scale = fit(SceneRect(x: 0, y: 0, width: 393, height: 852), viewport)

        assertClose(window.points[0], ScenePoint(x: 240 - 196.5 * scale, y: 450 - 426 * scale))
        assertClose(window.points[3], ScenePoint(x: 240 + 196.5 * scale, y: 450 + 426 * scale))
        // The height is what limits: 20 points above and below, more at the sides.
        XCTAssertEqual(window.points[0].y, 20, accuracy: 1e-9)
        XCTAssertEqual(window.points[3].y, 880, accuracy: 1e-9)
        XCTAssertGreaterThan(window.points[0].x, 20)
    }

    func test_C_SCENE_04_zoomScalesAboutTheViewportCenter() throws {
        let layout = try fixtureLayout()
        var zoomed = Camera.flat
        zoomed.zoom = 2
        let flat = layout.project(camera: .flat, viewport: viewport, selected: nil, hovered: nil)
        let near = layout.project(camera: zoomed, viewport: viewport, selected: nil, hovered: nil)
        XCTAssertEqual(flat.items.count, near.items.count)
        for (a, b) in zip(flat.items, near.items) {
            for (p, q) in zip(a.points, b.points) {
                assertClose(q, ScenePoint(x: 240 + 2 * (p.x - 240), y: 450 + 2 * (p.y - 450)))
            }
        }
    }

    func test_C_SCENE_04_panMovesEverything() throws {
        let layout = try fixtureLayout()
        var moved = Camera.flat
        moved.pan = ScenePoint(x: 30, y: -10)
        let flat = layout.project(camera: .flat, viewport: viewport, selected: nil, hovered: nil)
        let panned = layout.project(camera: moved, viewport: viewport, selected: nil, hovered: nil)
        XCTAssertEqual(flat.items.count, panned.items.count)
        for (a, b) in zip(flat.items, panned.items) {
            for (p, q) in zip(a.points, b.points) {
                assertClose(q, ScenePoint(x: p.x + 30, y: p.y - 10))
            }
        }
    }

    // MARK: - Perspective

    func test_C_SCENE_04_perspectiveWithoutTurnOrSpacingMatchesOrthographic() throws {
        let layout = try fixtureLayout()
        var camera = Camera.flat
        camera.projection = .perspective
        let flat = layout.project(camera: .flat, viewport: viewport, selected: nil, hovered: nil)
        let deep = layout.project(camera: camera, viewport: viewport, selected: nil, hovered: nil)
        XCTAssertEqual(flat.items.map(\.layerID), deep.items.map(\.layerID))
        for (a, b) in zip(flat.items, deep.items) {
            for (p, q) in zip(a.points, b.points) { assertClose(p, q, accuracy: 1e-9) }
        }
    }

    func test_C_SCENE_04_anyCameraMatchesTheReferenceProjection() throws {
        let layout = try fixtureLayout()
        let ids: [UInt64] = [1, 2, 3, 4, 6, 7, 8]
        let angles = [-170.0, -90, -30, 0, 15, 30, 89, 170].map { $0 * .pi / 180 }
        for projection in [Projection.orthographic, .perspective] {
            for yaw in angles {
                for pitch in angles {
                    for (zoom, spacing) in [(0.5, 0.0), (1, 20), (3, 75)] {
                        let camera = Camera(
                            projection: projection, yaw: yaw, pitch: pitch, zoom: zoom,
                            pan: ScenePoint(x: 25, y: -40), layerSpacing: spacing)
                        let list = layout.project(
                            camera: camera, viewport: viewport, selected: nil, hovered: nil)
                        let expected = referencePoints(layout, ids: ids, camera, viewport)
                        for id in ids {
                            let label = "layer \(id), \(camera)"
                            guard let actual = item(list, id) else {
                                XCTFail("missing: \(label)")
                                continue
                            }
                            for (p, q) in zip(actual.points, expected[id]!) {
                                assertClose(p, q, label)
                            }
                        }
                    }
                }
            }
        }
    }

    func test_C_SCENE_04_clipCoordinatesAgreeWithViewportPoints() throws {
        let list = try fixtureLayout().project(
            camera: .standard3D, viewport: viewport, selected: nil, hovered: nil)
        XCTAssertFalse(list.items.isEmpty)
        for item in list.items {
            for (clip, point) in zip(item.corners, item.points) {
                XCTAssertGreaterThan(clip.w, 0)
                XCTAssertEqual(clip.x / clip.w, point.x / 480 * 2 - 1, accuracy: 1e-9)
                XCTAssertEqual(clip.y / clip.w, 1 - point.y / 900 * 2, accuracy: 1e-9)
                XCTAssertEqual(clip.z / clip.w, 0.5, accuracy: 1e-9)
            }
        }
    }

    func test_C_SCENE_04_theStandard3DCameraIsAsDesigned() {
        let camera = Camera.standard3D
        XCTAssertEqual(camera.projection, .perspective)
        XCTAssertEqual(camera.yaw, .pi / 6, accuracy: 1e-12)
        XCTAssertEqual(camera.pitch, .pi / 12, accuracy: 1e-12)
        XCTAssertEqual(camera.zoom, 1)
        XCTAssertEqual(camera.pan, .zero)
        XCTAssertEqual(camera.layerSpacing, 50)
        XCTAssertEqual(Camera.flat.projection, .orthographic)
        XCTAssertEqual(Camera.flat.layerSpacing, 0)
    }

    // MARK: - Order

    func test_C_SCENE_04_fromTheFrontLevelsGoUpAndFromBehindTheyGoDown() throws {
        let layout = try fixtureLayout()
        func levels(_ yaw: Double) -> [Int] {
            var camera = Camera.standard3D
            camera.yaw = yaw * .pi / 180
            return layout.project(camera: camera, viewport: viewport, selected: nil, hovered: nil)
                .items.map { layout.level(of: $0.layerID)! }
        }
        XCTAssertEqual(levels(30).count, 7)
        XCTAssertEqual(levels(30), levels(30).sorted())
        XCTAssertEqual(levels(150).count, 7)
        XCTAssertEqual(levels(150), levels(150).sorted(by: >))
    }

    func test_C_SCENE_04_inTwoDimensionsTheOrderKeepsTheWiresOrderForOverlappingLayers() throws {
        let list = try fixtureLayout().project(
            camera: .flat, viewport: viewport, selected: nil, hovered: nil)
        // By level, then by the wire: 1 (0), 2 (1), 3, 4, 6, 8 (2), 7 (3). Layer 9 has no area.
        XCTAssertEqual(list.items.map(\.layerID), [1, 2, 3, 4, 6, 8, 7])
    }

    func test_C_SCENE_04_nearerSurfacesAreDrawnLaterForAnyPerspectiveCamera() {
        // Painter's order, checked against depth: wherever two items cover the same point,
        // the one drawn later is the nearer there. The deep stack puts the eye between level
        // planes when the camera looks at it almost edge on.
        let layouts = [
            ("fixture", try! fixtureLayout()),
            ("40 nested", SceneLayout(
                layers: SceneFixtures.nestedScreens(40), expanded: Set(1...40))),
        ]
        let angles = [-170.0, -120, -85, -60, 0, 45, 80, 85, 89, 135].map { $0 * .pi / 180 }
        var overlaps = 0
        for (name, layout) in layouts {
            for yaw in angles {
                for pitch in [-100.0, -20, 0, 15, 95].map({ $0 * .pi / 180 }) {
                    for spacing in [20.0, 75] {
                        let camera = Camera(
                            projection: .perspective, yaw: yaw, pitch: pitch, zoom: 1,
                            pan: .zero, layerSpacing: spacing)
                        let list = layout.project(
                            camera: camera, viewport: viewport, selected: nil, hovered: nil)
                        for x in stride(from: 3.37, to: 480, by: 31) {
                            for y in stride(from: 2.41, to: 900, by: 31) {
                                let p = ScenePoint(x: x, y: y)
                                let covering = list.items.compactMap { item in
                                    inverseDepth(item, at: p).map { (item.layerID, $0) }
                                }
                                guard let last = covering.last, covering.count > 1 else {
                                    continue
                                }
                                overlaps += 1
                                let nearest = covering.map(\.1).max()!
                                XCTAssertEqual(
                                    last.1, nearest, accuracy: 1e-9,
                                    "\(name) at \(p): layer \(last.0) is drawn last, \(camera)")
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(overlaps, 10_000)
    }

    func test_C_SCENE_04_aDeepStackFitsTheViewportIn3D() {
        for count in [40, 100] {
            let layout = SceneLayout(
                layers: SceneFixtures.nestedScreens(count), expanded: Set(1...UInt64(count)))
            for size in [Viewport(width: 900, height: 900), Viewport(width: 600, height: 700)] {
                let list = layout.project(
                    camera: .standard3D, viewport: size, selected: nil, hovered: nil)
                XCTAssertEqual(list.items.count, count, "\(count) levels in \(size)")
                let points = list.items.flatMap(\.points)
                let xs = points.map(\.x), ys = points.map(\.y)
                let label = "\(count) levels in \(size)"
                XCTAssertGreaterThanOrEqual(xs.min()!, Camera.margin - 1e-6, label)
                XCTAssertLessThanOrEqual(xs.max()!, size.width - Camera.margin + 1e-6, label)
                XCTAssertGreaterThanOrEqual(ys.min()!, Camera.margin - 1e-6, label)
                XCTAssertLessThanOrEqual(ys.max()!, size.height - Camera.margin + 1e-6, label)
                // Fitted, not just inside: one way or the other it reaches both margins.
                let fillsWidth = abs(xs.min()! - Camera.margin) < 1e-6
                    && abs(xs.max()! - (size.width - Camera.margin)) < 1e-6
                let fillsHeight = abs(ys.min()! - Camera.margin) < 1e-6
                    && abs(ys.max()! - (size.height - Camera.margin)) < 1e-6
                XCTAssertTrue(fillsWidth || fillsHeight, label)
            }
        }
    }

    func test_C_SCENE_04_zoomDoesNotPushLayersThroughTheCamera() throws {
        let layout = try fixtureLayout()
        var camera = Camera.flat
        camera.projection = .perspective
        camera.layerSpacing = 75
        camera.yaw = 0.3
        let near = layout.project(camera: camera, viewport: viewport, selected: nil, hovered: nil)
        camera.zoom = 50
        let far = layout.project(camera: camera, viewport: viewport, selected: nil, hovered: nil)
        XCTAssertEqual(far.items.map(\.layerID), near.items.map(\.layerID))
        XCTAssertEqual(far.items.count, 7)
        for (a, b) in zip(near.items, far.items) {
            for (p, q) in zip(a.points, b.points) {
                assertClose(q, ScenePoint(x: 240 + 50 * (p.x - 240), y: 450 + 50 * (p.y - 450)))
            }
            for (c, d) in zip(a.corners, b.corners) { XCTAssertEqual(c.w, d.w, accuracy: 1e-12) }
        }
    }

    // MARK: - Edge cases

    func test_C_SCENE_04_nothingDisplayedGivesAnEmptyList() {
        let empty = SceneLayout(layers: [], expanded: [])
        XCTAssertEqual(
            empty.project(camera: .standard3D, viewport: viewport, selected: nil, hovered: nil),
            .empty)
        let hidden = SceneLayout(
            layers: [SceneFixtures.layer(1, x: 0, y: 0, width: 10, height: 10, hidden: true)],
            expanded: [1])
        XCTAssertEqual(
            hidden.project(camera: .flat, viewport: viewport, selected: nil, hovered: nil), .empty)
    }

    func test_C_SCENE_04_aViewportWithoutAreaGivesAnEmptyList() throws {
        let layout = try fixtureLayout()
        for size in [Viewport(width: 0, height: 0), Viewport(width: 100, height: 0)] {
            XCTAssertEqual(
                layout.project(camera: .standard3D, viewport: size, selected: nil, hovered: nil),
                .empty)
        }
    }

    func test_C_SCENE_04_contentWithoutAreaIsNotScaledToInfinity() throws {
        // Layers without area are not drawn, so a scene of nothing else is empty.
        let point = SceneLayout(
            layers: [SceneFixtures.layer(1, x: 30, y: 40, width: 0, height: 0)], expanded: [1])
        let line = SceneLayout(
            layers: [SceneFixtures.layer(1, x: 0, y: 0, width: 100, height: 0)], expanded: [1])
        for layout in [point, line] {
            XCTAssertNil(layout.contentBox)
            XCTAssertEqual(
                layout.project(camera: .standard3D, viewport: viewport, selected: nil, hovered: nil),
                .empty)
        }

        // Seen edge on, what the camera sees has no width: it is fitted by its height.
        var edgeOn = Camera.flat
        edgeOn.yaw = .pi / 2
        let list = try fixtureLayout().project(
            camera: edgeOn, viewport: viewport, selected: nil, hovered: nil)
        XCTAssertEqual(list.items.count, 7)
        let points = list.items.flatMap(\.points)
        XCTAssertTrue(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        XCTAssertEqual(points.map(\.y).min()!, 20, accuracy: 1e-9)
        XCTAssertEqual(points.map(\.y).max()!, 880, accuracy: 1e-9)
    }

    // MARK: - Highlight, image, opacity (C-SCENE-06)

    func test_C_SCENE_04_selectionWinsOverHover() throws {
        let layout = try fixtureLayout()
        let list = layout.project(camera: .flat, viewport: viewport, selected: 3, hovered: 4)
        XCTAssertEqual(item(list, 3)?.highlight, .selected)
        XCTAssertEqual(item(list, 4)?.highlight, .hovered)
        XCTAssertEqual(item(list, 2)?.highlight, Highlight.none)
        let both = layout.project(camera: .flat, viewport: viewport, selected: 3, hovered: 3)
        XCTAssertEqual(item(both, 3)?.highlight, .selected)
        let hidden = layout.project(camera: .flat, viewport: viewport, selected: 5, hovered: nil)
        XCTAssertFalse(hidden.items.contains { $0.highlight != .none }, "5 is not drawn")
    }

    func test_C_SCENE_06_theImageSitsOnTheBoundsCornersWithTheLayersOpacity() throws {
        let solo = SceneFixtures.solo(4)
        var layers = try SceneFixtures.hierarchyLayers(textures: [4: LayerTextures(solo: solo)])
        layers[3].opacity = 0.5
        let layout = SceneLayout(layers: layers, expanded: SceneFixtures.allIDs)
        let list = layout.project(camera: .flat, viewport: viewport, selected: nil, hovered: nil)
        let card = try XCTUnwrap(item(list, 4))

        XCTAssertEqual(card.texture, solo)
        XCTAssertEqual(card.opacity, 0.5)
        // Corners in the order top left, top right, bottom left, bottom right of the bounds:
        // the texture coordinates (0,0), (1,0), (0,1), (1,1) go with them.
        let quad = try XCTUnwrap(layout.quad(of: 4))
        let scale = fit(try XCTUnwrap(layout.contentBox), viewport)
        let corners = [quad.topLeft, quad.topRight, quad.bottomLeft, quad.bottomRight]
        XCTAssertEqual(card.points.count, 4)
        XCTAssertEqual(card.corners.count, 4)
        for (point, corner) in zip(card.points, corners) {
            assertClose(
                point,
                ScenePoint(x: 240 + (corner.x - 196.5) * scale, y: 450 + (corner.y - 426) * scale))
        }
        assertClose(
            card.center,
            ScenePoint(
                x: 240 + (quad.center.x - 196.5) * scale, y: 450 + (quad.center.y - 426) * scale))
    }

    // MARK: - C-PREV-04 to 06: moving the camera

    func test_C_PREV_04_draggingRightAndDownTurnsTheLeftAndTopEdgesTowardsTheViewer() {
        let turned = Camera.standard3D.rotated(byDragOf: 10, 20)
        let step = Camera.rotationPerPoint
        XCTAssertEqual(turned.yaw, Camera.standard3D.yaw + 10 * step, accuracy: 1e-12)
        XCTAssertEqual(turned.pitch, Camera.standard3D.pitch + 20 * step, accuracy: 1e-12)
        XCTAssertEqual(turned.zoom, 1)
        XCTAssertEqual(turned.layerSpacing, 50)
    }

    func test_C_PREV_04_theTiltStopsAtAQuarterTurn() {
        XCTAssertEqual(Camera.standard3D.rotated(byDragOf: 0, 10_000).pitch, .pi / 2)
        XCTAssertEqual(Camera.standard3D.rotated(byDragOf: 0, -10_000).pitch, -.pi / 2)
    }

    func test_C_PREV_04_theTurnWrapsAround() {
        let points = 2 * .pi / Camera.rotationPerPoint  // one whole turn
        let turned = Camera.standard3D.rotated(byDragOf: points + 30, 0)
        XCTAssertEqual(
            turned.yaw, Camera.standard3D.yaw + 30 * Camera.rotationPerPoint, accuracy: 1e-9)
        XCTAssertLessThan(turned.yaw, .pi)
        XCTAssertGreaterThanOrEqual(turned.yaw, -.pi)
    }

    func test_C_PREV_06_panningMovesEveryCornerByThePoints() throws {
        let layout = try fixtureLayout()
        for camera in [Camera.flat, Camera.standard3D] {
            let before = layout.project(
                camera: camera, viewport: viewport, selected: nil, hovered: nil)
            let after = layout.project(
                camera: camera.panned(by: 12, -7), viewport: viewport, selected: nil, hovered: nil)
            for (a, b) in zip(before.items, after.items) {
                for (p, q) in zip(a.points, b.points) {
                    XCTAssertEqual(q.x - p.x, 12, accuracy: 1e-9)
                    XCTAssertEqual(q.y - p.y, -7, accuracy: 1e-9)
                }
            }
        }
    }

    func test_C_PREV_05_zoomKeepsWhatIsUnderThePointer() throws {
        let layout = try fixtureLayout()
        for camera in [Camera.flat, Camera.standard3D] {
            let list = layout.project(
                camera: camera, viewport: viewport, selected: nil, hovered: nil)
            // Three corners: of the label, the rotated card, and the scroll view's label.
            for (id, corner) in [(3, 0), (4, 3), (7, 1)] as [(UInt64, Int)] {
                let pointer = try XCTUnwrap(list.items.first { $0.layerID == id }).points[corner]
                for factor in [0.5, 2, 3.7] {
                    let zoomed = layout.project(
                        camera: camera.zoomed(by: factor, about: pointer, in: viewport),
                        viewport: viewport, selected: nil, hovered: nil)
                    let moved =
                        try XCTUnwrap(zoomed.items.first { $0.layerID == id }).points[corner]
                    let what = "\(camera) \(id) × \(factor)"
                    XCTAssertEqual(moved.x, pointer.x, accuracy: 0.5, what)
                    XCTAssertEqual(moved.y, pointer.y, accuracy: 0.5, what)
                }
            }
        }
    }

    func test_C_PREV_05_zoomStaysWithinItsRange() {
        let pointer = ScenePoint(x: 100, y: 200)
        let big = Camera.flat.zoomed(by: 50, about: pointer, in: viewport)
        XCTAssertEqual(big.zoom, 10)
        // Limited to 10 times, the pan follows the limited ratio, not the asked one.
        XCTAssertEqual(big.pan.x, (100 - 240) - (100 - 240) * 10, accuracy: 1e-9)
        XCTAssertEqual(Camera.flat.zoomed(by: 0.001, about: pointer, in: viewport).zoom, 0.1)
        let atLimit = big.zoomed(by: 2, about: pointer, in: viewport)
        XCTAssertEqual(atLimit, big, "nothing moves at the limit")
    }

    func test_C_PREV_05_aZoomWithoutAViewportOrAFactorDoesNothing() {
        let pointer = ScenePoint(x: 1, y: 1)
        XCTAssertEqual(
            Camera.flat.zoomed(by: 2, about: pointer, in: Viewport(width: 0, height: 0)), .flat)
        XCTAssertEqual(Camera.flat.zoomed(by: .nan, about: pointer, in: viewport), .flat)
        XCTAssertEqual(Camera.flat.zoomed(by: 0, about: pointer, in: viewport), .flat)
    }
}
