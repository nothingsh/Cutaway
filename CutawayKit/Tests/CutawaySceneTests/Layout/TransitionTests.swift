import CutawayScene
import Foundation
import XCTest

/// A frame between two cameras, or between two expansions of the same layers (C-SCENE-10).
final class TransitionTests: XCTestCase {
    private let viewport = Viewport(width: 480, height: 900)

    /// The `hierarchy` fixture with a solo and a group image for every layer.
    private func layers() throws -> [SceneLayer] {
        try SceneFixtures.hierarchyLayers(
            textures: Dictionary(
                uniqueKeysWithValues: SceneFixtures.allIDs.map {
                    ($0, LayerTextures(solo: SceneFixtures.solo($0), group: SceneFixtures.group($0)))
                }))
    }

    private func layout(collapsed: Set<UInt64> = []) throws -> SceneLayout {
        SceneLayout(layers: try layers(), expanded: SceneFixtures.allIDs.subtracting(collapsed))
    }

    private func transition(
        from start: SceneLayout, to end: SceneLayout, file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SceneTransition {
        try XCTUnwrap(SceneTransition(from: start.presentation, to: end), file: file, line: line)
    }

    private func project(
        _ transition: SceneTransition, _ progress: Double, camera: Camera = .standard3D,
        marks: [SceneMark] = []
    ) -> DrawList {
        transition.project(
            progress: progress, lens: Lens(camera), viewport: viewport, selected: 3, hovered: 4,
            marks: marks)
    }

    private func item(_ id: UInt64, in list: DrawList) throws -> DrawItem {
        try XCTUnwrap(list.items.first { $0.layerID == id }, "layer \(id) is drawn")
    }

    // MARK: - The lens

    func test_C_SCENE_10_theEndsOfALensTransitionAreTheTwoCameras() throws {
        let layout = try layout()
        let from = Lens(.flat), to = Lens(.standard3D)
        XCTAssertEqual(from.interpolated(to: to, progress: 0), from)
        XCTAssertEqual(from.interpolated(to: to, progress: 1), to)
        for (lens, camera) in [(from, Camera.flat), (to, .standard3D)] {
            XCTAssertEqual(
                layout.project(lens: lens, viewport: viewport, selected: 3, hovered: nil),
                layout.project(camera: camera, viewport: viewport, selected: 3, hovered: nil))
        }
    }

    /// The corners in viewport points at each step of 0.01, both ways and with a turned and
    /// zoomed camera too.
    func test_C_SCENE_10_noCornerJumpsBetweenTheOrthographicAndThePerspectiveProjections() throws {
        let layout = try layout()
        var turned = Camera.standard3D.rotated(byDragOf: -80, 40)
        turned.zoom = 2.5
        turned.pan = ScenePoint(x: 30, y: -20)
        turned.layerSpacing = 120
        var panned = Camera.flat
        panned.zoom = 0.6
        for (a, b) in [(Camera.flat, Camera.standard3D), (.standard3D, .flat), (panned, turned)] {
            let lists = (0...100).map { step in
                layout.project(
                    lens: Lens(a).interpolated(to: Lens(b), progress: Double(step) / 100),
                    viewport: viewport, selected: nil, hovered: nil)
            }
            func corners(_ list: DrawList) -> [UInt64: Corners<ScenePoint>] {
                Dictionary(uniqueKeysWithValues: list.items.map { ($0.layerID, $0.points) })
            }
            let first = corners(lists[0]), last = corners(lists[100])
            var whole = 0.0
            for (id, points) in first {
                for (p, q) in zip(points, last[id]!) { whole = max(whole, hypot(q.x - p.x, q.y - p.y)) }
            }
            XCTAssertGreaterThan(whole, 10, "the corners move")
            for step in 1...100 {
                let before = corners(lists[step - 1]), after = corners(lists[step])
                for (id, points) in after {
                    for (p, q) in zip(before[id]!, points) {
                        XCTAssertLessThanOrEqual(
                            hypot(q.x - p.x, q.y - p.y), whole * 0.05,
                            "layer \(id) at step \(step) of \(a) to \(b)")
                    }
                }
            }
        }
    }

    func test_C_SCENE_10_theTurnAboutTheVerticalAxisGoesTheShorterWay() {
        var a = Camera.standard3D, b = Camera.standard3D
        a.yaw = 170 * .pi / 180
        b.yaw = -170 * .pi / 180
        for step in 1..<10 {
            let yaw = Lens(a).interpolated(to: Lens(b), progress: Double(step) / 10).yaw
            XCTAssertGreaterThanOrEqual(abs(yaw), 170 * .pi / 180 - 1e-9, "step \(step)")
            XCTAssertLessThanOrEqual(abs(yaw), .pi)
        }
        XCTAssertEqual(
            abs(Lens(a).interpolated(to: Lens(b), progress: 0.5).yaw), .pi, accuracy: 1e-9)
    }

    func test_C_SCENE_10_theZoomGoesByEqualRatios() {
        var a = Camera.flat, b = Camera.flat
        a.zoom = 0.5
        b.zoom = 2
        XCTAssertEqual(Lens(a).interpolated(to: Lens(b), progress: 0.5).zoom, 1, accuracy: 1e-12)
        XCTAssertEqual(Lens(a).interpolated(to: Lens(b), progress: 0.25).zoom, 0.5.squareRoot(), accuracy: 1e-12)
    }

    // MARK: - Which layouts make a transition

    func test_C_SCENE_10_onlyLayoutsThatDifferInTheExpansionMakeATransition() throws {
        let layers = try layers()
        let all = SceneFixtures.allIDs
        let start = SceneLayout(layers: layers, expanded: all)
        XCTAssertNotNil(
            SceneTransition(from: start.presentation, to: SceneLayout(layers: layers, expanded: all.subtracting([2]))))
        XCTAssertNil(
            SceneTransition(from: start.presentation, to: SceneLayout(layers: layers, expanded: all)),
            "the same expansion: nothing moves")
        XCTAssertNil(
            SceneTransition(
                from: start.presentation,
                to: SceneLayout(layers: layers, expanded: all.subtracting([2]), focus: 2)),
            "another focus")
        XCTAssertNil(
            SceneTransition(
                from: start.presentation,
                to: SceneLayout(layers: layers, expanded: all.subtracting([2]), showsHidden: true)),
            "hidden layers shown")
        var moved = layers
        moved[2].position.x += 10
        XCTAssertNil(
            SceneTransition(from: start.presentation, to: SceneLayout(layers: moved, expanded: all.subtracting([2]))),
            "a layer moved: another tree")
        XCTAssertNil(
            SceneTransition(
                from: start.presentation,
                to: SceneLayout(layers: Array(layers.dropLast()), expanded: all.subtracting([2]))),
            "a layer fewer")
    }

    func test_C_SCENE_10_newImagesKeepTheTransitionGoing() throws {
        let transition = try transition(from: try layout(), to: try layout(collapsed: [2]))
        var textures = Dictionary(
            uniqueKeysWithValues: SceneFixtures.allIDs.map {
                ($0, LayerTextures(solo: SceneFixtures.solo($0), group: SceneFixtures.group($0)))
            })
        textures[3] = LayerTextures(
            solo: TextureKey(layerID: 3, kind: .solo, revision: 2),
            group: TextureKey(layerID: 3, kind: .group, revision: 2))
        textures[2]?.group = TextureKey(layerID: 2, kind: .group, revision: 2)
        let end = transition.end.replacingTextures(textures)
        let retargeted = try XCTUnwrap(transition.retargeted(to: end))
        XCTAssertNil(transition.retargeted(to: try layout(collapsed: [6])), "another expansion")
        XCTAssertNil(
            transition.retargeted(to: try layout(collapsed: [2])),
            "the same expansion laid out again: a new tree that happens to be the same")

        XCTAssertEqual(retargeted.level(of: 3, at: 0.5), transition.level(of: 3, at: 0.5))
        let halfway = project(retargeted, 0.5)
        XCTAssertEqual(try item(3, in: halfway).texture?.revision, 2, "the leaving layer's newer image")
        XCTAssertEqual(project(retargeted, 1), end.project(
            camera: .standard3D, viewport: viewport, selected: 3, hovered: 4))
    }

    // MARK: - Collapsing and expanding

    func test_C_SCENE_10_collapsingStartsOnTheSourceAndEndsOnTheTarget() throws {
        let start = try layout(), end = try layout(collapsed: [2])
        let transition = try transition(from: start, to: end)
        for camera in [Camera.standard3D, .flat, Camera.standard3D.rotated(byDragOf: 300, -50)] {
            XCTAssertEqual(
                project(transition, 0, camera: camera),
                start.project(camera: camera, viewport: viewport, selected: 3, hovered: 4))
            XCTAssertEqual(
                project(transition, 1, camera: camera),
                end.project(camera: camera, viewport: viewport, selected: 3, hovered: 4))
        }
    }

    /// `hierarchy`, 3D: collapsing node 2 brings 3, 4, 6, 7 and 8 down onto node 2's level.
    func test_C_SCENE_10_halfwayACollapsedLayerIsMidwayToItsNodesLevel() throws {
        let start = try layout(), end = try layout(collapsed: [2])
        let transition = try transition(from: start, to: end)
        let node = Double(try XCTUnwrap(end.level(of: 2)))
        for id: UInt64 in [3, 4, 6, 7, 8] {
            let from = Double(try XCTUnwrap(start.level(of: id)))
            XCTAssertNotEqual(from, node)
            XCTAssertEqual(
                try XCTUnwrap(transition.level(of: id, at: 0.5)), (from + node) / 2,
                accuracy: 1e-12, "layer \(id)")
            XCTAssertEqual(transition.level(of: id, at: 1), node)
        }
        let halfway = project(transition, 0.5)
        XCTAssertEqual(try item(2, in: halfway).texture, SceneFixtures.solo(2), "until the end")
        XCTAssertEqual(try item(3, in: halfway).texture, SceneFixtures.group(3))
        XCTAssertEqual(try item(7, in: halfway).texture, SceneFixtures.group(7))
        XCTAssertEqual(try item(2, in: project(transition, 1)).texture, SceneFixtures.group(2))
        XCTAssertNil(project(transition, 1).items.first { $0.layerID == 3 })
    }

    func test_C_SCENE_10_expandedLayersStartOnTheNodesLevel() throws {
        let start = try layout(collapsed: [2]), end = try layout()
        let transition = try transition(from: start, to: end)
        let node = Double(try XCTUnwrap(start.level(of: 2)))
        let first = project(transition, 0)
        for id: UInt64 in [3, 4, 6, 7, 8] {
            XCTAssertEqual(transition.level(of: id, at: 0), node, "layer \(id)")
            XCTAssertNotNil(first.items.first { $0.layerID == id }, "layer \(id) is drawn at once")
            let to = Double(try XCTUnwrap(end.level(of: id)))
            XCTAssertEqual(try XCTUnwrap(transition.level(of: id, at: 0.25)), node + (to - node) / 4, accuracy: 1e-12)
        }
        XCTAssertEqual(try item(2, in: first).texture, SceneFixtures.solo(2), "from the start")
        XCTAssertEqual(
            project(transition, 1),
            end.project(camera: .standard3D, viewport: viewport, selected: 3, hovered: 4))
    }

    /// A collapse can lower layers outside the collapsed node: D sits over C, which goes.
    func test_C_SCENE_10_otherLayersWhoseLevelChangesMoveToo() throws {
        let layers = [
            SceneFixtures.layer(1, x: 0, y: 0, width: 400, height: 400),
            SceneFixtures.layer(2, parent: 1, x: 0, y: 0, width: 200, height: 400),
            SceneFixtures.layer(3, parent: 2, x: 150, y: 10, width: 100, height: 50),
            SceneFixtures.layer(4, parent: 1, x: 220, y: 20, width: 50, height: 50),
        ]
        let start = SceneLayout(layers: layers, expanded: [1, 2, 3, 4])
        let end = SceneLayout(layers: layers, expanded: [1, 3, 4])
        XCTAssertEqual(start.level(of: 4), 3)
        XCTAssertEqual(end.level(of: 4), 1)
        let transition = try transition(from: start, to: end)
        XCTAssertEqual(transition.level(of: 4, at: 0.5), 2)
        XCTAssertEqual(transition.level(of: 3, at: 0.5), 1.5, "from 2 onto node 2's level 1")
    }

    func test_C_SCENE_10_anInterruptedTransitionStartsFromTheFrameOnScreen() throws {
        let collapsing = try transition(from: try layout(), to: try layout(collapsed: [2]))
        let expanding = try XCTUnwrap(
            SceneTransition(from: collapsing.presentation(at: 0.5), to: try layout()))
        XCTAssertEqual(project(expanding, 0), project(collapsing, 0.5))
        XCTAssertEqual(expanding.level(of: 3, at: 0), collapsing.level(of: 3, at: 0.5))
        XCTAssertEqual(
            project(expanding, 1),
            try layout().project(camera: .standard3D, viewport: viewport, selected: 3, hovered: 4))

        // A collapse again, from the middle of the expansion, of the same and another node.
        let again = try XCTUnwrap(
            SceneTransition(from: expanding.presentation(at: 0.5), to: try layout(collapsed: [2, 6])))
        XCTAssertEqual(project(again, 0), project(expanding, 0.5))
    }

    // MARK: - Order, hit testing, marks, measuring

    func test_C_SCENE_10_fractionalLevelsAreDrawnBackToFront() throws {
        let start = try layout(), end = try layout(collapsed: [2])
        let transition = try transition(from: start, to: end)
        var behind = Camera.standard3D
        behind.yaw = .pi - 0.3
        var orthographic = Camera.flat
        orthographic.yaw = 0.4
        orthographic.layerSpacing = 40
        for (camera, upwards) in [(Camera.standard3D, true), (orthographic, true), (behind, false)] {
            for progress in [0.3, 0.5, 0.8] {
                let levels = try project(transition, progress, camera: camera).items.map {
                    try XCTUnwrap(transition.level(of: $0.layerID, at: progress))
                }
                XCTAssertEqual(levels, upwards ? levels.sorted() : levels.sorted(by: >), "\(camera) at \(progress)")
            }
        }
    }

    func test_C_SCENE_10_aFrameIsHitTestedAsItIsDrawn() throws {
        let transition = try transition(from: try layout(), to: try layout(collapsed: [2]))
        let halfway = project(transition, 0.5)
        XCTAssertEqual(halfway.layer(at: try item(3, in: halfway).center), 3, "above node 2")
        XCTAssertEqual(project(transition, 1).layer(at: try item(3, in: halfway).center), 2)
    }

    func test_C_SCENE_10_marksFollowTheirLayers() throws {
        let transition = try transition(from: try layout(), to: try layout(collapsed: [2]))
        let halfway = project(transition, 0.5, marks: [.layer(3), .layer(5), .layer(99)])
        XCTAssertEqual(halfway.marks.map(\.mark), [.layer(3)], "5 is hidden, 99 unknown")
        XCTAssertEqual(halfway.marks.first?.points, try item(3, in: halfway).points)
    }

    /// Between two expansions in 2D the distances stay; in 3D see C-SCENE-12. Between two
    /// lenses the preview measures nothing (C-PREV-11).
    func test_C_SCENE_10_distancesAreMeasuredInA2DTransition() throws {
        let layout = try layout()
        let collapsing = try transition(from: layout, to: try self.layout(collapsed: [6]))
        let flat = collapsing.project(
            progress: 0.5, lens: Lens(.flat), viewport: viewport, selected: 3, hovered: 8,
            measuring: 8)
        XCTAssertEqual(flat.measurement?.measurement.distances.map(\.value), [26.5, 68])
    }

    // MARK: - From the independent review

    /// A scroll view whose content reaches far outside it: collapsing it shrinks the box the
    /// view is fitted to, expanding it grows the box. The fit goes over with the rest, so the
    /// picture neither zooms in on the last frame of a collapse nor out on the first frame of
    /// an expansion.
    func test_C_SCENE_10_theFitDoesNotJumpWhenSublayersReachOutsideTheirNode() throws {
        let layers = [
            SceneFixtures.layer(1, x: 0, y: 0, width: 400, height: 400),
            SceneFixtures.layer(2, parent: 1, x: 100, y: 100, width: 200, height: 200),
            SceneFixtures.layer(3, parent: 2, x: 0, y: 0, width: 200, height: 1600),
        ]
        let expanded = SceneLayout(layers: layers, expanded: [1, 2, 3])
        let collapsed = SceneLayout(layers: layers, expanded: [1, 3])
        func corners(_ list: DrawList, _ id: UInt64) throws -> Corners<ScenePoint> {
            try XCTUnwrap(list.items.first { $0.layerID == id }?.points)
        }
        func gap(_ a: Corners<ScenePoint>, _ b: Corners<ScenePoint>) -> Double {
            zip(a, b).map { hypot($0.x - $1.x, $0.y - $1.y) }.max() ?? 0
        }
        let collapsing = try transition(from: expanded, to: collapsed)
        let expanding = try transition(from: collapsed, to: expanded)
        for camera in [Camera.standard3D, .flat] {
            let nearEnd = collapsing.project(
                progress: 1 - 1e-6, lens: Lens(camera), viewport: viewport, selected: nil,
                hovered: nil)
            let end = project(collapsing, 1, camera: camera)
            XCTAssertLessThan(try gap(corners(nearEnd, 1), corners(end, 1)), 0.01, "\(camera)")
            XCTAssertLessThan(try gap(corners(nearEnd, 2), corners(end, 2)), 0.01, "\(camera)")

            let first = project(expanding, 0, camera: camera)
            let before = collapsed.project(
                camera: camera, viewport: viewport, selected: 3, hovered: 4)
            XCTAssertLessThan(try gap(corners(first, 1), corners(before, 1)), 1e-9, "\(camera)")
            XCTAssertLessThan(try gap(corners(first, 2), corners(before, 2)), 1e-9, "\(camera)")
        }
    }

    /// Layer 9 has no area: displayed, on level 0, never drawn. A mark on it stays there.
    func test_C_SCENE_10_aLayerWithoutAreaKeepsItsLevel() throws {
        let end = try layout(collapsed: [6])
        let transition = try transition(from: try layout(), to: end)
        let level = Double(try XCTUnwrap(end.level(of: 9)))
        for progress in [0, 0.5, 0.999, 1] {
            XCTAssertEqual(transition.level(of: 9, at: progress), level, "at \(progress)")
        }
    }

    func test_C_SCENE_10_aChangeThatMovesNothingMakesNoTransition() throws {
        let layers = try layers()
        XCTAssertNil(
            SceneTransition(
                from: try layout(collapsed: [2]).presentation, to: try layout(collapsed: [2, 6])),
            "inside a collapsed node")
        XCTAssertNil(
            SceneTransition(
                from: try layout().presentation,
                to: SceneLayout(layers: layers, expanded: SceneFixtures.allIDs.subtracting([8]))),
            "a layer without sublayers")
    }

    /// The collapsed node had no solo yet; one that arrives on the way is drawn at once.
    func test_C_SCENE_10_anImageForTheCollapsingNodeIsUsedOnTheWay() throws {
        var textures = Dictionary(
            uniqueKeysWithValues: SceneFixtures.allIDs.map {
                ($0, LayerTextures(solo: SceneFixtures.solo($0), group: SceneFixtures.group($0)))
            })
        textures[2] = LayerTextures()
        let start = try layout().replacingTextures(textures)
        let end = try layout(collapsed: [2]).replacingTextures(textures)
        let transition = try transition(from: start, to: end)
        XCTAssertNil(try item(2, in: project(transition, 0.5)).texture)
        textures[2] = LayerTextures(solo: SceneFixtures.solo(2))
        let retargeted = try XCTUnwrap(transition.retargeted(to: end.replacingTextures(textures)))
        XCTAssertEqual(try item(2, in: project(retargeted, 0.5)).texture, SceneFixtures.solo(2))
    }
}
