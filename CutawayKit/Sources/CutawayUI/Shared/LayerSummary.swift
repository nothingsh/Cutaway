import Combine
import CutawayModel

/// What the interface says about one layer outside the list: its title and symbol, its
/// layer class and ID, and its size.
struct LayerSummary: Equatable {
    var id: UInt64
    var title: String
    var symbol: String
    /// "_UILabelLayer · ID 58", or "ID 58" for a layer that backs no view.
    var subtitle: String
    /// "200 × 44", or nil when the layer has no bounds.
    var size: String?
    /// The view controller whose root view the layer backs (C-HIER-07).
    var controller: String?
    /// "Owner.name" of each member that holds the layer, nearest first (C-HIER-07).
    var references: [String]
    /// Whether the layer backs a view, and so can have constraints (P-LAYOUT-01).
    var backsView: Bool

    init?(_ tree: LayerTree, _ id: UInt64?) {
        guard let id, let node = tree.node(id) else { return nil }
        self.id = id
        title = tree.displayTitle(of: id)
        symbol = LayerSymbol.name(for: node)
        let layerClass = [node.displayClassName, node.className].compactMap { $0 }
            .first { !$0.isEmpty }
        let backsView = [node.viewDisplayClassName, node.viewClassName].contains {
            !($0 ?? "").isEmpty
        }
        self.backsView = backsView
        subtitle = [backsView ? layerClass : nil, "ID \(id)"].compactMap { $0 }
            .joined(separator: " · ")
        controller = tree.viewControllerTitle(of: id)
        references = tree.memberTitles(of: id)
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
