import XCTest

@testable import CutawayScene

/// A transition goes through the layers' parents as the layout took them (C-SCENE-10), also
/// when a layer ID comes twice.
final class ParentIndexTests: XCTestCase {
    func test_C_SCENE_10_aTransitionWithARepeatedLayerIDFollowsTheLayoutsParents() {
        // Layer 2's parent is the first layer 1: the second one comes after it.
        let layers = [
            SceneFixtures.layer(1, x: 0, y: 0, width: 100, height: 100),
            SceneFixtures.layer(2, parent: 1, x: 10, y: 10, width: 20, height: 20),
            SceneFixtures.layer(1, x: 0, y: 0, width: 50, height: 50),
        ]
        let layout = SceneLayout(layers: layers, expanded: [1, 2])
        XCTAssertEqual(layout.parentIndex(of: 1), 0)
        XCTAssertNil(layout.parentIndex(of: 0))
        XCTAssertNil(layout.parentIndex(of: 2))
    }
}
