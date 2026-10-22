import CutawayWire

/// The rows the attribute panel shows, sorted by what they show: what new values and states
/// are given to (C-ATTR-06, C-ATTR-19). Of a part built page by page only the rows of the
/// pages built are here (C-SCALE-03).
@MainActor
struct ShownAttributeRows {
    /// Each attribute's own row with the attribute it shows, in the order of the list.
    private(set) var rows: [(attribute: Attribute, row: AttributeRowView)] = []
    /// What shows each attribute, its own row or a part of a compound row, in the order of
    /// `Listing.attributes`.
    private(set) var cells: [(attribute: Attribute, cell: any AttributeCell)] = []
    /// The compound rows, in the order of the list.
    private(set) var compounds: [CompoundRowView] = []

    init() {}

    /// The rows built for `built`'s items, in the order of the list.
    init(_ built: [(item: AttributeClusters.Item, row: any AttributeListRow)]) {
        rows = built.compactMap { item, row in
            guard case .single(let attribute) = item, let row = row as? AttributeRowView else { return nil }
            return (attribute, row)
        }
        cells = built.flatMap { item, row -> [(attribute: Attribute, cell: any AttributeCell)] in
            switch row {
            case let compound as CompoundRowView:
                zip(Self.attributes(of: item), compound.cells.map(\.cell)).map { (attribute: $0, cell: $1) }
            case let single as AttributeRowView:
                Self.attributes(of: item).map { (attribute: $0, cell: single) }
            default: []
            }
        }
        compounds = built.compactMap { $0.row as? CompoundRowView }
    }

    /// The same rows showing `attributes`, the same attributes with new values in the order
    /// of `cells`.
    mutating func show(_ attributes: [Attribute]) {
        cells = zip(attributes, cells.map(\.cell)).map { (attribute: $0, cell: $1) }
        rows = cells.compactMap { attribute, cell in
            (cell as? AttributeRowView).map { (attribute: attribute, row: $0) }
        }
    }

    /// The attributes an item's cells show, in the order of its cells.
    private static func attributes(of item: AttributeClusters.Item) -> [Attribute] {
        switch item {
        case .single(let attribute): [attribute]
        case .cluster(let row): row.order.compactMap { row[$0] }
        }
    }
}
