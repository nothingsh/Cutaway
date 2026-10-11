/// How the inspection looks at its tree: which nodes are expanded (C-HIER-02), the focus
/// (C-HIER-05), the selected layer and the one under the pointer (C-PREV-03).
///
/// Its transitions only work out the new state and say what changed; the inspection that
/// holds it publishes the changes, in the order its interface needs. They keep what holds
/// across all of them: the selection is a row the list shows, never inside a collapsed node
/// or outside the focus, and the focus, the selection and the hover are layers of the tree.
struct HierarchyViewState: Equatable, Sendable {
    /// What a transition changed.
    struct Change: OptionSet, Sendable {
        let rawValue: Int

        static let expansion = Self(rawValue: 1 << 0)
        static let focus = Self(rawValue: 1 << 1)
        static let selection = Self(rawValue: 1 << 2)
        static let hover = Self(rawValue: 1 << 3)
    }

    var expansion = Expansion()
    /// The layer focused on, or nil for the whole tree.
    var focus: UInt64?
    var selection: UInt64?
    var hover: UInt64?

    // MARK: - Expansion

    /// Expands or collapses the layers of `ids` that are in the tree. A selection inside a
    /// node that collapses moves onto that node.
    mutating func setExpanded(_ ids: [UInt64], _ expanded: Bool, in tree: LayerTree) -> Change {
        let changed = ids.filter { tree.contains($0) && expansion[$0] != expanded }
        guard !changed.isEmpty else { return [] }
        for id in changed { expansion[id] = expanded }
        var change: Change = .expansion
        if !expanded { change.formUnion(moveSelectionToItsRow(in: tree)) }
        return change
    }

    /// Expands the layers of the focus, or of the whole tree, that are less than `n` deep, and
    /// collapses the rest (C-HIER-06). A selection inside a node that collapses moves onto it.
    mutating func expand(toDepth n: Int, in tree: LayerTree) -> Change {
        var changed = false
        for layer in tree.layers(within: focus) {
            let expanded = layer.depth < n
            if expansion[layer.id] != expanded {
                expansion[layer.id] = expanded
                changed = true
            }
        }
        guard changed else { return [] }
        return Change.expansion.union(moveSelectionToItsRow(in: tree))
    }

    // MARK: - Focus

    /// Focuses on a layer, or on the whole tree for nil (C-HIER-05). Nothing changes for a
    /// layer that is not in the tree. The layer's ancestors are expanded first, so that what
    /// is selected inside the focus is still a row once the focus ends. A selection outside
    /// the new focus moves onto it; otherwise onto the row that stands for it, which after
    /// leaving a focus may be a collapsed node above. A hover outside the focus ends.
    mutating func focus(on id: UInt64?, in tree: LayerTree) -> Change {
        if let id, !tree.contains(id) { return [] }
        guard id != focus else { return [] }
        var change: Change = .focus
        if let id, expansion.expandAncestors(of: id, in: tree) { change.insert(.expansion) }
        focus = id
        if let selected = selection {
            let target: UInt64
            if let id, !tree.isWithin(selected, root: id) {
                target = id
            } else {
                target = expansion.standIn(for: selected, in: tree, focus: id)
            }
            if target != selected {
                selection = target
                change.insert(.selection)
            }
        }
        if let id, let hovered = hover, !tree.isWithin(hovered, root: id) {
            hover = nil
            change.insert(.hover)
        }
        return change
    }

    // MARK: - Selection and hover

    /// Selects a layer, or nothing; a layer inside a collapsed node selects that node.
    /// Nothing changes for a layer that is not in the tree, or that is outside the focus.
    mutating func select(_ id: UInt64?, in tree: LayerTree) -> Change {
        var target = id
        if let id {
            guard tree.contains(id) else { return [] }
            if let focus, !tree.isWithin(id, root: focus) { return [] }
            target = expansion.standIn(for: id, in: tree, focus: focus)
        }
        guard target != selection else { return [] }
        selection = target
        return .selection
    }

    /// Selects a layer, expanding its ancestors first, so that the selection is the layer
    /// itself and not a collapsed node above it (C-HIER-04). Nothing changes for a layer that
    /// is not in the tree or outside the focus.
    mutating func reveal(_ id: UInt64, in tree: LayerTree) -> Change {
        guard tree.contains(id) else { return [] }
        if let focus, !tree.isWithin(id, root: focus) { return [] }
        var change: Change = []
        if expansion.expandAncestors(of: id, in: tree) { change.insert(.expansion) }
        return change.union(select(id, in: tree))
    }

    /// Records the layer under the pointer, or none. Nothing changes for a layer that is not
    /// in the tree.
    mutating func hover(_ id: UInt64?, in tree: LayerTree) -> Change {
        if let id, !tree.contains(id) { return [] }
        guard id != hover else { return [] }
        hover = id
        return .hover
    }

    // MARK: - A new tree

    /// Takes a new tree (C-HIER-02): layers that are still there keep their expansion, new
    /// ones open by the rule (C-HIER-09), and the state of layers that are gone is dropped.
    /// `restoring` takes an archive's expansion and focus over instead (C-ARCH-03). A focus on
    /// a layer that is gone ends; a selection that is gone ends too, one outside the focus
    /// moves onto it, and one inside a collapsed node onto that node. The expansion always
    /// counts as changed: it is made for the new tree.
    mutating func take(
        _ newTree: LayerTree, restoring: ArchiveState?, newLayers: InspectionStore.NewLayers
    ) -> Change {
        let restoredFocus = restoring?.focused.flatMap { newTree.contains($0) ? $0 : nil }
        expansion = expansion.forTree(
            newTree, restoring: restoring?.expanded, focus: restoredFocus, newLayers: newLayers)
        var change: Change = .expansion
        if let hovered = hover, !newTree.contains(hovered) {
            hover = nil
            change.insert(.hover)
        }
        let newFocus =
            restoring != nil ? restoredFocus : focus.flatMap { newTree.contains($0) ? $0 : nil }
        if newFocus != focus {
            focus = newFocus
            change.insert(.focus)
        }
        let newSelection = selection.flatMap { id -> UInt64? in
            guard newTree.contains(id) else { return nil }
            // A selected layer that moved out of the focus hands the selection to it.
            if let newFocus, !newTree.isWithin(id, root: newFocus) { return newFocus }
            return expansion.standIn(for: id, in: newTree, focus: newFocus)
        }
        if newSelection != selection {
            selection = newSelection
            change.insert(.selection)
        }
        return change
    }

    /// Moves the selection onto the row that stands for it, as after a collapse.
    private mutating func moveSelectionToItsRow(in tree: LayerTree) -> Change {
        guard let selected = selection else { return [] }
        let standIn = expansion.standIn(for: selected, in: tree, focus: focus)
        guard standIn != selected else { return [] }
        selection = standIn
        return .selection
    }
}
