import AppKit

// `sizeColumnToRows()`, `fitColumn()` and `sizeColumnSoon()` are internal only so that
// HierarchyViewController.swift can call them.
extension HierarchyViewController {
    // MARK: - The column's width

    /// Makes the column wide enough for the title of every row shown, however deep it is
    /// indented. When that is wider than the list, the list scrolls sideways; folding the deep
    /// rows away stops that, which a width for the whole tree would not. Measured again whenever
    /// the rows change: a reload, and every expansion and collapse. Titles are measured once each.
    func sizeColumnToRows() {
        isColumnSizingPending = false
        guard outlineView.numberOfRows > 0 else {
            rowsDidChange()
            return
        }
        // What the outline view puts around the title of a row at level 0; the first row is
        // always at level 0 (a root, or the focus).
        let columnRect = outlineView.rect(ofColumn: 0)
        let cell = outlineView.frameOfCell(atColumn: 0, row: 0)
        let around = (cell.minX - columnRect.minX) + (columnRect.maxX - cell.maxX)

        var widest: CGFloat = 0
        for row in 0..<outlineView.numberOfRows {
            guard let id = layerID(atRow: row) else { continue }
            let indentation = CGFloat(outlineView.level(forRow: row)) * outlineView.indentationPerLevel
            // Titles only: a detail is cut short rather than make the list scroll sideways;
            // the tooltip and the attribute panel's header have it in full (C-HIER-07).
            widest = max(widest, indentation + titleWidth(tree.displayTitle(of: id)))
        }
        titlesWidth = (around + widest).rounded(.up)
        fitColumn()
        rowsDidChange()
    }

    /// The column is as wide as the titles need, and at least as wide as the list: what is
    /// left over goes to the rows' details (C-HIER-07), which are cut short rather than make
    /// the list scroll sideways.
    func fitColumn() {
        guard let column = outlineView.tableColumns.first, titlesWidth > 0,
              let clip = outlineView.enclosingScrollView?.contentView
        else { return }
        // What the outline puts around its one column: an inset on either side, and the
        // spacing the column's rectangle has beyond the column itself.
        let rect = outlineView.rect(ofColumn: 0)
        let around = 2 * rect.minX + (rect.width - column.width)
        let width = max(titlesWidth, (clip.bounds.width - around).rounded(.down))
        if column.width != width { column.width = width }
    }

    /// Sizes the column once the expansion the user made is over: folding a row away
    /// notifies once for every expanded row inside it, and a scan of the rows for each would
    /// make a large collapse slow.
    func sizeColumnSoon() {
        guard !isColumnSizingPending else { return }
        isColumnSizingPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isColumnSizingPending else { return }
            self.sizeColumnToRows()
        }
    }

    private func titleWidth(_ title: String) -> CGFloat {
        if let width = titleWidths[title] { return width }
        let width = HierarchyRowView.width(ofTitle: title)
        titleWidths[title] = width
        return width
    }
}
