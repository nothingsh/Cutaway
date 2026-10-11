import CutawayModel

/// What the hierarchy list works out from a tree about its rows, without the outline view.
enum HierarchyOutlineSync {
    /// Whether two trees give the same rows: the same layers, under the same parents, with
    /// the same titles, details and dimming.
    static func sameRows(_ a: LayerTree, _ b: LayerTree) -> Bool {
        guard a.ids == b.ids else { return false }
        return a.ids.allSatisfy { id in
            a.parent(of: id) == b.parent(of: id) && a.title(of: id) == b.title(of: id)
                && a.isDimmed(id) == b.isDimmed(id)
                && a.viewControllerTitle(of: id) == b.viewControllerTitle(of: id)
                && a.memberTitles(of: id) == b.memberTitles(of: id)
        }
    }

    /// The layers among `ids` and inside them that have sublayers, are expanded, and whose
    /// every sublayer with sublayers of its own is too: a whole part of the tree expanded.
    static func wholeExpansions(
        below ids: [UInt64], in tree: LayerTree, isExpanded: (UInt64) -> Bool
    ) -> Set<UInt64> {
        var whole = Set<UInt64>()
        // Each layer after everything inside it.
        var order: [UInt64] = []
        var pending = ids
        while let id = pending.popLast() {
            order.append(id)
            pending.append(contentsOf: tree.children(of: id))
        }
        for id in order.reversed() {
            let children = tree.children(of: id)
            guard !children.isEmpty, isExpanded(id) else { continue }
            if children.allSatisfy({ tree.children(of: $0).isEmpty || whole.contains($0) }) {
                whole.insert(id)
            }
        }
        return whole
    }
}
