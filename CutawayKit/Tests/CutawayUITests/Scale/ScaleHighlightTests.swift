import CutawayModel
import CutawayScene
import CutawayTestSupport
import XCTest

@testable import CutawayUI

/// C-SCALE-01 for the preview's highlights: on 10,000 app-shaped layers (`ScaleScene`), a new
/// hover or selection highlights the list on screen again instead of projecting every layer.
/// Counted rather than timed; the time is printed.
final class ScaleHighlightTests: XCTestCase {
    @MainActor
    func test_C_SCALE_01_aNewHoverOrSelectionOnTenThousandLayersProjectsNothing() throws {
        let tree = try LayerTree(ScaleScene.hierarchy())
        let layout = SceneLayout(layers: tree.sceneLayers(), expanded: Set(tree.ids))
        let viewport = Viewport(width: 900, height: 900)
        var shown = DrawList.empty
        let projector = PreviewProjector(
            clock: nil, reducesMotion: { true }, keepTextures: { _ in },
            show: { list, _ in shown = list })
        projector.resize(to: CGSize(width: viewport.width, height: viewport.height))
        projector.follow(layout)
        projector.follow(.threeD)
        projector.follow(PreviewCameras())
        projector.followsChanges = true
        projector.selected = 5
        projector.project()
        XCTAssertEqual(shown.items.count, tree.count)
        let projections = projector.projectionCount

        let ids = Array(tree.ids.prefix(500))
        var next = 0
        let measured = ScaleScene.median(of: 21) {
            next += 7
            let start = ContinuousClock.now
            projector.hovered = ids[next % ids.count]
            projector.project()
            return ContinuousClock.now - start
        }
        projector.selected = ids[3]
        projector.project()
        XCTAssertEqual(projector.projectionCount, projections, "no layer projected again")
        XCTAssertEqual(
            shown,
            layout.project(
                camera: .standard3D, viewport: viewport, selected: ids[3],
                hovered: projector.hovered),
            "the list a projection gives")
        print("C-SCALE-01 new hover (no limit of its own): \(ScaleScene.milliseconds(measured))")
    }
}
