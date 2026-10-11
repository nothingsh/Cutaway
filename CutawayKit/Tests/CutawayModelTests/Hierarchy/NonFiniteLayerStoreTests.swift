import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import Foundation
import XCTest

@testable import CutawayModel

/// C-SCENE-11, outside the scene: a layer that cannot be placed is not drawn, but it is a
/// layer of the tree like any other.
@MainActor
final class NonFiniteLayerStoreTests: XCTestCase {
    func test_C_SCENE_11_aLayerThatCannotBePlacedIsStillListed() async throws {
        var responder = try MockResponder.demo()
        let index = try XCTUnwrap(responder.hierarchy.nodes.firstIndex { $0.id == 4 })
        responder.hierarchy.nodes[index].bounds?.size.width = .nan
        responder.hierarchy.nodes[index].position?.y = .infinity
        let server = try await ArchiveCaptureTests.server(responder)
        let session = try await ArchiveCaptureTests.session(to: server)
        let model = InspectionStore(session: session, maxTextureDimension: 4096)
        model.enter()

        let listed = await Wait.until { await model.tree.count == 9 }
        XCTAssertTrue(listed, "the tree has \(model.tree.count) layers")
        XCTAssertTrue(model.tree.contains(4))
        XCTAssertTrue(model.tree.contains(5))

        model.select(4)
        let loaded = await Wait.until {
            await MainActor.run {
                if case .loaded = model.attributes.state { return true }
                return false
            }
        }
        XCTAssertTrue(loaded, "layer 4's attributes are \(model.attributes.state)")
        model.leave()
    }
}
