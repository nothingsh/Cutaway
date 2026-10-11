import Combine
import CutawayModel
import CutawayWire

/// What the attribute panel shows, derived from the attributes (C-ATTR-01 to C-ATTR-06,
/// C-LAYOUT-02): the message in place of the list, which rows have editors and when the list
/// must be built again, what each row shows while a change is on its way or after it failed,
/// and the constraints as the panel writes them. It hands the editors' changes to the store.
///
/// It only builds publishers when asked; the panel subscribes to them where it lays itself
/// out, each on its own and in its order. What the store said last is kept here as the panel
/// passes it on from the publishers, which send before the store changes: it is never read
/// back from the store.
@MainActor
final class AttributesViewModel {
    /// What the panel says in place of the attributes.
    struct Message: Equatable {
        var symbol: String?
        var title: String
        var detail: String?
        var showsSpinner = false
        var offersRetry = false
    }

    /// What decides whether the list is built again: the layer, the groups and attributes
    /// with their kinds, and which have editors.
    struct Shape: Equatable {
        struct Row: Equatable {
            var id: String?
            var title: String?
            var kind: AttributeValueKind
            var hasEditor: Bool
        }

        var layerID: UInt64?
        var groups: [[Row]]
        var groupTitles: [String?]
        var groupIDs: [String?]
    }

    /// What a row shows: the value, a change on its way, or why the last one failed.
    struct RowState: Equatable {
        var value: AttributeValue?
        var isSending: Bool
        var failureText: String?
    }

    let store: AttributesStore
    let appName: String
    private let selectedLayer: AnyPublisher<LayerSummary?, Never>
    private let trees: AnyPublisher<LayerTree, Never>
    private let connection: AnyPublisher<InspectionStore.Connection, Never>

    /// Whether the store can change attributes, the changes under way or failed, and whether
    /// the connection holds (C-WIN-03), as last published.
    var canEdit = false
    var edits: [AttributeKey: EditStatus] = [:]
    var isConnected = true
    /// The hierarchy, for the names of the layers constraints relate.
    var tree = LayerTree.empty

    init(
        store: AttributesStore, appName: String, layer: AnyPublisher<LayerSummary?, Never>,
        tree: AnyPublisher<LayerTree, Never>,
        connection: AnyPublisher<InspectionStore.Connection, Never> = Just(.live).eraseToAnyPublisher()
    ) {
        self.store = store
        self.appName = appName
        selectedLayer = layer
        trees = tree
        self.connection = connection
    }

    // MARK: - Publishers

    /// The selected layer, for the header. Not shared: each subscriber gets the current value
    /// when it subscribes.
    var layer: AnyPublisher<LayerSummary?, Never> {
        selectedLayer.removeDuplicates().eraseToAnyPublisher()
    }

    /// The tree there is now, for the first list.
    var firstTree: AnyPublisher<LayerTree, Never> {
        trees.prefix(1).eraseToAnyPublisher()
    }

    /// Whether the store can change attributes, the changes, and whether the connection
    /// holds: any of them builds the rows' editors again.
    var editing: AnyPublisher<(Bool, [AttributeKey: EditStatus], Bool), Never> {
        Publishers.CombineLatest3(
            store.$canEdit, store.$edits, connection.map { !$0.isLost }.removeDuplicates()
        )
        .eraseToAnyPublisher()
    }

    var state: AnyPublisher<AttributesStore.State, Never> {
        store.$state.eraseToAnyPublisher()
    }

    /// The tree's changes after the first, which rename the constraints' ends.
    var treeChanges: AnyPublisher<LayerTree, Never> {
        trees.dropFirst().eraseToAnyPublisher()
    }

    // MARK: - What is shown

    /// What the panel says in place of the attributes, or nil when it lists them: the
    /// attributes, or the Constraints section when there is one.
    nonisolated static func message(
        for state: AttributesStore.State, appName: String, hasConstraints: Bool = false
    ) -> Message? {
        switch state {
        case .none:
            return Message(
                symbol: "cursorarrow.click.2", title: localized("attributes.empty.noSelection.title"),
                detail: localized("attributes.empty.noSelection.detail"))
        case .loading:
            return Message(symbol: nil, title: localized("attributes.empty.loading.title"), showsSpinner: true)
        case .loaded(let groups, _):
            return groups.isEmpty && !hasConstraints
                ? Message(symbol: "list.bullet.rectangle", title: localized("attributes.empty.none.title")) : nil
        case .layerGone:
            return Message(
                symbol: "questionmark.square.dashed", title: localized("attributes.empty.notFound.title"),
                detail: localized("attributes.empty.notFound.detail"))
        case .appNotActive:
            return Message(
                symbol: "moon.zzz", title: localized("attributes.empty.notActive.title", appName),
                detail: localized("attributes.empty.notActive.detail"))
        case .failed:
            return Message(
                symbol: "exclamationmark.triangle", title: localized("attributes.empty.failed.title"),
                detail: localized("attributes.empty.failed.detail"), offersRetry: true)
        }
    }

    /// The selected layer's constraints as the panel writes them, or nil when there is no
    /// Constraints section: the server gives none (P-HELLO-04), or the layer backs no view
    /// (P-LAYOUT-01).
    func constraintRows(for state: AttributesStore.State) -> [ConstraintRow]? {
        guard case .loaded(_, let constraints?) = state, let id = store.selectedID,
              LayerSummary(tree, id)?.backsView == true
        else { return nil }
        return constraints.map { ConstraintRow($0, selected: id, tree: tree) }
    }

    // MARK: - Changing attributes

    /// What the warning sign of a row says when a change failed (C-ATTR-06), or nil for no
    /// sign. None of them is a window.
    nonisolated static func failureText(_ failure: EditFailure, appName: String) -> String? {
        switch failure {
        // The app keeps the value it holds, a valid one, and that is what the row shows:
        // nothing to say (reported by the user).
        case .rejected: return nil
        case .notEditable: return localized("attributes.edit.notEditable")
        case .appNotActive: return localized("attributes.edit.notActive", appName)
        case .noAnswer: return localized("attributes.edit.noAnswer", appName)
        // Like a typed value that is not a number: the row goes back to the value it had.
        case .notFinite: return nil
        }
    }

    /// Whether rows offer editors now (C-ATTR-04).
    var offersEditors: Bool { canEdit && isConnected }

    func shape(of groups: [AttributeGroup]) -> Shape {
        Shape(
            layerID: store.selectedID,
            groups: groups.map { group in
                group.attributes.map { attribute in
                    Shape.Row(
                        id: attribute.id, title: attribute.title, kind: attribute.valueKind,
                        hasEditor: hasEditor(attribute))
                }
            },
            groupTitles: groups.map(\.title), groupIDs: groups.map(\.id))
    }

    func hasEditor(_ attribute: Attribute) -> Bool {
        offersEditors && attribute.isEditable && attribute.id != nil && store.selectedID != nil
    }

    func key(of attribute: Attribute) -> AttributeKey? {
        guard let id = attribute.id, let layer = store.selectedID else { return nil }
        return AttributeKey(layerID: layer, attributeID: id)
    }

    /// A row's value and state: a row being changed shows the value on its way.
    func rowState(of attribute: Attribute) -> RowState {
        let status = key(of: attribute).flatMap { edits[$0] }
        switch status {
        case .sending(let value):
            return RowState(value: value, isSending: true, failureText: nil)
        case .failed(let failure):
            return RowState(
                value: attribute.value, isSending: false,
                failureText: Self.failureText(failure, appName: appName))
        case nil:
            return RowState(value: attribute.value, isSending: false, failureText: nil)
        }
    }

    /// Sends what an editor set for an attribute. The store is held weakly: the editor can
    /// outlive the panel.
    func setValue(for key: AttributeKey) -> (AttributeValue?, _ continuous: Bool) -> Void {
        { [weak store] value, continuous in store?.set(key, to: value, continuous: continuous) }
    }

    /// Ends the change an editor made to an attribute, as `setValue(for:)` holds the store.
    func finish(for key: AttributeKey) -> () -> Void {
        { [weak store] in store?.finish(key) }
    }
}
