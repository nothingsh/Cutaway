import Combine
import CutawayModel

/// What the interface says about one layer outside the list: its title and icon, what holds
/// it, its classes and addresses, and its size.
struct LayerSummary: Equatable {
    /// One of the layer's ancestors as the header names it (C-ATTR-16).
    struct Ancestor: Equatable {
        var id: UInt64
        var icon: LayerIcon
        /// Its short name (`LayerTree.shortTitle(of:)`).
        var title: String
    }

    var id: UInt64
    var title: String
    var icon: LayerIcon
    /// The header's second line (C-HIER-07): the nearest member that holds the layer, or the
    /// view controller whose root view it backs; nil when neither. Never an address: those are
    /// each under their own class (C-ATTR-11).
    var subtitle: String?
    /// "200 × 44", or nil when the layer has no bounds.
    var size: String?
    /// The second line of the attribute panel's header: what holds the layer and its size
    /// (C-HIER-07, C-ATTR-18); nil when there is neither.
    var headerLine: String? {
        let parts = [subtitle, size].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The view's readable class, or the layer's for a layer that backs no view (C-ATTR-10).
    var className: String?
    /// The layer's readable class, for a layer that backs a view.
    var layerClassName: String?
    /// The addresses as the panel writes them, or nil when the server sent none (C-ATTR-11).
    /// Only shown: the layer is known by its ID (P-HIER-15).
    var viewAddress: String?
    var layerAddress: String?
    var controllerAddress: String?
    /// The view controller whose root view the layer backs (C-HIER-07).
    var controller: String?
    /// "Owner.name" of each member that holds the layer, nearest first (C-HIER-07).
    var references: [String]
    /// Whether the layer backs a view, and so can have constraints (P-LAYOUT-01).
    var backsView: Bool
    /// From the window's root layer down to the layer's parent (C-ATTR-16).
    var ancestors: [Ancestor]

    init?(_ tree: LayerTree, _ id: UInt64?) {
        guard let id, let node = tree.node(id) else { return nil }
        self.id = id
        title = tree.displayTitle(of: id)
        icon = LayerIcon(node)
        let layerClass = [node.displayClassName, node.className].compactMap { $0 }
            .first { !$0.isEmpty }
        let viewClass = [node.viewDisplayClassName, node.viewClassName].compactMap { $0 }
            .first { !$0.isEmpty }
        let backsView = viewClass != nil
        self.backsView = backsView
        className = viewClass ?? layerClass
        layerClassName = backsView ? layerClass : nil
        viewAddress = node.viewAddress.map(AttributeText.address)
        layerAddress = node.layerAddress.map(AttributeText.address)
        controllerAddress = node.viewControllerAddress.map(AttributeText.address)
        controller = tree.viewControllerTitle(of: id)
        references = tree.memberTitles(of: id)
        subtitle = references.first ?? controller.map { localized("attributes.header.rootView", $0) }
        ancestors = tree.path(to: id).dropLast().map { ancestor in
            Ancestor(id: ancestor, icon: LayerIcon(tree.node(ancestor)), title: tree.shortTitle(of: ancestor))
        }
        size = node.bounds.map {
            "\(AttributeText.number($0.size.width)) × \(AttributeText.number($0.size.height))"
        }
    }
}

extension InspectionStore {
    /// What the interface says about the selected layer, as the selection and the tree change;
    /// nil while no layer in the tree is selected.
    var selectedLayerSummary: AnyPublisher<LayerSummary?, Never> {
        Publishers.CombineLatest($selectedLayerID, $tree)
            .map { id, tree in LayerSummary(tree, id) }
            .eraseToAnyPublisher()
    }
}
