import Combine
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// What the stores publish is in place when it is published: whoever follows a property and
/// reads the store meanwhile finds the value just sent, not the one before it.
final class StorePublishingTests: XCTestCase {
    @MainActor
    private func model() throws -> InspectionStore {
        let session = Session(
            channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0"))
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        return model
    }

    /// For each value `publisher` sends after the first, whether `read` gave the same value
    /// then.
    @MainActor
    private func inPlace<Value: Equatable>(
        _ publisher: some Publisher<Value, Never>, read: @escaping @MainActor () -> Value,
        while change: () -> Void
    ) -> [Bool] {
        var seen: [Bool] = []
        let subscription = publisher.dropFirst().sink { value in
            MainActor.assumeIsolated { seen.append(value == read()) }
        }
        change()
        withExtendedLifetime(subscription) {}
        return seen
    }

    @MainActor
    func test_C_HIER_01_theSelectionIsInPlaceWhenItPublishes() throws {
        let model = try model()
        let ids = model.tree.ids
        let seen = inPlace(model.$selectedLayerID, read: { model.selectedLayerID }, while: {
            model.select(ids[1])
            model.select(nil)
        })
        XCTAssertEqual(seen, [true, true])
    }

    @MainActor
    func test_C_HIER_15_theHoverIsInPlaceWhenItPublishes() throws {
        let model = try model()
        let ids = model.tree.ids
        let seen = inPlace(model.$hoveredLayerID, read: { model.hoveredLayerID }, while: {
            model.hover(ids[1])
            model.hover(nil)
        })
        XCTAssertEqual(seen, [true, true])
    }

    @MainActor
    func test_C_WIN_03_theLostConnectionIsInPlaceWhenItPublishes() throws {
        let model = try model()
        let seen = inPlace(model.$connection, read: { model.connection }, while: {
            model.connectionLost(waiting: true)
        })
        XCTAssertEqual(seen, [true])
    }
}
