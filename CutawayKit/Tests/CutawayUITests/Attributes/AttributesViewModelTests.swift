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

    // MARK: - Changing attributes

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
                id: "view.alpha", title: "Alpha", kind: .double, section: .unspecified, limits: nil, unit: .unspecified,
                hasEditor: false)]],
            groupTitles: ["View"], groupIDs: ["view"], groupClassNames: [nil]))

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
            "self.centerX = HomeViewController.centerX",
            "self.top = Safe Area.top + 49",
            "self.width = 240",
            "cardView.top = self.bottom + 78",
        ])
        // The state is not an answer.
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

    // MARK: - C-ATTR-10: five sections

    private static func attribute(_ id: String, _ section: AttributeSection) -> Attribute {
        Attribute(id: id, title: id, value: .integer(0), section: section)
    }

    private static func ids(_ attributes: [Attribute]) -> [String?] {
        attributes.map(\.id)
    }

    private static func ids(
        _ listing: AttributesViewModel.Listing, _ kind: AttributesViewModel.Listing.Kind
    ) -> [String?] {
        ids(listing.section(kind)?.attributes ?? [])
    }

    private static func layerThree() throws -> [AttributeGroup] {
        try XCTUnwrap(try Fixtures.layerDetails(scenario: "layer-details").first { $0.layerID == 3 })
            .attributeGroups
    }

    func test_C_ATTR_10_eachAttributeIsListedOnceInTheSectionOfItsPurpose() throws {
        let groups = try Self.layerThree()
        let listing = AttributesViewModel.listing(of: groups)
        XCTAssertEqual(listing.sections.map(\.kind), [.content, .appearance, .layout, .behavior, .object])
        XCTAssertEqual(
            Self.ids(listing, .content),
            ["label.text", "label.fontSize", "label.fontTextStyle",
             "label.adjustsFontForContentSizeCategory", "label.numberOfLines", "label.textAlignment"])
        XCTAssertEqual(listing.section(.content)?.parts.map(\.groupTitle), ["Label"])
        XCTAssertEqual(listing.section(.content)?.parts.map(\.groupClassName), ["UILabel"])
        // From the most specific group to the most general, each group as it came.
        XCTAssertEqual(Self.ids(listing, .appearance), [
            "view.isHidden", "view.alpha", "view.backgroundColor", "view.tintColor",
            "view.accessibilityLabel", "layer.shadowOpacity", "layer.shadowOffset", "layer.borderWidth",
            "layer.borderColor",
        ])
        XCTAssertEqual(
            Self.ids(listing, .layout),
            ["view.layoutMargins", "layer.frame", "layer.bounds", "layer.position", "layer.transform"])
        XCTAssertEqual(Self.ids(listing, .behavior), ["view.isUserInteractionEnabled"])
        XCTAssertEqual(Self.ids(listing, .object), ["view.tag"])
        // Every attribute exactly once.
        let listed = Self.ids(listing.attributes)
        XCTAssertEqual(listed.count, groups.flatMap(\.attributes).count)
        XCTAssertEqual(Set(listed), Set(groups.flatMap(\.attributes).map(\.id)))
    }

    func test_C_ATTR_10_generalUnspecifiedAndUnknownSectionsAreAppearance() {
        let groups = [AttributeGroup(id: "view", title: "View", attributes: [
            Self.attribute("a", .general), Self.attribute("b", .unspecified),
            Self.attribute("c", .appearance),
        ])]
        let listing = AttributesViewModel.listing(of: groups)
        XCTAssertEqual(listing.sections.map(\.kind), [.appearance])
        XCTAssertEqual(Self.ids(listing, .appearance), ["a", "b", "c"])
    }

    func test_C_ATTR_10_theContentOfSeveralGroupsKeepsThemApart() {
        let groups = [
            AttributeGroup(id: "view", title: "View", attributes: [Self.attribute("hidden", .appearance)]),
            AttributeGroup(id: "control", title: "Control", attributes: [Self.attribute("enabled", .content)],
                           className: "UIControl"),
            AttributeGroup(id: "button", title: "Button", attributes: [Self.attribute("title", .content)],
                           className: "UIButton"),
            AttributeGroup(id: "empty", title: "Empty", attributes: []),
        ]
        let listing = AttributesViewModel.listing(of: groups)
        let content = try? XCTUnwrap(listing.section(.content))
        XCTAssertEqual(content?.parts.map(\.groupTitle), ["Button", "Control"], "the most specific first")
        XCTAssertEqual(content?.parts.map(\.groupClassName), ["UIButton", "UIControl"])
        XCTAssertEqual(Self.ids(listing.attributes), ["title", "enabled", "hidden"])
        XCTAssertEqual(listing.sections.map(\.kind), [.content, .appearance], "no empty sections")
    }

    func test_C_ATTR_10_olderPeersFallBackToAppearance() throws {
        // A server whose sections are Identity, Layout and General only.
        let bare = AttributesViewModel.listing(of: Fixtures.withoutTheOptionalFields(try Self.layerThree()))
        XCTAssertEqual(bare.sections.map(\.kind), [.appearance, .layout, .object])
        XCTAssertEqual(Self.ids(bare, .appearance), [
            "view.isHidden", "view.alpha", "view.backgroundColor", "view.tintColor",
            "view.isUserInteractionEnabled", "view.accessibilityLabel",
            "label.text", "label.fontSize", "label.fontTextStyle",
            "label.adjustsFontForContentSizeCategory", "label.numberOfLines", "label.textAlignment",
            "layer.shadowOpacity", "layer.shadowOffset", "layer.borderWidth", "layer.borderColor",
        ])
        // A 1.0 server: no sections at all.
        let old = AttributesViewModel.listing(of: Fixtures.withoutProtocol11(try Self.layerThree()))
        XCTAssertEqual(old.sections.map(\.kind), [.appearance])
        XCTAssertEqual(old.attributes.count, 22)
    }

    func test_C_WIRE_12_accessibilityIsListedWithAppearanceForNow() {
        // Until C-ATTR-26 gives Accessibility a section of its own.
        let groups = [AttributeGroup(id: "view", title: "View", attributes: [
            Self.attribute("hidden", .appearance), Self.attribute("label", .accessibility),
            Self.attribute("enabled", .behavior),
        ])]
        let listing = AttributesViewModel.listing(of: groups)
        XCTAssertEqual(listing.sections.map(\.kind), [.appearance, .behavior])
        XCTAssertEqual(Self.ids(listing, .appearance), ["hidden", "label"])
    }

    func test_C_ATTR_10_theListingDependsOnTheSectionAlone() {
        // The IDs of groups and attributes mean nothing to the listing (C-ATTR-03).
        let named = [
            AttributeGroup(id: "layer", title: "Layer", attributes: [
                Self.attribute("layer.frame", .behavior), Self.attribute("view.tag", .layout),
                Self.attribute("layer.bounds", .identity), Self.attribute("label.text", .appearance),
            ]),
        ]
        let renamed = [
            AttributeGroup(id: "x9", title: "Q", attributes: [
                Self.attribute("zz", .behavior), Self.attribute("yy", .layout),
                Self.attribute("ww", .identity), Self.attribute("vv", .appearance),
            ]),
        ]
        for groups in [named, renamed] {
            let listing = AttributesViewModel.listing(of: groups)
            XCTAssertEqual(listing.sections.map(\.kind), [.appearance, .layout, .behavior, .object])
            XCTAssertEqual(listing.sections.map(\.attributes.count), [1, 1, 1, 1])
        }
    }

    // MARK: - C-ATTR-14: the filter

    @MainActor
    func test_C_ATTR_10_theShapeChangesWithTheSection() {
        let viewModel = self.viewModel(for: attributesStore())
        let general = [AttributeGroup(id: "g", title: "G", attributes: [Self.attribute("a", .general)])]
        let layout = [AttributeGroup(id: "g", title: "G", attributes: [Self.attribute("a", .layout)])]
        XCTAssertNotEqual(viewModel.shape(of: general), viewModel.shape(of: layout))
    }
}
