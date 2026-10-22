import AppKit
import CutawayWire

/// A layer with very many attributes (C-SCALE-03): its parts are built page by page
/// as the list comes near them, and taken down again when it is far from them. Only the rows
/// built are in `attributeRows`, `attributeCells` and `compoundRows`.
extension AttributesViewController {
    /// More items than this, and the parts are built page by page; fewer are built at once,
    /// as before.
    static let lazyThreshold = 200

    /// Whether `listing` is built page by page.
    static func isBuiltByPage(_ listing: AttributesViewModel.Listing) -> Bool {
        listing.sections.flatMap(\.parts).reduce(0) { $0 + $1.listed.count } > lazyThreshold
    }

    /// A part whose rows are built page by page.
    func pagedPart(_ items: [AttributeClusters.Item], heading: String?) -> AttributeGroupView.Part {
        let lazy = LazyRowsView(items: items) { [weak self] item in
            self?.makeListRow(item) ?? AttributeRowView(title: "", value: nil)
        }
        return AttributeGroupView.Part(heading: heading, rows: [], lazy: lazy)
    }

    /// Every part built page by page, in the order of the list.
    var lazyParts: [LazyRowsView] { sectionViews.flatMap(\.lazyParts) }

    /// The attributes an item's cells show, in the order of its cells.
    private static func attributes(of item: AttributeClusters.Item) -> [Attribute] {
        switch item {
        case .single(let attribute): [attribute]
        case .cluster(let row): row.order.compactMap { row[$0] }
        }
    }

    /// The rows the panel keeps, from the pages built now.
    func listBuiltRows() {
        let built = lazyParts.flatMap(\.built)
        attributeRows = built.compactMap { item, row in
            guard case .single(let attribute) = item, let row = row as? AttributeRowView else { return nil }
            return (attribute, row)
        }
        attributeCells = built.flatMap { item, row -> [(attribute: Attribute, cell: any AttributeCell)] in
            switch row {
            case let compound as CompoundRowView:
                zip(Self.attributes(of: item), compound.cells.map(\.cell)).map { (attribute: $0, cell: $1) }
            case let single as AttributeRowView:
                Self.attributes(of: item).map { (attribute: $0, cell: single) }
            default: []
            }
        }
        compoundRows = built.compactMap { $0.row as? CompoundRowView }
    }

    /// New values for the same attributes (C-ATTR-06): the pages keep their rows, which take
    /// the new values with the rest.
    func replaceValues(_ listing: AttributesViewModel.Listing) {
        let parts = AttributesViewModel.Listing.Kind.allCases.flatMap { listing.section($0)?.parts ?? [] }
        for (lazy, part) in zip(lazyParts, parts) { lazy.replaceValues(part.listed) }
        listBuiltRows()
    }

    /// Arranges the pages on the next turn of the run loop, once: the list says what it shows
    /// while it is laid out, when laying out again is not allowed. The pages a screen away are
    /// built ahead, so that a turn later is soon enough.
    func arrangePagesSoon() {
        guard !lazyParts.isEmpty, !isPageArrangementDue, !isArrangingPages else { return }
        isPageArrangementDue = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isPageArrangementDue = false
            self.arrangePages()
            self.updateSticky()
        }
    }

    /// Builds the pages near what the list shows, a screen above and below it, and takes down
    /// those more than three screens away, keeping what is seen where it is. A row being typed
    /// in or changed stays.
    func arrangePages() {
        // Not while the list is hidden: nothing has its place yet, and every page would seem near.
        guard !lazyParts.isEmpty, !isArrangingPages, !list.isHiddenOrHasHiddenAncestor,
              let document = list.documentView
        else { return }
        isArrangingPages = true
        defer { isArrangingPages = false }
        // Built pages turn out shorter or taller than thought: again, until nothing changes.
        for _ in 0..<6 {
            view.layoutSubtreeIfNeeded()
            let visible = list.contentView.bounds
            let screen = max(visible.height, 100)
            let near = visible.insetBy(dx: 0, dy: -screen)
            let keep = visible.insetBy(dx: 0, dy: -3 * screen)
            let anchor = lazyParts.lazy.compactMap { $0.anchor(in: visible, of: document) }.first
            let before = anchor.map { top(of: $0, in: document, visible: visible) }
            var built: [any AttributeListRow] = []
            var takenDown = 0
            for lazy in lazyParts where !lazy.isHiddenOrHasHiddenAncestor {
                let change = lazy.arrange(near: near, keep: keep, in: document, isPinned: isPinned)
                built += change.built
                takenDown += change.takenDown.count
            }
            guard !built.isEmpty || takenDown > 0 else { return }
            listBuiltRows()
            showRowStates()
            view.layoutSubtreeIfNeeded()
            // What was seen stays where it was, whatever changed above it.
            if let anchor, let before, anchor.superview != nil {
                let delta = top(of: anchor, in: document, visible: list.contentView.bounds) - before
                if abs(delta) > 0.5 { scroll(by: delta, document: document) }
            }
        }
    }

    /// How far below the top of what the list shows a view's top is.
    private func top(of view: NSView, in document: NSView, visible: NSRect) -> CGFloat {
        let frame = view.convert(view.bounds, to: document)
        return document.isFlipped ? frame.minY - visible.minY : visible.maxY - frame.maxY
    }

    private func scroll(by delta: CGFloat, document: NSView) {
        var origin = list.contentView.bounds.origin
        origin.y += document.isFlipped ? delta : -delta
        list.contentView.scroll(to: list.contentView.constrainBoundsRect(
            NSRect(origin: origin, size: list.contentView.bounds.size)).origin)
        list.reflectScrolledClipView(list.contentView)
    }

    /// A row that is typed in, or whose change is on its way or failed, is not taken down.
    private func isPinned(_ row: any AttributeListRow) -> Bool {
        if let responder = view.window?.firstResponder as? NSView, responder.isDescendant(of: row) {
            return true
        }
        let attributes: [Attribute] = switch row {
        case let compound as CompoundRowView: compound.row.attributes
        case let single as AttributeRowView:
            attributeRows.first { $0.row === single }.map { [$0.attribute] } ?? []
        default: []
        }
        return attributes.contains { attribute in
            viewModel.key(of: attribute).flatMap { viewModel.store.edits[$0] } != nil
        }
    }
}
