import CutawayScene
import CutawayTestSupport
import XCTest

/// C-SCALE-01 in the scene: 10,000 app-shaped layers (`ScaleScene`), every node expanded, as a
/// new tree is.
final class ScaleLayoutTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
    }

    private func layers() throws -> [SceneLayer] {
        try SceneInput.scaleScene()
    }

    private func check(
        _ item: String, _ measured: Duration, limit: Duration,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let report = ScaleScene.report(item, measured, limit: limit)
        if ScaleScene.checksLimits {
            XCTAssertLessThanOrEqual(measured, limit, report, file: file, line: line)
        }
    }

    func test_C_SCALE_01_tenThousandLayersAreLaidOutWithinASecond() throws {
        let layers = try layers()
        let expanded = Set(layers.map(\.id))
        var layout: SceneLayout?
        let measured = ScaleScene.median(of: 3) {
            let start = ContinuousClock.now
            layout = SceneLayout(layers: layers, expanded: expanded)
            return ContinuousClock.now - start
        }
        XCTAssertEqual(layout?.neededTextures.count, layers.count, "every layer is drawn")
        check("layout", measured, limit: .seconds(1))
    }

    func test_C_SCALE_01_aNewCameraOnTenThousandLayersTakesAtMostSixteenMilliseconds() throws {
        let layers = try layers()
        let layout = SceneLayout(layers: layers, expanded: Set(layers.map(\.id)))
        let viewport = Viewport(width: 900, height: 900)
        var camera = Camera.standard3D
        let measured = ScaleScene.median(of: 21) {
            camera = camera.rotated(byDragOf: 3, 1)
            let start = ContinuousClock.now
            let list = layout.project(camera: camera, viewport: viewport, selected: 5, hovered: nil)
            let elapsed = ContinuousClock.now - start
            XCTAssertEqual(list.items.count, layers.count)
            return elapsed
        }
        check("new camera", measured, limit: .milliseconds(16))
    }
}
