import CutawayModel

/// What one row of the hierarchy list shows (C-HIER-01): the layer's title and the symbol for
/// what it is; weaker for a layer that cannot be seen (C-HIER-03) or that the search shows only
/// because a match is inside it (C-HIER-04); and the view controller and members that hold it
/// (C-HIER-07).
struct HierarchyRow: Equatable {
    var title: String
    var isDimmed: Bool
    /// A row the search shows only because a match is inside it (C-HIER-04).
    var isContext: Bool
    var symbolName: String
    var detail: String?
    var toolTip: String?

    init(
        title: String, isDimmed: Bool, isContext: Bool = false,
        symbolName: String = LayerSymbol.view, detail: String? = nil, toolTip: String? = nil
    ) {
        self.title = title
        self.isDimmed = isDimmed
        self.isContext = isContext
        self.symbolName = symbolName
        self.detail = detail
        self.toolTip = toolTip
    }

    /// The row of a layer of the tree, with the search there is, if any.
    init(_ tree: LayerTree, _ id: UInt64, filter: HierarchyFilter?) {
        self.init(
            title: tree.displayTitle(of: id), isDimmed: tree.isDimmed(id),
            isContext: filter.map { !$0.matches.contains(id) } ?? false,
            symbolName: LayerSymbol.name(for: tree.node(id)),
            detail: Self.detail(tree, id), toolTip: Self.detailToolTip(tree, id))
    }

    /// What a row says after its title (C-HIER-07): the view controller it is the root view
    /// of, and the nearest member that holds it, with how many more there are.
    private static func detail(_ tree: LayerTree, _ id: UInt64) -> String? {
        var parts: [String] = []
        if let controller = tree.viewControllerTitle(of: id) { parts.append(controller) }
        let members = tree.memberTitles(of: id)
        if let nearest = members.first {
            parts.append(members.count > 1 ? "\(nearest) +\(members.count - 1)" : nearest)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{00B7} ")
    }

    /// Every view controller and member of a row, one to a line.
    private static func detailToolTip(_ tree: LayerTree, _ id: UInt64) -> String? {
        let lines = (tree.viewControllerTitle(of: id).map { [localized("hierarchy.row.viewController", $0)] } ?? [])
            + tree.memberTitles(of: id).map { localized("hierarchy.row.referencedBy", $0) }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
