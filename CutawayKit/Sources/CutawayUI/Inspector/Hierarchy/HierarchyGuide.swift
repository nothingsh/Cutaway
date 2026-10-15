/// One guide of a row (C-HIER-12): the line that runs down through the rows inside an expanded
/// row, at that row's level.
struct HierarchyGuide: Equatable {
    enum Style: Equatable {
        case plain
        /// The guide of the hovered row's parent.
        case hovered
        /// The guide of the selected row's parent.
        case selected
    }

    var level: Int
    var style: Style

    /// The guides of a row inside `ancestors`, outermost first: the row's level is
    /// `ancestors.count`, and the guide of level k belongs to `ancestors[k]`. The selected row's
    /// parent wins over the hovered row's.
    static func guides(
        ancestors: [UInt64], selectedParent: UInt64?, hoveredParent: UInt64?
    ) -> [Self] {
        ancestors.enumerated().map { level, id in
            let style: Style =
                id == selectedParent ? .selected : id == hoveredParent ? .hovered : .plain
            return Self(level: level, style: style)
        }
    }
}
