import AppKit

/// The pages of a layer with very many attributes (C-SCALE-03): built as the list comes near
/// them, and taken down again when it is far from them, keeping what is seen where it is.
@MainActor
final class AttributePageArranger {
    /// More items than this, and the parts are built page by page; fewer are built at once.
    static let threshold = 200

    /// Whether `listing` is built page by page.
    static func isBuiltByPage(_ listing: AttributesViewModel.Listing) -> Bool {
        listing.sections.flatMap(\.parts).reduce(0) { $0 + $1.listed.count } > threshold
    }

    private let list: NSScrollView
    /// Every part built page by page, in the order of the list.
    private let parts: @MainActor () -> [LazyRowsView]
    /// Whether a row is not to be taken down: typed in, or being changed.
    private let isPinned: @MainActor (any AttributeListRow) -> Bool
    /// Called once rows were built or taken down, before the list is laid out again.
    private let rowsDidChange: @MainActor () -> Void
    /// Called after the pages arranged on a later turn of the run loop.
    private let didArrangeLater: @MainActor () -> Void
    /// Lays the panel out, as pages change.
    private let layout: @MainActor () -> Void
    /// Set while pages are built and taken down, which scrolls the list.
    private var isArranging = false
    /// Set while the pages are to be arranged on the next turn of the run loop.
    private var isDue = false

    init(
        list: NSScrollView, parts: @escaping @MainActor () -> [LazyRowsView],
        isPinned: @escaping @MainActor (any AttributeListRow) -> Bool,
        rowsDidChange: @escaping @MainActor () -> Void,
        didArrangeLater: @escaping @MainActor () -> Void, layout: @escaping @MainActor () -> Void
    ) {
        self.list = list
        self.parts = parts
        self.isPinned = isPinned
        self.rowsDidChange = rowsDidChange
        self.didArrangeLater = didArrangeLater
        self.layout = layout
    }

    /// Arranges the pages on the next turn of the run loop, once: the list says what it shows
    /// while it is laid out, when laying out again is not allowed. The pages a screen away are
    /// built ahead, so that a turn later is soon enough.
    func arrangeSoon() {
        guard !parts().isEmpty, !isDue, !isArranging else { return }
        isDue = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isDue = false
            self.arrange()
            self.didArrangeLater()
        }
    }

    /// Builds the pages near what the list shows, a screen above and below it, and takes down
    /// those more than three screens away, keeping what is seen where it is. A row being typed
    /// in or changed stays.
    func arrange() {
        let parts = parts()
        // Not while the list is hidden: nothing has its place yet, and every page would seem near.
        guard !parts.isEmpty, !isArranging, !list.isHiddenOrHasHiddenAncestor,
              let document = list.documentView
        else { return }
        isArranging = true
        defer { isArranging = false }
        // Built pages turn out shorter or taller than thought: again, until nothing changes.
        for _ in 0..<6 {
            layout()
            let visible = list.contentView.bounds
            let screen = max(visible.height, 100)
            let near = visible.insetBy(dx: 0, dy: -screen)
            let keep = visible.insetBy(dx: 0, dy: -3 * screen)
            let anchor = parts.lazy.compactMap { $0.anchor(in: visible, of: document) }.first
            let before = anchor.map { top(of: $0, in: document, visible: visible) }
            var built: [any AttributeListRow] = []
            var takenDown = 0
            for lazy in parts where !lazy.isHiddenOrHasHiddenAncestor {
                let change = lazy.arrange(near: near, keep: keep, in: document, isPinned: isPinned)
                built += change.built
                takenDown += change.takenDown.count
            }
            guard !built.isEmpty || takenDown > 0 else { return }
            rowsDidChange()
            layout()
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
}
