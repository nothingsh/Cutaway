/// Which nodes of the tree are expanded (C-HIER-02): one entry for every layer of the tree it
/// was made for. A layer that is not in it counts as collapsed.
struct Expansion: Equatable, Sendable {
    private var byLayer: [UInt64: Bool] = [:]

    init() {}

    /// False for a layer that is not in the tree.
    func isExpanded(_ id: UInt64) -> Bool {
        byLayer[id] ?? false
    }

    /// Whether the layer is in the tree the expansion was made for.
    func knows(_ id: UInt64) -> Bool {
        byLayer[id] != nil
    }

    subscript(id: UInt64) -> Bool? {
        get { byLayer[id] }
        set { byLayer[id] = newValue }
    }

    /// Every expanded node.
    var expandedIDs: Set<UInt64> {
        Set(byLayer.lazy.filter(\.value).map(\.key))
    }

    /// The row that stands for a layer in the list: the layer itself, or the outermost
    /// collapsed node it is inside of, looking no higher than the focus.
    func standIn(for id: UInt64, in tree: LayerTree, focus: UInt64?) -> UInt64 {
        LayerTree.standIn(for: id, in: tree, expansion: byLayer, focus: focus)
    }

    /// Expands every ancestor of the layer. Returns whether any changed.
    mutating func expandAncestors(of id: UInt64, in tree: LayerTree) -> Bool {
        var changed = false
        var current = tree.parent(of: id)
        while let ancestor = current {
            if byLayer[ancestor] == false {
                byLayer[ancestor] = true
                changed = true
            }
            current = tree.parent(of: ancestor)
        }
        return changed
    }

    /// The expansion of a new tree: `restoring` when an archive's state is taken over,
    /// otherwise this one, with new layers opened by the rule (C-HIER-09); a layer without
    /// sublayers counts as expanded. The layers above a restored focus are opened, as
    /// focusing opens them.
    func forTree(
        _ newTree: LayerTree, restoring: Set<UInt64>?, focus restoredFocus: UInt64?,
        newLayers: InspectionStore.NewLayers
    ) -> Self {
        var new = Self()
        new.byLayer.reserveCapacity(newTree.count)
        // Worked out once, and only when there are new layers.
        var opened: Set<UInt64>?
        for id in newTree.ids {
            if let restoring {
                new.byLayer[id] = restoring.contains(id)
            } else if let known = byLayer[id] {
                new.byLayer[id] = known
            } else if newLayers == .expanded || newTree.children(of: id).isEmpty {
                new.byLayer[id] = true
            } else {
                if opened == nil { opened = newTree.defaultExpansion() }
                new.byLayer[id] = opened?.contains(id) == true
            }
        }
        var above = restoredFocus.flatMap { newTree.parent(of: $0) }
        while let ancestor = above {
            new.byLayer[ancestor] = true
            above = newTree.parent(of: ancestor)
        }
        return new
    }
}
