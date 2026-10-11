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

    // MARK: - In place of the rows

    @MainActor
    func test_C_HIER_01_textStandsInWhileLoadingAndWhenThereAreNoWindows() throws {
        let model = model()
        let status = Recorder(viewModel(for: model).status)
        let symbol = Recorder(viewModel(for: model).statusSymbolName)
        let loading = Recorder(viewModel(for: model).isLoading)
        XCTAssertEqual(status.last, "Loading layers…")
        XCTAssertEqual(symbol.last, .some(nil))
        XCTAssertEqual(loading.last, true)

        model.apply(Hierarchy(nodes: [], keyWindowID: 0))
        XCTAssertEqual(status.last, "This app has no windows.")
        XCTAssertEqual(symbol.last, "rectangle.dashed")
        XCTAssertEqual(loading.last, false)

        model.apply(try Fixtures.hierarchy())
        XCTAssertEqual(status.last, .some(nil))
        XCTAssertEqual(symbol.last, .some(nil))
    }

    @MainActor
    func test_C_HIER_01_theLoadStatusIsNilOnceTheTreeIsIn() throws {
        let model = model()
        let loadStatus = Recorder(viewModel(for: model).loadStatus)
        XCTAssertEqual(loadStatus.values, ["Loading layers…"])
        model.apply(try Fixtures.hierarchy())
        XCTAssertEqual(loadStatus.values, ["Loading layers…", nil])
        // The same text again is not sent again.
        model.apply(try Fixtures.hierarchy())
        XCTAssertEqual(loadStatus.values, ["Loading layers…", nil])
    }

    @MainActor
    func test_C_HIER_01_failuresAreExplained() {
        let tree = LayerTree.empty
        XCTAssertEqual(
            HierarchyViewModel.statusText(
                .failed(.invalidHierarchy("the ID 3 appears more than once")), tree,
                appName: "Demo"),
            "The app sent a layer tree that breaks the protocol: the ID 3 appears more than once.")
        XCTAssertEqual(
            HierarchyViewModel.statusText(.failed(.other), tree, appName: "Demo"),
            "The layers could not be loaded. Go back to the apps and open it again.")

        let model = model()
        let symbol = Recorder(viewModel(for: model).statusSymbolName)
        model.loadState = .failed(.other)
        XCTAssertEqual(symbol.last, "exclamationmark.triangle")
    }

    @MainActor
    func test_C_DET_04_anAppThatIsNotActiveIsExplainedByName() {
        XCTAssertEqual(
            HierarchyViewModel.statusText(.failed(.appNotActive), .empty, appName: "Demo"),
            "Demo is not active. Its layers will load when it comes to the foreground.")

        let model = model()
        let status = Recorder(viewModel(for: model).status)
        let symbol = Recorder(viewModel(for: model).statusSymbolName)
        model.loadState = .failed(.appNotActive)
        XCTAssertEqual(
            status.last, "Demo is not active. Its layers will load when it comes to the foreground.")
        XCTAssertEqual(symbol.last, "moon.zzz")
    }

    @MainActor
    func test_C_HIER_04_noMatchesAreExplained() throws {
        let model = try loaded()
        let status = Recorder(viewModel(for: model).status)
        let symbol = Recorder(viewModel(for: model).statusSymbolName)
        model.setSearchText("  button ")
        XCTAssertEqual(status.last, "No layers match “button”.")
        XCTAssertEqual(symbol.last, Theme.Symbol.noMatches)

        model.setSearchText("label")
        XCTAssertEqual(status.last, .some(nil))
        XCTAssertEqual(symbol.last, .some(nil))
        XCTAssertNil(HierarchyViewModel.noMatchText(nil))
    }

    // MARK: - Around the rows

    @MainActor
    func test_C_HIER_01_theFooterCountsTheLayers() throws {
        let model = try loaded()
        XCTAssertEqual(Recorder(viewModel(for: model).count).last, "9 layers · 1 hidden")
        XCTAssertEqual(HierarchyViewModel.countText(model), "9 layers · 1 hidden")
    }

    @MainActor
    func test_C_HIER_04_theFooterCountsTheMatches() throws {
        let model = try loaded()
        let count = Recorder(viewModel(for: model).count)
        model.setSearchText("label")
        XCTAssertEqual(count.last, "2 matches")
        model.setSearchText("scroll")
        XCTAssertEqual(count.last, "1 match")
        model.setSearchText("")
        XCTAssertEqual(count.last, "9 layers · 1 hidden")
    }

    @MainActor
    func test_C_HIER_05_theFooterCountsTheFocus() throws {
        let model = try loaded()
        let count = Recorder(viewModel(for: model).count)
        model.focus(on: 4)
        XCTAssertEqual(count.last, "2 layers · 1 hidden")
        model.focus(on: 9)
        XCTAssertEqual(count.last, "1 layer")
    }

    @MainActor
    func test_C_HIER_05_thePathShowsTheWayDownToTheFocus() throws {
        let model = try loaded()
        XCTAssertEqual(HierarchyViewModel.pathSteps(model), [])
        model.focus(on: 5)
        XCTAssertEqual(HierarchyViewModel.pathSteps(model), [
            .init(title: "UIWindow", symbolName: "macwindow"),
            .init(title: "UIView", symbolName: "square"),
            .init(title: "CardView", symbolName: "square"),
            .init(title: "CAShapeLayer", symbolName: "square.dashed"),
        ])
    }

    @MainActor
    func test_C_HIER_06_theMenuIsNotAvailableDuringASearch() throws {
        let model = try loaded()
        let enabled = Recorder(viewModel(for: model).expandEnabled)
        XCTAssertEqual(enabled.last, true)
        model.setSearchText("label")
        XCTAssertEqual(enabled.last, false)
        model.setSearchText("")
        XCTAssertEqual(enabled.last, true)
    }

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
