import Combine
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// What the hierarchy list says around its rows, without the list: C-HIER-01, C-HIER-04 to
/// C-HIER-06, C-DET-04.
final class HierarchyViewModelTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    @MainActor
    private func model() -> InspectionStore {
        InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
    }

    /// A model showing the `hierarchy` fixture.
    @MainActor
    private func loaded() throws -> InspectionStore {
        let model = model()
        model.apply(try Fixtures.hierarchy())
        return model
    }

    @MainActor
    private func viewModel(for model: InspectionStore) -> HierarchyViewModel {
        HierarchyViewModel(store: model, appName: "Demo")
    }

    /// Everything a publisher sends while the subscription lasts.
    private final class Recorder<Value> {
        private(set) var values: [Value] = []
        private var subscription: AnyCancellable?

        init(_ publisher: AnyPublisher<Value, Never>) {
            subscription = publisher.sink { [weak self] in self?.values.append($0) }
        }

        var last: Value? { values.last }
    }

    // MARK: - Around the rows

    @MainActor
    func test_C_HIER_05_theMenuIsNotAvailableOnceDisconnected() throws {
        let model = try loaded()
        let viewModel = viewModel(for: model)
        let enabled = Recorder(viewModel.expandEnabled)
        XCTAssertEqual(enabled.last, true)
        model.connectionLost()
        XCTAssertEqual(enabled.last, false)
    }
}
