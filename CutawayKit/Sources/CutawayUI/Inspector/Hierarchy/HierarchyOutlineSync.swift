import CutawayModel
import CutawayWire

/// What the hierarchy list works out from a tree about its rows, without the outline view.
enum HierarchyOutlineSync {
    /// Whether two trees give the same rows: the same layers, under the same parents, with
    /// the same titles, details, icons and dimming.
    ///
    /// Called with every tree that comes, thousands of layers each: the nodes' own fields are
    /// compared, and the titles the details are made of only when those differ.
    static func sameRows(_ a: LayerTree, _ b: LayerTree) -> Bool {
        guard a.ids == b.ids else { return false }
        return a.ids.allSatisfy { id in
            guard let x = a.node(id), let y = b.node(id) else { return false }
            return x.parentID == y.parentID && a.title(of: id) == b.title(of: id)
                && a.isDimmed(id) == b.isDimmed(id)
                && sameViewControllerTitle(x, y, a, b, id)
                && sameIcon(x, y)
                && (x.memberReferences == y.memberReferences
                    || a.memberTitles(of: id) == b.memberTitles(of: id))
        }
    }

    /// Whether two nodes have the same icon: what `LayerIcon` reads of them is the same, or,
    /// where it differs, the icons it makes are.
    private static func sameIcon(_ x: LayerNode, _ y: LayerNode) -> Bool {
        let sameFields = x.kind == y.kind && x.className == y.className
            && x.displayClassName == y.displayClassName && x.layerClassOrigin == y.layerClassOrigin
            && x.layerBaseClassName == y.layerBaseClassName && x.viewClassName == y.viewClassName
            && x.viewDisplayClassName == y.viewDisplayClassName
            && x.viewClassOrigin == y.viewClassOrigin && x.viewBaseClassName == y.viewBaseClassName
            && x.viewControllerClassName == y.viewControllerClassName
            && x.viewControllerDisplayClassName == y.viewControllerDisplayClassName
            && x.viewControllerClassOrigin == y.viewControllerClassOrigin
        return sameFields || LayerIcon(x) == LayerIcon(y)
    }

    private static func sameViewControllerTitle(
        _ x: LayerNode, _ y: LayerNode, _ a: LayerTree, _ b: LayerTree, _ id: UInt64
    ) -> Bool {
        (x.viewControllerDisplayClassName == y.viewControllerDisplayClassName
            && x.viewControllerClassName == y.viewControllerClassName)
            || a.viewControllerTitle(of: id) == b.viewControllerTitle(of: id)
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
