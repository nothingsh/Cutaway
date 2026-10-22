import AppKit
import CutawayModel

// What the list shows besides its rows: the hover (C-HIER-15), the guides (C-HIER-12), the
// sticky ancestors (C-HIER-13), and following the selection sideways (C-HIER-14).
extension HierarchyViewController {
    /// The most ancestors kept at the top.
    static let maxStickyRows = 4

    // MARK: - The pointer

    func configurePointer() {
        outlineView.pointerDidMove = { [weak self] row in
            guard let self else { return }
            pointerIsOver(row >= 0 ? layerID(atRow: row) : nil)
        }
        outlineView.isCovered = { [weak self] point in
            self?.stickyView.layer(at: point) != nil
        }
        stickyView.onHover = { [weak self] id in self?.pointerIsOver(id) }
        stickyView.onClick = { [weak self] id in self?.stickyRowWasClicked(id) }
    }

    /// The layer under the pointer in the list, or none: it is the hovered layer, as in the
    /// preview, and measured with ⌥ held. Not once the connection is gone, as there: the
    /// store takes no hover then, and a list that takes no clicks has no row to measure.
    private func pointerIsOver(_ id: UInt64?) {
        store.hover(id)
        guard outlineView.isEnabled else { return }
        onPointerOverRow?(id != nil)
    }

    // MARK: - Rows

    /// The rows were shown anew, or rows came or went: the guides are measured again, and the
    /// rows in view and the sticky ones follow.
    func rowsDidChange() {
        outlineView.invalidateGuides()
        decorateRows()
        updateSticky()
        outlineView.pointerMayHaveMoved()
    }

    /// The layers a row is inside as the list shows them, outermost first.
    func ancestors(of item: Any?) -> [UInt64] {
        var ids: [UInt64] = []
        var parent = outlineView.parent(forItem: item)
        while let current = parent {
            if let id = layerID(of: current) { ids.append(id) }
            parent = outlineView.parent(forItem: current)
        }
        return ids.reversed()
    }

    /// What every row's hover and guides are drawn from: the layers whose rows the selected
    /// and the hovered rows are inside. Worked out once for all the rows decorated together.
    struct RowDecoration {
        let hover: UInt64?
        let selectedParent: UInt64?
        let hoveredParent: UInt64?
    }

    /// The decoration of the rows as the store holds the selection and the hover.
    func rowDecoration() -> RowDecoration {
        let hover = store.hoveredLayerID
        return RowDecoration(
            hover: hover, selectedParent: shownParent(of: store.selectedLayerID),
            hoveredParent: shownParent(of: hover))
    }

    /// The hover and the guides of the rows there are views for.
    func decorateRows() {
        let decoration = rowDecoration()
        outlineView.enumerateAvailableRowViews { [self] view, row in
            guard let view = view as? HierarchyTableRowView else { return }
            let item = outlineView.item(atRow: row)
            decorate(view, id: layerID(of: item), ancestors: ancestors(of: item), decoration)
        }
        updateSticky()
    }

    func decorate(
        _ view: HierarchyTableRowView, id: UInt64?, ancestors: [UInt64], _ decoration: RowDecoration
    ) {
        view.isHovered = id != nil && id == decoration.hover
        view.guides = HierarchyGuide.guides(
            ancestors: ancestors, selectedParent: decoration.selectedParent,
            hoveredParent: decoration.hoveredParent)
    }

    /// The row a layer's row is inside in the list, if the layer has a row.
    private func shownParent(of id: UInt64?) -> UInt64? {
        guard let id else { return nil }
        let row = row(of: id)
        guard row >= 0 else { return nil }
        return layerID(of: outlineView.parent(forItem: outlineView.item(atRow: row)))
    }

    // MARK: - Sticky ancestors

    /// The height of a row with the space between rows.
    private var rowPitch: CGFloat {
        outlineView.rowHeight + outlineView.intercellSpacing.height
    }

    /// Keeps the ancestors of the rows at the top in view: the most rows, up to four, such
    /// that the row just below them has at least that many ancestors, which are its nearest.
    func updateSticky() {
        let visible = outlineView.visibleRect
        var shown: [UInt64] = []
        var more = 0
        if visible.minY > 0 {
            for count in stride(from: Self.maxStickyRows, through: 1, by: -1) {
                let below = outlineView.row(at: NSPoint(
                    x: visible.minX, y: visible.minY + CGFloat(count) * rowPitch + 0.5))
                guard below >= 0 else { continue }
                let ancestors = ancestors(of: outlineView.item(atRow: below))
                guard ancestors.count >= count else { continue }
                shown = Array(ancestors.suffix(count))
                more = ancestors.count - count
                break
            }
        }
        let scrollX = visible.minX
        let selected = store.selectedLayerID
        let hovered = store.hoveredLayerID
        let rows = shown.compactMap { id -> HierarchyStickyView.Row? in
            let row = row(of: id)
            guard row >= 0 else { return nil }
            let cell = outlineView.frameOfCell(atColumn: 0, row: row)
            return HierarchyStickyView.Row(
                id: id, row: HierarchyRow(tree, id, filter: store.filter),
                triangleX: outlineView.guideX(level: outlineView.level(forRow: row)).map { $0 - scrollX },
                cellX: cell.minX - scrollX, cellWidth: cell.width,
                isSelected: id == selected, isHovered: id == hovered)
        }
        stickyView.show(rows, more: more, rowHeight: rowPitch)
    }

    /// A sticky row was clicked: its layer is selected, and the list scrolls to put its row
    /// just below its own sticky ancestors. A sticky row is a row of the list: it takes no
    /// clicks while the list takes none.
    func stickyRowWasClicked(_ id: UInt64) {
        guard outlineView.isEnabled else { return }
        store.select(id)
        let row = row(of: id)
        guard row >= 0 else { return }
        let above = min(Self.maxStickyRows, outlineView.level(forRow: row))
        let y = max(0, outlineView.rect(ofRow: row).minY - CGFloat(above) * rowPitch)
        scroll(to: NSPoint(x: outlineView.visibleRect.minX, y: y))
    }

    // MARK: - Following the selection sideways

    /// After the selection changed: when the start of its row is out of view sideways, the
    /// list scrolls sideways to leave two levels of indentation before its icon.
    func followSideways(_ id: UInt64?) {
        guard let id else { return }
        let row = row(of: id)
        guard row >= 0 else { return }
        let cell = outlineView.frameOfCell(atColumn: 0, row: row)
        let visible = outlineView.visibleRect
        // The icon and the first letters of the title.
        let start = cell.minX
        let end = start + 16 + 6 + 40
        guard start < visible.minX || end > visible.maxX else { return }
        let x = max(0, start - 2 * outlineView.indentationPerLevel - 10)
        let widest = max(0, outlineView.bounds.width - visible.width)
        scroll(to: NSPoint(x: min(x, widest), y: visible.minY))
    }

    private func scroll(to point: NSPoint) {
        guard let scrollView = outlineView.enclosingScrollView else { return }
        scrollView.contentView.scroll(to: point)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
