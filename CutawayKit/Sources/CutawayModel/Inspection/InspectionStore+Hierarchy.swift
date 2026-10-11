// `fitCamerasToTheFocus()` is internal only so that the other InspectionStore files can call
// it. What changes is worked out by `HierarchyViewState`; each function here publishes it in
// the order its interface needs.
extension InspectionStore {
    // MARK: - Expansion, focus, search and selection

    /// False for a layer that is not in the tree.
    public func isExpanded(_ id: UInt64) -> Bool {
        expansion.isExpanded(id)
    }

    /// Every expanded node of the tree. Package for tests.
    package var expandedLayerIDs: Set<UInt64> {
        expansion.expandedIDs
    }

    /// Does nothing for a layer that is not in the tree.
    public func setExpanded(_ id: UInt64, _ expanded: Bool) {
        setExpanded([id], expanded)
    }

    /// Expands or collapses several layers and lays the tree out once: collapsing a row in the
    /// list collapses every expanded row inside it too. Layers that are not in
    /// the tree are ignored.
    public func setExpanded(_ ids: [UInt64], _ expanded: Bool) {
        let (change, state) = transition { $0.setExpanded(ids, expanded, in: tree) }
        guard change.contains(.expansion) else { return }
        announceExpansion()
        setSelection(state.selection)
        rebuildLayout()
        fetchNext()
    }

    /// Searches the list for the text (C-HIER-04).
    public func setSearchText(_ text: String) {
        guard publishSearchText(text) else { return }
        if refilter() { announceRows() }
    }

    /// Focuses on a layer, or on the whole tree for nil (C-HIER-05). Does nothing for a layer
    /// that is not in the tree. The layer's ancestors are expanded first, so that what is
    /// selected inside the focus is still a row of the list once the focus ends.
    public func focus(on id: UInt64?) {
        let (change, state) = transition { $0.focus(on: id, in: tree) }
        guard change.contains(.focus) else { return }
        publishFocus(state.focus)
        // Built before the expansion is announced: whoever follows it finds the new needs.
        layOut(tree)
        if change.contains(.expansion) { announceExpansion() }
        setSelection(state.selection)
        publishHover(state.hover)
        refilter()
        swapTextures()
        // After the layout: whoever follows the camera projects the new part of the tree.
        fitCamerasToTheFocus()
        announceRows()
        fetchNext()
    }

    /// The new part of the tree fills the view; how it is turned stays.
    func fitCamerasToTheFocus() {
        let fitted = PreviewCameras.fitted(cameras)
        if fitted != cameras { cameras = fitted }
    }

    /// How deep the deepest layer of the focus, or of the whole tree, is: the levels
    /// `expand(toDepth:)` can tell apart go from 1 to this (C-HIER-06).
    public var expandableDepth: Int {
        tree.layers(within: focusedLayerID).map(\.depth).max() ?? 0
    }

    /// Expands the layers of the focus, or of the whole tree, that are less than `n` deep, and
    /// collapses the rest (C-HIER-06). Depths count from the root of the focus, or from the
    /// windows' root layers. Publishes once, and nothing when nothing changed.
    public func expand(toDepth n: Int) {
        let (change, state) = transition { $0.expand(toDepth: n, in: tree) }
        guard change.contains(.expansion) else { return }
        // Built before the expansion is announced: whoever follows it finds the new needs.
        layOut(tree)
        announceExpansion()
        setSelection(state.selection)
        swapTextures()
        fetchNext()
    }

    public func expandAll() {
        expand(toDepth: .max)
    }

    public func collapseAll() {
        expand(toDepth: 0)
    }

    /// Selects a layer from the search's list, whose rows are all expanded whatever the
    /// store holds: the layer's ancestors are expanded first, so that the selection is the
    /// row that was clicked and not a collapsed node above it (C-HIER-04). Does nothing for a
    /// layer that is not in the tree or outside the focus.
    public func reveal(_ id: UInt64) {
        let (change, state) = transition { $0.reveal(id, in: tree) }
        if change.contains(.expansion) {
            // Built before the expansion is announced: whoever follows it finds the new needs.
            layOut(tree)
            announceExpansion()
            swapTextures()
            fetchNext()
        }
        setSelection(state.selection)
    }

    /// Selects the layer at the other end of a constraint (C-LAYOUT-03): leaves the focus when
    /// the layer is outside it, then reveals it, so that the layer itself is selected and not a
    /// collapsed node above it. Does nothing for a layer that is not in the tree.
    public func showConstraintEnd(_ id: UInt64) {
        guard tree.contains(id) else { return }
        if let focus = focusedLayerID, !tree.isWithin(id, root: focus) { self.focus(on: nil) }
        reveal(id)
    }

    /// Selects a layer, or nothing. Does nothing for a layer that is not in the tree, or that
    /// is outside the focus.
    public func select(_ id: UInt64?) {
        let (_, state) = transition { $0.select(id, in: tree) }
        setSelection(state.selection)
    }

    /// Records the layer under the pointer, or none. Does nothing for a layer that is not in
    /// the tree.
    public func hover(_ id: UInt64?) {
        let (_, state) = transition { $0.hover(id, in: tree) }
        publishHover(state.hover)
    }

    /// The user asked again for the selected layer's attributes, by clicking its row once more.
    /// They are asked for again when the last request failed (C-ATTR-01).
    public func retryAttributes() {
        attributes.retry()
    }
}
