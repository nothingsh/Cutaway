import CutawayScene
import XCTest

/// The distances between two layers (C-SCENE-09), worked out in window coordinates and as
/// the camera sees them.
final class MeasurementTests: XCTestCase {
    private static let portrait = Viewport(width: 480, height: 900)

    private func fixtureLayout(
        expanded: Set<UInt64> = SceneFixtures.allIDs, focus: UInt64? = nil,
        showsHidden: Bool = false
    ) throws -> SceneLayout {
        SceneLayout(
            layers: try SceneFixtures.hierarchyLayers(), expanded: expanded, focus: focus,
            showsHidden: showsHidden)
    }

    private func point(_ x: Double, _ y: Double) -> ScenePoint {
        ScenePoint(x: x, y: y)
    }

    private func assertClose(
        _ actual: ScenePoint, _ expected: ScenePoint, _ message: String,
        accuracy: Double = 1e-9, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, "\(message) x", file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, "\(message) y", file: file, line: line)
    }

    private func assertDistance(
        _ distance: Distance, _ axis: Distance.Axis, _ value: Double, from start: ScenePoint,
        to end: ScenePoint, extensions: [Segment] = [], _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(distance.axis, axis, message, file: file, line: line)
        XCTAssertEqual(distance.value, value, accuracy: 1e-9, message, file: file, line: line)
        assertClose(distance.start, start, "\(message) start", file: file, line: line)
        assertClose(distance.end, end, "\(message) end", file: file, line: line)
        XCTAssertEqual(
            distance.extensions.count, extensions.count, "\(message) extensions", file: file,
            line: line)
        for (index, (a, e)) in zip(distance.extensions, extensions).enumerated() {
            assertClose(a.from, e.from, "\(message) extension \(index) from", file: file, line: line)
            assertClose(a.to, e.to, "\(message) extension \(index) to", file: file, line: line)
        }
    }

    // MARK: - Distances

    func test_C_SCENE_09_layersApartHaveTheGapOnEachAxis() throws {
        let measurement = try XCTUnwrap(try fixtureLayout().measurement(from: 3, to: 8))
        XCTAssertEqual(measurement.distances.count, 2)
        // Across at the middle of node 3, the shorter of the two heights; node 8 ends above
        // that line, so an extension runs down its right edge.
        assertDistance(
            measurement.distances[0], .horizontal, 26.5, from: point(70, 120),
            to: point(96.5, 120),
            extensions: [Segment(from: point(70, 40), to: point(70, 120))], "across")
        // Down at the middle of node 8, the narrower one; node 3 starts to its right.
        assertDistance(
            measurement.distances[1], .vertical, 68, from: point(40, 40), to: point(40, 108),
            extensions: [Segment(from: point(96.5, 108), to: point(40, 108))], "down")
        XCTAssertEqual(
            measurement.boxes,
            [
                SceneRect(x: 96.5, y: 108, width: 200, height: 24),
                SceneRect(x: 10, y: 10, width: 60, height: 30),
            ])
    }

    func test_C_SCENE_09_aLayerInsideAnotherHasEdgeToEdgeDistancesOnAllFourSides() throws {
        let measurement = try XCTUnwrap(try fixtureLayout().measurement(from: 3, to: 2))
        XCTAssertEqual(measurement.distances.count, 4)
        assertDistance(
            measurement.distances[0], .horizontal, 96.5, from: point(0, 120),
            to: point(96.5, 120), "left")
        assertDistance(
            measurement.distances[1], .horizontal, 96.5, from: point(296.5, 120),
            to: point(393, 120), "right")
        assertDistance(
            measurement.distances[2], .vertical, 108, from: point(196.5, 0),
            to: point(196.5, 108), "top")
        assertDistance(
            measurement.distances[3], .vertical, 720, from: point(196.5, 132),
            to: point(196.5, 852), "bottom")
    }

    func test_C_SCENE_09_aRotatedLayerIsMeasuredByTheBoxAroundItsCorners() throws {
        // Node 4's corners from the reference coordinates.
        let left = 21.5961894323342, right = 371.4038105676658
        let top = 147.05771365940052, bottom = 452.9422863405995
        let measurement = try XCTUnwrap(try fixtureLayout().measurement(from: 3, to: 4))
        XCTAssertEqual(measurement.distances.count, 3)
        assertDistance(
            measurement.distances[0], .horizontal, 96.5 - left, from: point(left, 120),
            to: point(96.5, 120),
            extensions: [Segment(from: point(left, top), to: point(left, 120))], "left")
        assertDistance(
            measurement.distances[1], .horizontal, right - 296.5, from: point(296.5, 120),
            to: point(right, 120),
            extensions: [Segment(from: point(right, top), to: point(right, 120))], "right")
        assertDistance(
            measurement.distances[2], .vertical, top - 132, from: point(196.5, 132),
            to: point(196.5, top), "gap")
        XCTAssertEqual(measurement.boxes[1].maxY, bottom, accuracy: 1e-9)
    }

    func test_C_SCENE_09_noMeasurementToItselfOrAnUnknownLayer() throws {
        let layout = try fixtureLayout()
        XCTAssertNil(layout.measurement(from: 3, to: 3), "itself")
        XCTAssertNil(layout.measurement(from: 3, to: 99), "to an unknown layer")
        XCTAssertNil(layout.measurement(from: 99, to: 3), "from an unknown layer")
    }

    func test_C_SCENE_09_layersThatTouchHaveOnlyTheSameSideDistances() {
        // Side by side, touching at x = 100; the second is taller and lower.
        let layout = SceneLayout(
            layers: [
                SceneFixtures.layer(1, x: 0, y: 0, width: 400, height: 400),
                SceneFixtures.layer(2, parent: 1, x: 50, y: 50, width: 50, height: 20),
                SceneFixtures.layer(3, parent: 1, x: 100, y: 60, width: 30, height: 100),
            ], expanded: [1, 2, 3])
        let measurement = layout.measurement(from: 2, to: 3)
        let distances = measurement?.distances ?? []
        // Across: the facing edges meet, so the gap is 0 and left out; left to left 50 and
        // right to right 30. Down: they overlap from 60 to 70; top to top 10, bottom to
        // bottom 90.
        XCTAssertEqual(distances.map(\.axis), [.horizontal, .horizontal, .vertical, .vertical])
        XCTAssertEqual(distances.map(\.value), [50, 30, 10, 90])
        // On the overlap's middle, y 65; across x, the overlap is just the edge at 100.
        XCTAssertEqual(distances[0].start, point(50, 65))
        XCTAssertEqual(distances[2].start, point(100, 50))
        XCTAssertEqual(distances[2].end, point(100, 60))
    }

    func test_C_SCENE_09_aDistanceThatRoundsToZeroIsLeftOut() {
        func distances(gap: Double) -> [Double] {
            let layout = SceneLayout(
                layers: [
                    SceneFixtures.layer(1, x: 0, y: 0, width: 400, height: 400),
                    SceneFixtures.layer(2, parent: 1, x: 0, y: 0, width: 100, height: 100),
                    SceneFixtures.layer(
                        3, parent: 1, x: 100 + gap, y: 0, width: 100, height: 100),
                ], expanded: [1, 2, 3])
            return layout.measurement(from: 2, to: 3)?.distances.map(\.value) ?? []
        }
        // Same top and bottom: no vertical distances at all.
        XCTAssertEqual(distances(gap: 0.04), [])
        XCTAssertEqual(distances(gap: 0.06).count, 1)
        XCTAssertEqual(distances(gap: 0.06).first ?? 0, 0.06, accuracy: 1e-9)
    }

    // MARK: - As the camera sees it

    /// The map from window coordinates to viewport points in 2D, read off node 2, which
    /// covers the window.
    private func flatMap(_ list: DrawList) throws -> (ScenePoint) -> ScenePoint {
        let window = try XCTUnwrap(list.items.first { $0.layerID == 2 })
        let origin = window.points[0], far = window.points[3]
        let sx = (far.x - origin.x) / 393, sy = (far.y - origin.y) / 852
        return { ScenePoint(x: origin.x + $0.x * sx, y: origin.y + $0.y * sy) }
    }

    func test_C_SCENE_09_theMeasurementIsPlacedLikeTheLayers() throws {
        let layout = try fixtureLayout()
        let list = layout.project(
            camera: .flat, viewport: Self.portrait, selected: 3, hovered: 8, measuring: 8)
        let drawn = try XCTUnwrap(list.measurement)
        let map = try flatMap(list)
        XCTAssertEqual(drawn.measurement, layout.measurement(from: 3, to: 8))

        // Two boxes of four edges, then per distance its line and a tick across each end.
        XCTAssertEqual(drawn.lines.count, 8 + 2 * 3)
        assertClose(drawn.lines[0].from, map(point(96.5, 108)), "box top from")
        assertClose(drawn.lines[0].to, map(point(296.5, 108)), "box top to")
        assertClose(drawn.lines[4].from, map(point(10, 10)), "other box top from")
        let across = drawn.lines[8]
        assertClose(across.from, map(point(70, 120)), "across from")
        assertClose(across.to, map(point(96.5, 120)), "across to")
        let tick = drawn.lines[9]
        assertClose(tick.from, ScenePoint(x: across.from.x, y: across.from.y - 3), "tick from")
        assertClose(tick.to, ScenePoint(x: across.from.x, y: across.from.y + 3), "tick to")
        let downTick = drawn.lines[13]
        let down = drawn.lines[11]
        assertClose(downTick.from, ScenePoint(x: down.to.x - 3, y: down.to.y), "down tick from")
        assertClose(downTick.to, ScenePoint(x: down.to.x + 3, y: down.to.y), "down tick to")

        XCTAssertEqual(drawn.dashes.count, 2)
        assertClose(drawn.dashes[0].from, map(point(70, 40)), "extension from")
        assertClose(drawn.dashes[0].to, map(point(70, 120)), "extension to")

        XCTAssertEqual(drawn.labels.map(\.value), [26.5, 68])
        XCTAssertEqual(drawn.labels.map(\.axis), [.horizontal, .vertical])
        assertClose(drawn.labels[0].middle, map(point(83.25, 120)), "label")

        // The clip points go with the viewport points, with a w of 1.
        let clip = across.clipFrom
        XCTAssertEqual(clip.w, 1)
        XCTAssertEqual(clip.x, across.from.x / Self.portrait.width * 2 - 1, accuracy: 1e-9)
        XCTAssertEqual(clip.y, 1 - across.from.y / Self.portrait.height * 2, accuracy: 1e-9)
    }

    func test_C_SCENE_09_zoomAndPanMoveTheLinesButNotTheValues() throws {
        let layout = try fixtureLayout()
        let plain = try XCTUnwrap(
            layout.project(
                camera: .flat, viewport: Self.portrait, selected: 3, hovered: 8, measuring: 8
            ).measurement)
        var camera = Camera.flat
        camera.zoom = 2
        camera.pan = ScenePoint(x: 30, y: -40)
        let moved = layout.project(
            camera: camera, viewport: Self.portrait, selected: 3, hovered: 8, measuring: 8)
        let drawn = try XCTUnwrap(moved.measurement)
        let map = try flatMap(moved)
        XCTAssertEqual(drawn.measurement, plain.measurement)
        XCTAssertEqual(drawn.labels.map(\.value), plain.labels.map(\.value))
        XCTAssertNotEqual(drawn.lines[8], plain.lines[8])
        assertClose(drawn.lines[8].from, map(point(70, 120)), "across from")
        // The ticks stay 6 points long.
        let tick = drawn.lines[9]
        XCTAssertEqual(tick.to.y - tick.from.y, 6, accuracy: 1e-9)
    }

    /// In 2D, and in 3D (C-SCENE-12) measuring to node 2, a level below the selection.
    private static let cameras: [(Camera, other: UInt64)] = [(.flat, 8), (.standard3D, 2)]

    func test_C_SCENE_09_onlyTwoDifferentLayersInThePictureAreMeasured() throws {
        let layout = try fixtureLayout()
        for (camera, other) in Self.cameras {
            func measured(_ layout: SceneLayout, _ selected: UInt64?, _ other: UInt64?) -> Bool {
                layout.project(
                    camera: camera, viewport: Self.portrait, selected: selected, hovered: other,
                    measuring: other
                ).measurement != nil
            }
            let label = "\(camera)"
            XCTAssertTrue(measured(layout, 3, other), label)
            XCTAssertFalse(measured(layout, 3, 3), "the selection itself, \(label)")
            XCTAssertFalse(measured(layout, nil, other), "nothing selected, \(label)")
            XCTAssertFalse(measured(layout, 3, nil), "nothing to measure to, \(label)")
            // Node 5 is hidden.
            XCTAssertFalse(measured(layout, 5, 3), "a hidden selection, \(label)")
            XCTAssertTrue(
                measured(try fixtureLayout(showsHidden: true), 5, 3), "shown as a ghost, \(label)")
            // Focused on node 4, node 3 is outside.
            XCTAssertFalse(
                measured(try fixtureLayout(focus: 4), 3, 4), "outside the focus, \(label)")
        }
    }

    func test_C_SCENE_09_measuringChangesNeitherTheLayersNorTheMarks() throws {
        let layout = try fixtureLayout()
        for (camera, other) in Self.cameras {
            let plain = layout.project(
                camera: camera, viewport: Self.portrait, selected: 3, hovered: other,
                marks: [.layer(4)])
            let measuring = layout.project(
                camera: camera, viewport: Self.portrait, selected: 3, hovered: other,
                marks: [.layer(4)], measuring: other)
            XCTAssertNil(plain.measurement, "\(camera)")
            XCTAssertNotNil(measuring.measurement, "\(camera)")
            XCTAssertEqual(measuring.items, plain.items, "\(camera)")
            XCTAssertEqual(measuring.marks, plain.marks, "\(camera)")
        }
    }
}
