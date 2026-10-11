import CutawayScene
import CutawayTestSupport
import XCTest

/// Alarms for a slowdown, not performance targets. The bounds are loose because
/// `swift test` builds without optimisation.
final class ScenePerformanceTests: XCTestCase {
    /// A window with `containers` nested full-screen views, the innermost holding small
    /// leaves that do not overlap one another: the shape of a real screen.
    private func screen(containers: Int, leaves: Int) -> [SceneLayer] {
        var layers = [SceneFixtures.layer(1, x: 0, y: 0, width: 393, height: 852)]
        for index in 0..<containers {
            layers.append(
                SceneFixtures.layer(
                    UInt64(2 + index), parent: UInt64(1 + index), x: 0, y: 0, width: 393,
                    height: 852))
        }
        let innermost = UInt64(1 + containers)
        let columns = 40
        for index in 0..<leaves {
            let column = index % columns, row = index / columns
            layers.append(
                SceneFixtures.layer(
                    UInt64(2 + containers + index), parent: innermost,
                    x: Double(column) * 9.8, y: Double(row) * 9.8, width: 8, height: 8))
        }
        return layers
    }

    func test_C_SCENE_02_twoThousandLayersAreLaidOutWithinASecond() throws {
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
        let layers = screen(containers: 20, leaves: 1979)
        XCTAssertEqual(layers.count, 2000)
        let expanded = Set(layers.map(\.id))

        let start = ContinuousClock.now
        let layout = SceneLayout(layers: layers, expanded: expanded)
        let elapsed = ContinuousClock.now - start

        XCTAssertEqual(layout.level(of: 21), 20, "the innermost container")
        XCTAssertEqual(layout.level(of: 22), 21, "a leaf")
        XCTAssertLessThan(elapsed, .seconds(1))
        print("ScenePerformanceTests: laid out 2000 layers in \(elapsed)")
    }

    func test_C_SCENE_04_fiveThousandLayersAreProjectedWithinFiftyMilliseconds() throws {
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
        let layers = screen(containers: 20, leaves: 4979)
        let layout = SceneLayout(layers: layers, expanded: Set(layers.map(\.id)))
        let viewport = Viewport(width: 900, height: 900)

        let start = ContinuousClock.now
        let list = layout.project(camera: .standard3D, viewport: viewport, selected: 3, hovered: 4)
        let elapsed = ContinuousClock.now - start

        XCTAssertEqual(list.items.count, 5000)
        XCTAssertLessThan(elapsed, .milliseconds(50))
        print("ScenePerformanceTests: projected 5000 layers in \(elapsed)")
    }

    func test_C_SCENE_07_aNewCameraOnTwoThousandLayersTakesAtMostSixteenMilliseconds() throws {
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
        let layers = screen(containers: 20, leaves: 1979)
        let layout = SceneLayout(layers: layers, expanded: Set(layers.map(\.id)))
        let viewport = Viewport(width: 900, height: 900)
        var times: [Duration] = []
        var camera = Camera.standard3D
        for _ in 0..<21 {
            camera = camera.rotated(byDragOf: 3, 1)
            let start = ContinuousClock.now
            let list = layout.project(
                camera: camera, viewport: viewport, selected: nil, hovered: nil)
            times.append(ContinuousClock.now - start)
            XCTAssertEqual(list.items.count, 2000)
        }
        let median = times.sorted()[times.count / 2]
        XCTAssertLessThanOrEqual(median, .milliseconds(16), "median of 21: \(median)")
    }

    /// A frame of a transition sorts the layers by level instead of going level by level; it
    /// should cost about what a still frame does. 3,000 layers, the innermost container
    /// collapsing, which sends 2,979 leaves down.
    func test_C_SCENE_10_aFrameOfATransitionCostsAboutAsMuchAsAStillOne() throws {
        let layers = screen(containers: 20, leaves: 2979)
        let all = Set(layers.map(\.id))
        let start = SceneLayout(layers: layers, expanded: all)
        let end = SceneLayout(layers: layers, expanded: all.subtracting([21]))
        let transition = try XCTUnwrap(SceneTransition(from: start.presentation, to: end))
        let viewport = Viewport(width: 900, height: 900)
        let lens = Lens(.standard3D)

        func median(_ body: () -> DrawList) -> Duration {
            var times: [Duration] = []
            for _ in 0..<11 {
                let begin = ContinuousClock.now
                XCTAssertEqual(body().items.count, 3000)
                times.append(ContinuousClock.now - begin)
            }
            return times.sorted()[times.count / 2]
        }
        let still = median {
            start.project(lens: lens, viewport: viewport, selected: nil, hovered: nil)
        }
        let moving = median {
            transition.project(
                progress: 0.5, lens: lens, viewport: viewport, selected: nil, hovered: nil)
        }
        XCTAssertLessThan(moving, still * 5, "still \(still), moving \(moving)")
        print("ScenePerformanceTests: a frame of 3000 layers, still \(still), moving \(moving)")
    }
}
