import Combine
import CutawayModel
import CutawayWire

/// What the attribute panel shows, derived from the attributes (C-ATTR-01 to C-ATTR-06,
/// C-ATTR-10, C-ATTR-14, C-LAYOUT-02): the message in place of the list, where each attribute
/// is listed, which rows a filter keeps, which rows have editors and when the list must be built
/// again, what each row shows while a change is on its way or after it failed, and the
/// constraints as the panel writes them. It hands the editors' changes to the store.
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

    /// Where the attributes are listed (C-ATTR-10, C-ATTR-26): six sections by what the
    /// attributes are for, in a fixed order.
    struct Listing: Equatable {
        /// The sections, in the order of the list.
        enum Kind: String, CaseIterable, Equatable {
            case content, appearance, layout, behavior, accessibility, object
        }

        /// The attributes one group gives a section.
        struct Part: Equatable {
            var groupID: String?
            var groupTitle: String?
            /// The class that declares the group's properties (P-ATTR-16).
            var groupClassName: String?
            var attributes: [Attribute]
            /// The rows the part lists (C-ATTR-19): its attributes, a cluster as one item in
            /// the place of its first member. Nil lists each attribute on its own.
            var items: [AttributeClusters.Item]?

            /// The items listed, in order.
            var listed: [AttributeClusters.Item] {
                items ?? attributes.map(AttributeClusters.Item.single)
            }
        }

        /// A section with attributes: its groups' parts, from the most specific group to the
        /// most general.
        struct Section: Equatable {
            var kind: Kind
            var parts: [Part]

            /// Every attribute in the order the section lists it: a cluster's members
            /// together, where the cluster is.
            var attributes: [Attribute] { parts.flatMap { $0.listed.flatMap(\.attributes) } }
        }

        /// Only the sections that have attributes, in the order of `Kind`.
        var sections: [Section]

        func section(_ kind: Kind) -> Section? {
            sections.first { $0.kind == kind }
        }

        /// Every attribute in the order the list shows it.
        var attributes: [Attribute] {
            sections.flatMap(\.attributes)
        }
    }

    /// What decides whether the list is built again: the layer, the groups and attributes
    /// with their kinds, sections and limits, and which have editors.
    struct Shape: Equatable {
        struct Row: Equatable {
            var id: String?
            var title: String?
            var kind: AttributeValueKind
            var section: AttributeSection
            var limits: [NumberLimit]?
            var unit: AttributeUnit
            var cluster: AttributeCluster?
            var hasEditor: Bool
        }

        var layerID: UInt64?
        var groups: [[Row]]
        var groupTitles: [String?]
        var groupIDs: [String?]
        var groupClassNames: [String?]
    }

    /// What a row shows: the value, a change on its way, or why the last one failed; what the
    /// value is known by (a colour's name, a text's key), and why the value has no effect.
    struct RowState: Equatable {
        var value: AttributeValue?
        var isSending: Bool
        var failureText: String?
        var names = ValueNames.none
        var inactiveReason: String?
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
    /// The app's project folder as last indexed, for the names of colours and texts
    /// (C-SRC-04, C-SRC-05); nil without one.
    var projectIndex: ProjectIndex?

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

    /// Whether the connection holds (C-WIN-03).
    var isLive: AnyPublisher<Bool, Never> {
        connection.map { !$0.isLost }.removeDuplicates().eraseToAnyPublisher()
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

    /// What the panel says in place of the attributes, or nil when it lists them. Loaded
    /// attributes are always listed: the Identity section describes the layer whatever it has.
    nonisolated static func message(
        for state: AttributesStore.State, appName: String
    ) -> Message? {
        switch state {
        case .none:
            return Message(
                symbol: "cursorarrow.click.2", title: localized("attributes.empty.noSelection.title"),
                detail: localized("attributes.empty.noSelection.detail"))
        case .loading:
            return Message(symbol: nil, title: localized("attributes.empty.loading.title"), showsSpinner: true)
        case .loaded:
            return nil
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

    /// Where the attributes are listed (C-ATTR-10): each in the section its `section` names,
    /// General, Unspecified and values this client does not know in Appearance, Identity in
    /// Object. Within a section the groups go in reverse, from the most specific to the most
    /// general, as the server sends them the other way round, and a group's attributes in the
    /// order they came. A section without attributes is not listed. Only the sections decide,
    /// never the IDs (C-ATTR-03).
    nonisolated static func listing(of groups: [AttributeGroup]) -> Listing {
        var parts: [Listing.Kind: [Listing.Part]] = [:]
        for group in groups.reversed() {
            var byKind: [Listing.Kind: [Attribute]] = [:]
            for attribute in group.attributes {
                byKind[kind(of: attribute.section), default: []].append(attribute)
            }
            for (kind, attributes) in byKind {
                parts[kind, default: []].append(Listing.Part(
                    groupID: group.id, groupTitle: group.title, groupClassName: group.className,
                    attributes: attributes))
            }
        }
        return Listing(sections: Listing.Kind.allCases.compactMap { kind in
            guard var parts = parts[kind] else { return nil }
            // A cluster gathers its members from every group of the section (C-ATTR-19).
            let items = AttributeClusters.items(of: parts.map(\.attributes))
            for index in parts.indices { parts[index].items = items[index] }
            return Listing.Section(kind: kind, parts: parts)
        })
    }

    /// The section an attribute is listed in.
    nonisolated static func kind(of section: AttributeSection) -> Listing.Kind {
        switch section {
        case .content: .content
        case .appearance, .general, .unspecified: .appearance
        case .layout: .layout
        case .behavior: .behavior
        case .accessibility: .accessibility
        case .identity: .object
        }
    }

    /// The filter as it is matched: nil when it keeps everything (C-ATTR-14).
    nonisolated static func filterText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Where a title holds the filter, ignoring case; nil when it does not (C-ATTR-14).
    nonisolated static func match(of filter: String, in title: String) -> Range<String.Index>? {
        title.range(of: filter, options: [.caseInsensitive, .diacriticInsensitive])
    }

    /// The selected layer's constraints as the panel writes them, or nil when there is no
    /// Constraints section: nothing is loaded, or the layer backs no view (P-LAYOUT-01).
    func constraintRows(for state: AttributesStore.State) -> [ConstraintRow]? {
        guard case .loaded(_, let constraints) = state, let id = store.selectedID,
              LayerSummary(tree, id)?.backsView == true
        else { return nil }
        return constraints.enumerated().map {
            ConstraintRow($0.element, selected: id, tree: tree, index: $0.offset)
        }
    }

    // MARK: - Changing attributes

    /// What the warning sign of a row says when a change failed (C-ATTR-06), or nil for no
    /// sign. None of them is a window. `kind` names the components of a value outside its
    /// limits (C-ATTR-13).
    nonisolated static func failureText(
        _ failure: EditFailure, kind: AttributeValueKind, unit: AttributeUnit = .unspecified,
        appName: String
    ) -> String? {
        switch failure {
        case .rejected: return localized("attributes.edit.rejected")
        case .notEditable: return localized("attributes.edit.notEditable")
        case .appNotActive: return localized("attributes.edit.notActive", appName)
        case .noAnswer: return localized("attributes.edit.noAnswer", appName)
        // Like a typed value that is not a number: the row goes back to the value it had.
        case .notFinite: return nil
        case .outOfRange(let violation): return LimitText.message(violation, kind: kind, unit: unit)
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
                        section: attribute.section, limits: attribute.limits, unit: attribute.unit,
                        cluster: attribute.cluster, hasEditor: hasEditor(attribute))
                }
            },
            groupTitles: groups.map(\.title), groupIDs: groups.map(\.id),
            groupClassNames: groups.map(\.className))
    }

    func hasEditor(_ attribute: Attribute) -> Bool {
        offersEditors && attribute.isEditable && attribute.id != nil && store.selectedID != nil
    }

    /// Whether the selected layer's lists count rows or items (C-ATTR-27): a table's do.
    var clusterWords: ClusterText.Words {
        ClusterText.Words(viewBaseClassName: store.selectedID.flatMap { tree.node($0)?.viewBaseClassName })
    }

    func key(of attribute: Attribute) -> AttributeKey? {
        guard let id = attribute.id, let layer = store.selectedID else { return nil }
        return AttributeKey(layerID: layer, attributeID: id)
    }

    /// A row's value and state: a row being changed shows the value on its way. `layer` is
    /// every attribute of the layer, where the one that makes this one have no effect is.
    func rowState(of attribute: Attribute, among layer: [Attribute] = []) -> RowState {
        let status = key(of: attribute).flatMap { edits[$0] }
        var state = switch status {
        case .sending(let value):
            RowState(value: value, isSending: true, failureText: nil)
        case .failed(let failure):
            RowState(
                value: attribute.value, isSending: false,
                failureText: Self.failureText(
                    failure, kind: attribute.valueKind, unit: attribute.unit, appName: appName))
        case nil:
            RowState(value: attribute.value, isSending: false, failureText: nil)
        }
        // The names are the app's value's: a value on its way has none.
        if state.value == attribute.value { state.names = ValueNames(attribute, index: projectIndex) }
        state.inactiveReason = Self.inactiveReason(of: attribute, among: layer)
        return state
    }

    /// Why an attribute has no effect now (C-ATTR-21): "No effect while Border Width is 0 pt",
    /// from the title and value of the attribute its `inactiveCause` names; nil when it names
    /// none, or one the layer does not have. Only what the server marks counts (C-ATTR-03).
    nonisolated static func inactiveReason(of attribute: Attribute, among layer: [Attribute]) -> String? {
        guard let id = attribute.inactiveCause,
              let cause = layer.first(where: { $0.id == id })
        else { return nil }
        return localized(
            "attributes.inactive.reason", AttributeText.title(cause.title, id: cause.id),
            AttributeText.text(of: cause.value, unit: cause.unit))
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
