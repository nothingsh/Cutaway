import AppKit

/// The width of the hierarchy list's one column: as wide as the titles of the rows shown need,
/// however deep they are indented, and at least as wide as the list. When that is wider than
/// the list, the list scrolls sideways; folding the deep rows away stops that, which a width
/// for the whole tree would not.
@MainActor
final class HierarchyColumnSizer {
    private weak var outlineView: NSOutlineView?
    /// The title of the layer a row shows, if the row shows one.
    private let title: @MainActor (Int) -> String?
    /// How wide each title is when shown in full. Class names repeat a lot.
    private var titleWidths: [String: CGFloat] = [:]
    /// The column's width that every title of the rows needs.
    private var titlesWidth: CGFloat = 0

    init(outlineView: NSOutlineView, title: @escaping @MainActor (Int) -> String?) {
        self.outlineView = outlineView
        self.title = title
    }

    /// Makes the column wide enough for the title of every row shown. Measured again whenever
    /// the rows change: a reload, and every expansion and collapse. Titles are measured once
    /// each.
    func sizeToRows() {
        guard let outlineView, outlineView.numberOfRows > 0 else { return }
        // What the outline view puts around the title of a row at level 0; the first row is
        // always at level 0 (a root, or the focus).
        let columnRect = outlineView.rect(ofColumn: 0)
        let cell = outlineView.frameOfCell(atColumn: 0, row: 0)
        let around = (cell.minX - columnRect.minX) + (columnRect.maxX - cell.maxX)

        var widest: CGFloat = 0
        for row in 0..<outlineView.numberOfRows {
            guard let title = title(row) else { continue }
            let indentation = CGFloat(outlineView.level(forRow: row)) * outlineView.indentationPerLevel
            // Titles only: a detail is cut short rather than make the list scroll sideways;
            // the tooltip and the attribute panel's header have it in full (C-HIER-07).
            widest = max(widest, indentation + titleWidth(title))
        }
        titlesWidth = (around + widest).rounded(.up)
        fit()
    }

    /// The column is as wide as the titles need, and at least as wide as the list: what is
    /// left over goes to the rows' details (C-HIER-07), which are cut short rather than make
    /// the list scroll sideways.
    func fit() {
        guard let outlineView, let column = outlineView.tableColumns.first, titlesWidth > 0,
              let clip = outlineView.enclosingScrollView?.contentView
        else { return }
        // What the outline puts around its one column: an inset on either side, and the
        // spacing the column's rectangle has beyond the column itself.
        let rect = outlineView.rect(ofColumn: 0)
        let around = 2 * rect.minX + (rect.width - column.width)
        let width = max(titlesWidth, (clip.bounds.width - around).rounded(.down))
        if column.width != width { column.width = width }
    }

    private func titleWidth(_ title: String) -> CGFloat {
        if let width = titleWidths[title] { return width }
        let width = HierarchyRowView.width(ofTitle: title)
        titleWidths[title] = width
        return width
    }
}
