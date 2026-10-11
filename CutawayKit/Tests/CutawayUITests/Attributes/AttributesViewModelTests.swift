import Combine
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// What the attribute panel shows, without the panel: C-ATTR-01, C-ATTR-04, C-ATTR-06,
/// C-ATTR-09, C-LAYOUT-02.
final class AttributesViewModelTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.4.0")

    @MainActor
    private func attributesStore() -> AttributesStore {
        AttributesStore(session: Session(channel: InertChannel(), client: Self.client))
    }

    @MainActor
    private func viewModel(
        for model: AttributesStore,
        layer: AnyPublisher<LayerSummary?, Never> = Just(nil).eraseToAnyPublisher(),
        tree: AnyPublisher<LayerTree, Never> = Just(.empty).eraseToAnyPublisher(),
        connection: CurrentValueSubject<InspectionStore.Connection, Never> = .init(.live)
    ) -> AttributesViewModel {
        AttributesViewModel(
            store: model, appName: "Demo", layer: layer, tree: tree,
            connection: connection.eraseToAnyPublisher())
    }

    /// Everything a publisher sends while the subscription lasts.
    private final class Recorder<Value> {
        private(set) var values: [Value] = []
        private var subscription: AnyCancellable?

        init(_ publisher: AnyPublisher<Value, Never>) {
            subscription = publisher.sink { [weak self] in self?.values.append($0) }
        }
    }

    private static let editable = Attribute(
        id: "view.alpha", title: "Alpha", value: .double(1), editable: true, valueKind: .double)
    private static let readOnly = Attribute(
        id: "layer.frame", title: "Frame", value: nil, editable: false, valueKind: .rect)

    // MARK: - Messages

    func test_C_ATTR_01_eachStateHasItsMessage() {
        func message(_ state: AttributesStore.State) -> AttributesViewModel.Message? {
            AttributesViewModel.message(for: state, appName: "Demo")
        }
        XCTAssertEqual(message(.none), AttributesViewModel.Message(
            symbol: "cursorarrow.click.2", title: "No Selection",
            detail: "Select a layer in the list or the preview."))
        XCTAssertEqual(message(.loading), AttributesViewModel.Message(
            symbol: nil, title: "Loading Attributes", showsSpinner: true))
        XCTAssertEqual(message(.loaded([])), AttributesViewModel.Message(
            symbol: "list.bullet.rectangle", title: "No Attributes"))
        XCTAssertNil(message(.loaded([AttributeGroup(id: "g", title: "G", attributes: [])])))
        XCTAssertEqual(message(.layerGone), AttributesViewModel.Message(
            symbol: "questionmark.square.dashed", title: "Layer Not Found",
            detail: "This layer is no longer in the app."))
        XCTAssertEqual(message(.appNotActive), AttributesViewModel.Message(
            symbol: "moon.zzz", title: "Demo Is Not Active",
            detail: "Attributes load when it comes to the foreground."))
        XCTAssertEqual(message(.failed), AttributesViewModel.Message(
            symbol: "exclamationmark.triangle", title: "Couldn’t Load Attributes",
            detail: "The request failed or took too long.", offersRetry: true))
    }

    func test_C_LAYOUT_02_aLayerWithConstraintsButNoAttributesHasNoMessage() {
        XCTAssertNil(AttributesViewModel.message(
            for: .loaded([]), appName: "Demo", hasConstraints: true))
    }

    // MARK: - Changing attributes

    func test_C_ATTR_06_theRowsSayWhyAChangeFailed() {
        XCTAssertNil(AttributesViewModel.failureText(.rejected, appName: "Demo"))
        XCTAssertEqual(
            AttributesViewModel.failureText(.notEditable, appName: "Demo"),
            "This attribute cannot be changed.")
        XCTAssertEqual(
            AttributesViewModel.failureText(.appNotActive, appName: "Demo"),
            "Demo is not active.")
        XCTAssertEqual(
            AttributesViewModel.failureText(.noAnswer, appName: "Demo"),
            "Demo did not answer in time.")
        XCTAssertNil(AttributesViewModel.failureText(.notFinite, appName: "Demo"))
    }

    @MainActor
    func test_C_ATTR_04_editableAttributesGetEditorsWhileEditingIsPossible() {
        let model = attributesStore()
        let viewModel = self.viewModel(for: model)
        model.select(3)
        XCTAssertFalse(viewModel.hasEditor(Self.editable), "the model cannot edit yet")

        viewModel.canEdit = true
        XCTAssertTrue(viewModel.hasEditor(Self.editable))
        XCTAssertFalse(viewModel.hasEditor(Self.readOnly))
        var noID = Self.editable
        noID.id = nil
        XCTAssertFalse(viewModel.hasEditor(noID))

        // A lost connection takes every editor away (C-WIN-03).
        viewModel.isConnected = false
        XCTAssertFalse(viewModel.offersEditors)
        XCTAssertFalse(viewModel.hasEditor(Self.editable))
    }

    @MainActor
    func test_C_ATTR_04_noLayerNoEditorsAndNoKeys() {
        let viewModel = self.viewModel(for: attributesStore())
        viewModel.canEdit = true
        XCTAssertFalse(viewModel.hasEditor(Self.editable))
        XCTAssertNil(viewModel.key(of: Self.editable))
    }

    @MainActor
    func test_C_ATTR_06_theShapeChangesWithTheLayerTheKindsAndTheEditors() {
        let model = attributesStore()
        let viewModel = self.viewModel(for: model)
        model.select(3)
        let groups = [AttributeGroup(id: "view", title: "View", attributes: [Self.editable])]
        let shape = viewModel.shape(of: groups)
        XCTAssertEqual(shape, AttributesViewModel.Shape(
            layerID: 3,
            groups: [[AttributesViewModel.Shape.Row(
                id: "view.alpha", title: "Alpha", kind: .double, hasEditor: false)]],
            groupTitles: ["View"], groupIDs: ["view"]))

        // New values keep the shape: the rows are updated in place.
        var newValue = groups
        newValue[0].attributes[0].value = .double(0.5)
        XCTAssertEqual(viewModel.shape(of: newValue), shape)

        viewModel.canEdit = true
        XCTAssertNotEqual(viewModel.shape(of: groups), shape, "editors now")
        model.select(4)
        XCTAssertEqual(viewModel.shape(of: groups).layerID, 4)
        XCTAssertEqual(
            viewModel.key(of: Self.editable),
            AttributeKey(layerID: 4, attributeID: "view.alpha"))
    }

    @MainActor
    func test_C_ATTR_06_aRowShowsTheValueOnItsWayOrWhyItFailed() {
        let model = attributesStore()
        let viewModel = self.viewModel(for: model)
        model.select(3)
        let key = AttributeKey(layerID: 3, attributeID: "view.alpha")
        XCTAssertEqual(
            viewModel.rowState(of: Self.editable),
            AttributesViewModel.RowState(value: .double(1), isSending: false, failureText: nil))

        viewModel.edits = [key: .sending(.double(0.5))]
        XCTAssertEqual(
            viewModel.rowState(of: Self.editable),
            AttributesViewModel.RowState(
                value: .double(0.5), isSending: true, failureText: nil))

        viewModel.edits = [key: .failed(.noAnswer)]
        XCTAssertEqual(
            viewModel.rowState(of: Self.editable),
            AttributesViewModel.RowState(
                value: .double(1), isSending: false, failureText: "Demo did not answer in time."))

        // Another layer's change says nothing here.
        viewModel.edits = [AttributeKey(layerID: 4, attributeID: "view.alpha"): .sending(nil)]
        XCTAssertEqual(viewModel.rowState(of: Self.editable).isSending, false)
    }

    /// A value that is not finite is never sent: the row goes back to the value it had.
    @MainActor
    func test_C_ATTR_09_aValueThatIsNotFiniteReachesTheModelAndIsNotSent() {
        let model = attributesStore()
        model.setEditingSupported(true)
        let viewModel = self.viewModel(for: model)
        model.select(3)
        let key = AttributeKey(layerID: 3, attributeID: "view.alpha")
        viewModel.setValue(for: key)(.double(.nan), false)
        XCTAssertEqual(model.edits, [key: .failed(.notFinite)])
        viewModel.edits = model.edits
        XCTAssertEqual(
            viewModel.rowState(of: Self.editable),
            AttributesViewModel.RowState(value: .double(1), isSending: false, failureText: nil))
    }

    /// An editor outlives the panel at most for the colour panel's pause; its hands keep
    /// nothing alive.
    @MainActor
    func test_C_SCALE_02_theEditorsHandsDoNotKeepTheModel() {
        weak var gone: AttributesStore?
        var hands: [() -> Void] = []
        do {
            let model = attributesStore()
            let viewModel = self.viewModel(for: model)
            let key = AttributeKey(layerID: 3, attributeID: "view.alpha")
            let set = viewModel.setValue(for: key)
            hands = [{ set(.double(0.5), false) }, viewModel.finish(for: key)]
            gone = model
        }
        XCTAssertNil(gone)
        for hand in hands { hand() }
    }

    // MARK: - Constraints

    @MainActor
    func test_C_LAYOUT_02_onlyALayerThatBacksAViewHasConstraints() throws {
        let model = attributesStore()
        let viewModel = self.viewModel(for: model)
        viewModel.tree = try LayerTree(try Fixtures.hierarchy())
        let constraints = try Fixtures.constraints(of: 3)

        model.select(3)
        let texts = try XCTUnwrap(
            viewModel.constraintRows(for: .loaded([], constraints: constraints)))
        XCTAssertEqual(texts.map(\.plainEquation), [
            "self.centerX = UIView.centerX",
            "self.top = Safe Area.top + 49",
            "self.width = 240",
            "CardView.top = self.bottom + 78",
        ])
        // The server gave none (P-HELLO-04), or the state is not an answer.
        XCTAssertNil(viewModel.constraintRows(for: .loaded([])))
        XCTAssertNil(viewModel.constraintRows(for: .loading))
        // Layer 8 backs no view.
        model.select(8)
        XCTAssertNil(viewModel.constraintRows(for: .loaded([], constraints: [])))
        // Layer 2 is a view without constraints.
        model.select(2)
        XCTAssertEqual(viewModel.constraintRows(for: .loaded([], constraints: [])), [])
    }

    // MARK: - Publishers

    @MainActor
    func test_C_ATTR_04_editingFollowsTheModelAndTheConnection() {
        let model = attributesStore()
        let connection = CurrentValueSubject<InspectionStore.Connection, Never>(.live)
        let viewModel = self.viewModel(for: model, connection: connection)
        let editing = Recorder(viewModel.editing)
        XCTAssertEqual(editing.values.map(\.0), [false])
        XCTAssertEqual(editing.values.map(\.2), [true])

        model.setEditingSupported(true)
        XCTAssertEqual(editing.values.map(\.0), [false, true])
        connection.send(.lost(waiting: false))
        XCTAssertEqual(editing.values.map(\.2), [true, true, false])
    }

    @MainActor
    func test_C_LAYOUT_02_theFirstTreeAndItsChangesComeApart() throws {
        let trees = CurrentValueSubject<LayerTree, Never>(.empty)
        let viewModel = self.viewModel(
            for: attributesStore(), tree: trees.eraseToAnyPublisher())
        let first = Recorder(viewModel.firstTree)
        let changes = Recorder(viewModel.treeChanges)
        let tree = try LayerTree(try Fixtures.hierarchy())
        trees.send(tree)
        XCTAssertEqual(first.values.map(\.count), [0])
        XCTAssertEqual(changes.values.map(\.count), [tree.count])
    }

    @MainActor
    func test_C_HIER_07_theHeaderSkipsTheSameLayerSentAgain() throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        let layers = PassthroughSubject<LayerSummary?, Never>()
        let viewModel = self.viewModel(for: attributesStore(), layer: layers.eraseToAnyPublisher())
        let shown = Recorder(viewModel.layer)
        layers.send(LayerSummary(tree, 3))
        layers.send(LayerSummary(tree, 3))
        layers.send(nil)
        XCTAssertEqual(shown.values.map { $0?.id }, [3, nil])
    }
}
