import CutawayModel
import CutawayScene

/// Which rows of the list mark what the last refresh changed (C-LIVE-05).
enum HierarchyChangeMarks {
    /// A new or changed layer marks its own row. One inside a collapsed row, or otherwise
    /// without a row of its own, marks the nearest row above it as changed: something inside
    /// it changed. A row's own mark wins over one from inside it. `hasRow` says
    /// whether the list shows a layer's row now.
    static func rows(
        of diff: RefreshDiff, in tree: LayerTree, hasRow: (UInt64) -> Bool
    ) -> [UInt64: ChangeMark] {
        var rows: [UInt64: ChangeMark] = [:]
        var inside: Set<UInt64> = []
        for (ids, mark) in [(diff.added, ChangeMark.added), (diff.changed, .changed)] {
            for id in ids {
                if hasRow(id) {
                    rows[id] = mark
                } else if let shown = tree.path(to: id).dropLast().last(where: hasRow) {
                    inside.insert(shown)
                }
            }
        }
        for id in inside where rows[id] == nil {
            rows[id] = .changed
        }
        return rows
    }
}
