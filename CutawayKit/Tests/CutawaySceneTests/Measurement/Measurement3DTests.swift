import CutawayScene
import XCTest

/// The distances between two layers as a turned camera sees them (C-SCENE-12): the values of
/// 2D, the selected layer's box and the lines on its level, the other box on its own.
final class Measurement3DTests: XCTestCase {
    private static let portrait = Viewport(width: 480, height: 900)

    /// Where the bounds of each layer measured here start in the window, so that a window
    /// point can be given in the layer's bounds coordinates: none of them is transformed.
    private static let origins: [UInt64: ScenePoint] = [
        2: ScenePoint(x: 0, y: 0), 3: ScenePoint(x: 96.5, y: 108), 8: ScenePoint(x: 10, y: 10),
        // Scrolled down 100 points: bounds y 100 is drawn at window y 500.
        6: ScenePoint(x: 46.5, y: 400),
    ]

    private func fixtureLayout(
        focus: UInt64? = nil, showsHidden: Bool = false
    ) throws -> SceneLayout {
        SceneLayout(
            layers: try SceneFixtures.hierarchyLayers(), expanded: SceneFixtures.allIDs,
            focus: focus, showsHidden: showsHidden)
    }

    private func point(_ x: Double, _ y: Double) -> ScenePoint {
        ScenePoint(x: x, y: y)
    }

    private func assertClose(
        _ actual: ScenePoint, _ expected: ScenePoint, _ message: String,
        accuracy: Double = 1e-9, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(
            actual.x, expected.x, accuracy: accuracy, "\(message) x", file: file, line: line)
        XCTAssertEqual(
            actual.y, expected.y, accuracy: accuracy, "\(message) y", file: file, line: line)
    }

    private func assertClose(
        _ actual: ClipPoint, _ expected: ClipPoint, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for (a, e, name) in [
            (actual.x, expected.x, "x"), (actual.y, expected.y, "y"), (actual.z, expected.z, "z"),
            (actual.w, expected.w, "w"),
        ] {
            XCTAssertEqual(a, e, accuracy: 1e-9, "\(message) \(name)", file: file, line: line)
        }
    }

    private func measured(
        _ layout: SceneLayout, _ camera: Camera = .standard3D, from selected: UInt64 = 3,
        to other: UInt64, file: StaticString = #filePath, line: UInt = #line
    ) throws -> DrawMeasurement {
        try XCTUnwrap(
            layout.project(
                camera: camera, viewport: Self.portrait, selected: selected, hovered: other,
                measuring: other
            ).measurement, file: file, line: line)
    }

    /// A window point as the camera sees it on the level of layer `id`: a mark of no size
    /// there, which is placed on that level (C-LAYOUT-04).
    private func placed(
        _ p: ScenePoint, onLevelOf id: UInt64, _ layout: SceneLayout,
        _ camera: Camera = .standard3D
    ) throws -> (point: ScenePoint, clip: ClipPoint) {
        let origin = try XCTUnwrap(Self.origins[id])
        let area = SceneRect(x: p.x - origin.x, y: p.y - origin.y, width: 0, height: 0)
        let list = layout.project(
            camera: camera, viewport: Self.portrait, selected: nil, hovered: nil,
            marks: [.area(area, in: id)])
        let mark = try XCTUnwrap(list.marks.first)
        return (mark.points[0], mark.corners[0])
    }

    private func assertSegment(
        _ segment: DrawSegment, from: ScenePoint, to: ScenePoint, onLevelOf id: UInt64,
        _ layout: SceneLayout, camera: Camera = .standard3D, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let a = try placed(from, onLevelOf: id, layout, camera)
        let b = try placed(to, onLevelOf: id, layout, camera)
        assertClose(segment.from, a.point, "\(message) from", file: file, line: line)
        assertClose(segment.to, b.point, "\(message) to", file: file, line: line)
        assertClose(segment.clipFrom, a.clip, "\(message) clip from", file: file, line: line)
        assertClose(segment.clipTo, b.clip, "\(message) clip to", file: file, line: line)
    }

    /// The four edges of a box in window coordinates: top, right, bottom, left.
    private func edges(_ box: SceneRect) -> [(ScenePoint, ScenePoint)] {
        let topLeft = point(box.minX, box.minY), topRight = point(box.maxX, box.minY)
        let bottomLeft = point(box.minX, box.maxY), bottomRight = point(box.maxX, box.maxY)
        return [
            (topLeft, topRight), (topRight, bottomRight), (bottomRight, bottomLeft),
            (bottomLeft, topLeft),
        ]
    }

    // MARK: - Values

    func test_C_SCENE_12_theValuesAreThoseOf2D() throws {
        let layout = try fixtureLayout()
        for (other, values) in [(UInt64(8), [26.5, 68]), (2, [96.5, 96.5, 108, 720])] {
            let drawn = try measured(layout, to: other)
            XCTAssertEqual(
                drawn.measurement, layout.measurement(from: 3, to: other), "to \(other)")
            XCTAssertEqual(drawn.labels.map(\.value), values, "to \(other)")
        }
    }

    // MARK: - Where it is drawn

    func test_C_SCENE_12_eachBoxIsOnItsOwnLevel() throws {
        let layout = try fixtureLayout()
        XCTAssertNotEqual(layout.level(of: 3), layout.level(of: 2), "the fixture's levels")
        let drawn = try measured(layout, to: 2)
        let boxes = drawn.measurement.boxes
        for (index, (from, to)) in edges(boxes[0]).enumerated() {
            try assertSegment(
                drawn.lines[index], from: from, to: to, onLevelOf: 3, layout,
                "selected edge \(index)")
        }
        for (index, (from, to)) in edges(boxes[1]).enumerated() {
            try assertSegment(
                drawn.lines[4 + index], from: from, to: to, onLevelOf: 2, layout,
                "other edge \(index)")
        }
    }

    func test_C_SCENE_12_theDistancesLieOnTheSelectedLayersLevel() throws {
        let layout = try fixtureLayout()
        let drawn = try measured(layout, to: 2)
        let distances = drawn.measurement.distances
        XCTAssertEqual(drawn.distanceLines.count, distances.count)
        var extensions = 0
        for (index, distance) in distances.enumerated() {
            try assertSegment(
                drawn.distanceLines[index], from: distance.start, to: distance.end,
                onLevelOf: 3, layout, "distance \(index)")
            // Each distance's line, then a tick across each end, after the two boxes.
            XCTAssertEqual(drawn.lines[8 + 3 * index], drawn.distanceLines[index])
            for segment in distance.extensions {
                try assertSegment(
                    drawn.dashes[extensions], from: segment.from, to: segment.to, onLevelOf: 3,
                    layout, "extension \(extensions)")
                extensions += 1
            }
            let middle = point(
                (distance.start.x + distance.end.x) / 2, (distance.start.y + distance.end.y) / 2)
            assertClose(
                drawn.labels[index].middle, try placed(middle, onLevelOf: 3, layout).point,
                "label \(index)")
        }
    }

    func test_C_SCENE_12_onAnotherLevelTheOtherBoxIsCopiedAndJoined() throws {
        let layout = try fixtureLayout()
        let drawn = try measured(layout, to: 2)
        let other = drawn.measurement.boxes[1]
        let extensions = drawn.measurement.distances.flatMap(\.extensions).count
        // The copy's four edges come after the extensions.
        XCTAssertEqual(drawn.dashes.count, extensions + 4)
        for (index, (from, to)) in edges(other).enumerated() {
            try assertSegment(
                drawn.dashes[extensions + index], from: from, to: to, onLevelOf: 3, layout,
                "copy edge \(index)")
        }
        // A link from each corner of the other box to the same corner of the copy.
        XCTAssertEqual(drawn.links.count, 4)
        for (index, (corner, _)) in edges(other).enumerated() {
            let link = drawn.links[index]
            let start = try placed(corner, onLevelOf: 2, layout)
            let end = try placed(corner, onLevelOf: 3, layout)
            assertClose(link.from, start.point, "link \(index) from")
            assertClose(link.to, end.point, "link \(index) to")
            assertClose(link.clipFrom, start.clip, "link \(index) clip from")
            assertClose(link.clipTo, end.clip, "link \(index) clip to")
        }
    }

    func test_C_SCENE_12_onTheSameLevelOrWithoutSpacingNothingIsCopied() throws {
        let layout = try fixtureLayout()
        XCTAssertEqual(layout.level(of: 3), layout.level(of: 8), "the fixture's levels")
        let sameLevel = try measured(layout, to: 8)
        XCTAssertEqual(sameLevel.links, [])
        XCTAssertEqual(
            sameLevel.dashes.count, sameLevel.measurement.distances.flatMap(\.extensions).count)
        try assertSegment(
            sameLevel.lines[4], from: point(10, 10), to: point(70, 10), onLevelOf: 8, layout,
            "the other box on its level")

        var flatLevels = Camera.standard3D
        flatLevels.layerSpacing = 0
        let noSpacing = try measured(layout, flatLevels, to: 2)
        XCTAssertEqual(noSpacing.links, [])
        XCTAssertEqual(
            noSpacing.dashes.count, noSpacing.measurement.distances.flatMap(\.extensions).count)
    }

    func test_C_SCENE_12_theTicksStandAcrossTheLineOnTheScreen() throws {
        let drawn = try measured(try fixtureLayout(), to: 2)
        for (index, line) in drawn.distanceLines.enumerated() {
            let dx = line.to.x - line.from.x, dy = line.to.y - line.from.y
            let length = (dx * dx + dy * dy).squareRoot()
            XCTAssertGreaterThan(length, 0)
            let ticks = [
                (drawn.lines[9 + 3 * index], line.from), (drawn.lines[10 + 3 * index], line.to),
            ]
            for (tick, end) in ticks {
                let tx = tick.to.x - tick.from.x, ty = tick.to.y - tick.from.y
                XCTAssertEqual(
                    (tx * tx + ty * ty).squareRoot(), 6, accuracy: 1e-9, "tick \(index)")
                XCTAssertEqual(
                    (tx * dx + ty * dy) / length, 0, accuracy: 1e-9, "tick \(index) across")
                assertClose(
                    point((tick.from.x + tick.to.x) / 2, (tick.from.y + tick.to.y) / 2), end,
                    "tick \(index) at the end")
            }
        }
    }

    func test_C_SCENE_12_turningZoomingPanningAndSpacingMoveTheLinesButNotTheValues() throws {
        let layout = try fixtureLayout()
        let plain = try measured(layout, to: 2)
        var turned = Camera.standard3D.rotated(byDragOf: -80, 40)
        turned.zoom = 1.5
        turned.pan = point(30, -40)
        var spaced = Camera.standard3D
        spaced.layerSpacing = 120
        var orthographic = Camera.standard3D
        orthographic.projection = .orthographic
        for camera in [turned, spaced, orthographic] {
            let drawn = try measured(layout, camera, to: 2)
            XCTAssertEqual(drawn.measurement, plain.measurement, "\(camera)")
            XCTAssertEqual(drawn.labels.map(\.value), plain.labels.map(\.value), "\(camera)")
            XCTAssertNotEqual(drawn.lines, plain.lines, "\(camera)")
            try assertSegment(
                drawn.distanceLines[0], from: drawn.measurement.distances[0].start,
                to: drawn.measurement.distances[0].end, onLevelOf: 3, layout, camera: camera,
                "\(camera)")
            try assertSegment(
                drawn.lines[4], from: point(0, 0), to: point(393, 0), onLevelOf: 2, layout,
                camera: camera, "\(camera)")
        }
    }

    /// A layer inside a collapsed node is shown by the node's image: it is measured on the
    /// node's level, as its marks are (C-LAYOUT-04).
    func test_C_SCENE_12_aLayerInsideACollapsedNodeIsMeasuredOnTheNodesLevel() throws {
        let layout = SceneLayout(
            layers: try SceneFixtures.hierarchyLayers(),
            expanded: SceneFixtures.allIDs.subtracting([6]))
        XCTAssertFalse(layout.isDisplayed(7))
        XCTAssertNotEqual(layout.level(of: 6), layout.level(of: 2), "the fixture's levels")
        let drawn = try measured(layout, from: 7, to: 2)
        XCTAssertEqual(drawn.labels.map(\.value), [146.5, 146.5, 530, 282])
        try assertSegment(
            drawn.lines[0], from: point(146.5, 530), to: point(246.5, 530), onLevelOf: 6, layout,
            "the selected box on the node's level")
        XCTAssertEqual(drawn.links.count, 4)
    }

    func test_C_SCENE_12_onlyTwoDifferentLayersInThePictureAreMeasured() throws {
        func measures(_ layout: SceneLayout, _ selected: UInt64?, _ other: UInt64?) -> Bool {
            layout.project(
                camera: .standard3D, viewport: Self.portrait, selected: selected, hovered: other,
                measuring: other
            ).measurement != nil
        }
        let layout = try fixtureLayout()
        XCTAssertTrue(measures(layout, 3, 2))
        XCTAssertFalse(measures(layout, 3, 3), "the selection itself")
        XCTAssertFalse(measures(layout, nil, 2), "nothing selected")
        XCTAssertFalse(measures(layout, 3, nil), "nothing to measure to")
        XCTAssertFalse(measures(layout, 5, 3), "a hidden selection")
        XCTAssertTrue(measures(try fixtureLayout(showsHidden: true), 5, 3), "shown as a ghost")
        XCTAssertFalse(measures(try fixtureLayout(focus: 4), 3, 4), "outside the focus")
    }

    func test_C_SCENE_12_measuringChangesNeitherTheLayersNorTheMarks() throws {
        let layout = try fixtureLayout()
        let plain = layout.project(
            camera: .standard3D, viewport: Self.portrait, selected: 3, hovered: 2,
            marks: [.layer(4)])
        let measuring = layout.project(
            camera: .standard3D, viewport: Self.portrait, selected: 3, hovered: 2,
            marks: [.layer(4)], measuring: 2)
        XCTAssertNil(plain.measurement)
        XCTAssertNotNil(measuring.measurement)
        XCTAssertEqual(measuring.items, plain.items)
        XCTAssertEqual(measuring.marks, plain.marks)
    }

    // MARK: - Transitions

    /// The levels go through fractions while the expansion changes: nothing is measured on the
    /// way in 3D. In 2D the levels do not show, and the distances stay (C-SCENE-10).
    func test_C_SCENE_12_inAnExpansionsTransitionNothingIsMeasuredIn3D() throws {
        let start = try fixtureLayout()
        let end = SceneLayout(
            layers: try SceneFixtures.hierarchyLayers(),
            expanded: SceneFixtures.allIDs.subtracting([6]))
        let transition = try XCTUnwrap(SceneTransition(from: start.presentation, to: end))
        func project(_ camera: Camera, _ progress: Double) -> DrawList {
            transition.project(
                progress: progress, lens: Lens(camera), viewport: Self.portrait, selected: 3,
                hovered: 2, measuring: 2)
        }
        XCTAssertNil(project(.standard3D, 0.5).measurement)
        XCTAssertNotNil(project(.standard3D, 1).measurement, "at the end")
        XCTAssertEqual(
            project(.flat, 0.5).measurement?.labels.map(\.value), [96.5, 96.5, 108, 720])
    }
}
