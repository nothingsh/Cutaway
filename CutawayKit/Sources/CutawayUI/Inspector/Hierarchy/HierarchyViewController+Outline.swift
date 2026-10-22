import AppKit

// The outline view's data source and delegate: the rows from the store's tree, and what
// the user does in the outline written to the store.
extension HierarchyViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    private func children(of item: Any?) -> [UInt64] {
        guard let item = item as? Item else { return roots }
        let children = tree.children(of: item.id)
        guard let filter else { return children }
        // The outline view asks for each child by its index: filtering the children for each
        // would take a node's k children k times.
        if let shown = shownChildren[item.id] { return shown }
        let shown = children.filter(filter.shown.contains)
        shownChildren[item.id] = shown
        return shown
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        self.item(for: children(of: item)[index])
    }

    /// Typing a title's first letters selects its row.
    func outlineView(
        _ outlineView: NSOutlineView, typeSelectStringFor tableColumn: NSTableColumn?, item: Any
    ) -> String? {
        (item as? Item).map { tree.displayTitle(of: $0.id) }
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let view = HierarchyTableRowView()
        view.outline = self.outlineView
        decorate(view, id: layerID(of: item), ancestors: ancestors(of: item), rowDecoration())
        return view
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !children(of: item).isEmpty
    }

    func outlineView(
        _ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any
    ) -> NSView? {
        guard let item = item as? Item else { return nil }
        let view =
            outlineView.makeView(withIdentifier: Self.rowIdentifier, owner: nil)
                as? HierarchyRowView ?? HierarchyRowView()
        view.identifier = Self.rowIdentifier
        view.configure(HierarchyRow(tree, item.id, filter: filter))
        return view
    }

    // MARK: From the outline to the store

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isShowingStore else { return }
        // Rows appeared: the column follows them, with a search too.
        defer { columnSizer.sizeSoon() }
        // With a search, expanding is the list's own business (C-HIER-04).
        guard filter == nil, let item = notification.userInfo?["NSObject"] as? Item
        else { return }
        writingExpansion { store.setExpanded(item.id, true) }
        // The rows that just appeared are as the outline view remembers them, or collapsed.
        // The store says how they should be.
        showingStore {
            applyExpansion(below: tree.children(of: item.id))
        }
        reportVisibleRows()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isShowingStore else { return }
        // Rows went away: the column follows them, with a search too.
        defer { columnSizer.sizeSoon() }
        guard filter == nil, let item = notification.userInfo?["NSObject"] as? Item
        else { return }
        // Collapsing a row collapses every expanded row inside it first, each with its own
        // notification, and the row itself last. Without ⌥ the outline view expands them
        // again with that row, as they were, so the store keeps them expanded: their
        // expansion does not show while the row is collapsed. With ⌥ they stay collapsed and
        // go to the store together with the row. Either way the tree is laid out once, not
        // once for each.
        if let parent = outlineView.parent(forItem: item), !outlineView.isItemExpanded(parent) {
            if outlineView.isCollapsingChildren { collapsedInside.append(item.id) }
            return
        }
        let collapsed = collapsedInside + [item.id]
        collapsedInside.removeAll()
        writingExpansion { store.setExpanded(collapsed, false) }
        // The outline view has dropped a selection that was inside the collapsed row. The
        // store moved it onto the row; show that.
        showSelection(store.selectedLayerID, scroll: true)
        reportVisibleRows()
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isShowingStore else { return }
        // The outline view's selection now, not at the time the notification was posted: it
        // arrives after a collapse has already been dealt with.
        let id = layerID(atRow: outlineView.selectedRow)
        // Collapsing a row of the search drops a selection inside it from the outline. The
        // search's rows are the list's own business: the store keeps its selection.
        if id == nil, filter != nil, let selected = store.selectedLayerID,
           tree.contains(selected), outlineView.row(forItem: item(for: selected)) < 0
        {
            return
        }
        // A row of the search may be inside nodes the store holds collapsed: they are
        // expanded, so that the row clicked is the one selected (C-HIER-04).
        if let id, filter != nil {
            store.reveal(id)
        } else {
            store.select(id)
        }
    }
}
