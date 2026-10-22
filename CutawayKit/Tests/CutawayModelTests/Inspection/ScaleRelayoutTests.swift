import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-SCALE-01: after a change that moves no layer, such as an opacity, the server sends the
/// window's subtree again and the scene is laid out again. Laying out 10,000 layers whose
/// places did not change keeps their levels, the costly part, instead of finding them again.
final class ScaleRelayoutTests: XCTestCase {
    @MainActor
    func test_C_SCALE_01_layingOutAgainAfterAChangeThatMovesNothingTakesLessThanHalfOfLayingOutAnew() throws {
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
        let hierarchy = try ScaleScene.hierarchy()
        let model = InspectionStore(
            session: Session(
                channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0")),
            newLayers: .expanded)
        model.apply(hierarchy)
        let index = hierarchy.nodes.count / 2
        var opacity: Float = 0.5
        // Another value each time, so that each tree differs from the last.
        func changedTree() throws -> LayerTree {
            let value = opacity
            opacity = opacity == 0.5 ? 0.25 : 0.5
            var nodes = hierarchy.nodes
            nodes[index].opacity = value
            return try LayerTree(Hierarchy(nodes: nodes, keyWindowID: hierarchy.keyWindowID))
        }
        let again = try ScaleScene.median(of: 7) {
            let tree = try changedTree()
            let start = ContinuousClock.now
            model.layOut(tree)
            return ContinuousClock.now - start
        }
        let anew = try ScaleScene.median(of: 7) {
            let tree = try changedTree()
            model.geometry = SceneLayout(layers: [], expanded: [])
            let start = ContinuousClock.now
            model.layOut(tree)
            return ContinuousClock.now - start
        }
        let report = ScaleScene.report(
            "laying out again after a change that moves nothing (anew: "
                + ScaleScene.milliseconds(anew) + ")",
            again, limit: anew / 2)
        if ScaleScene.checksLimits { XCTAssertLessThan(again, anew / 2, report) }
    }
}
