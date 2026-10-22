import AppKit
import DeclarativeAppKit

/// A part's rows when a layer has very many attributes (C-SCALE-03): its items in
/// pages of `pageSize`, each built when it comes near the list's visible area and taken down
/// again when it is far from it. A page not built is an empty view as tall as it was when it
/// was last built, or as it is thought to be. Which items are listed follows the filter,
/// worked out from the items rather than from rows, most of which are not there.
@MainActor
final class LazyRowsView: NSView {
    /// Small, so that building the next page while scrolling stays well within a frame or so.
    static let pageSize = 20
    /// The space between rows, as in a part that is built at once.
    static let spacing: CGFloat = 2

    @MainActor
    private final class Page {
        let range: Range<Int>
        let holder = VStack(alignment: .fill, spacing: LazyRowsView.spacing) {}
        let height: NSLayoutConstraint
        /// The rows, while the page is built.
        var rows: [any AttributeListRow]?

        init(range: Range<Int>, height: CGFloat) {
            self.range = range
            self.height = holder.heightAnchor.constraint(equalToConstant: height)
            self.height.isActive = true
        }
    }

    /// Every item of the part, as listed.
    private(set) var allItems: [AttributeClusters.Item]
    /// The items the filter keeps, in their order.
    private(set) var items: [AttributeClusters.Item]
    /// Where each of `items` is in `allItems`.
    private var positions: [Int]
    private let make: (AttributeClusters.Item) -> any AttributeListRow
    private let stack = VStack(alignment: .fill, spacing: LazyRowsView.spacing) {}
    private var pages: [Page] = []
    /// What the rows mark in their titles (C-ATTR-14).
    private(set) var highlight: String?
    /// Compound rows made to know what they say, which a filter looks at, by their item's
    /// place in `allItems`: kept while the filter lists their items, and used when their page
    /// is built.
    private var madeForMatching: [Int: any AttributeListRow] = [:]

    init(items: [AttributeClusters.Item], make: @escaping (AttributeClusters.Item) -> any AttributeListRow) {
        allItems = items
        self.items = items
        positions = Array(items.indices)
        self.make = make
        super.init(frame: .zero)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        makePages()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The rows built now, with their items.
    var built: [(item: AttributeClusters.Item, row: any AttributeListRow)] {
        pages.flatMap { page in
            zip(items[page.range], page.rows ?? []).map { (item: $0, row: $1) }
        }
    }

    /// How many attributes the part lists, whatever the filter keeps.
    var attributeCount: Int { allItems.reduce(0) { $0 + Self.attributeCount(of: $1) } }

    /// How many attributes the filter keeps.
    var shownAttributeCount: Int { items.reduce(0) { $0 + Self.attributeCount(of: $1) } }

    static func attributeCount(of item: AttributeClusters.Item) -> Int {
        switch item {
        case .single: 1
        case .cluster(let row): row.attributes.count
        }
    }

    /// The same items with new values (C-ATTR-06): the rows built stay, and are given the
    /// new values with the rest.
    func replaceValues(_ items: [AttributeClusters.Item]) {
        allItems = items
        // Kept by the filter as before: the same shape keeps the same titles and IDs.
        list(kept(for: highlight))
    }

    /// Lists the items `filter` keeps, from no page built; nil keeps them all. Returns the
    /// rows taken down.
    @discardableResult
    func apply(filter: String?) -> [any AttributeListRow] {
        let kept = kept(for: filter)
        let changes = filter != highlight || kept.count != items.count
        highlight = filter
        list(kept)
        guard changes else { return [] }
        let removed = pages.flatMap { $0.rows ?? [] }
        makePages()
        return removed
    }

    /// The places in `allItems` of the items `filter` keeps, in their order.
    private func kept(for filter: String?) -> [Int] {
        guard let filter else { return Array(allItems.indices) }
        let built = builtRows()
        return allItems.indices.filter { matches(allItems[$0], at: $0, filter, built: built) }
    }

    /// The rows of the pages built, by their item's place in `allItems`.
    private func builtRows() -> [Int: any AttributeListRow] {
        var rows: [Int: any AttributeListRow] = [:]
        for page in pages {
            guard let built = page.rows else { continue }
            for (index, row) in zip(page.range, built) { rows[positions[index]] = row }
        }
        return rows
    }

    /// Lists the items at `kept`, and lets go of the rows made for items no longer listed:
    /// nothing would build them.
    private func list(_ kept: [Int]) {
        positions = kept
        items = kept.map { allItems[$0] }
        let listed = Set(kept)
        madeForMatching = madeForMatching.filter { listed.contains($0.key) }
    }

    /// Whether the filter keeps an item, as its row would say (C-ATTR-14): an attribute's
    /// row by its title and ID; a compound row by what it says, which only the row knows: the
    /// one on show if its page is built, or one made to ask.
    private func matches(
        _ item: AttributeClusters.Item, at index: Int, _ filter: String,
        built: [Int: any AttributeListRow]
    ) -> Bool {
        switch item {
        case .single(let attribute):
            return AttributesViewModel
                .match(of: filter, in: AttributeText.title(attribute.title, id: attribute.id)) != nil
                || attribute.id.map { AttributesViewModel.match(of: filter, in: $0) != nil } == true
        case .cluster:
            if let row = built[index] { return row.matches(filter) }
            let row = madeForMatching[index] ?? make(item)
            madeForMatching[index] = row
            return row.matches(filter)
        }
    }

    private func makePages() {
        for page in pages { page.holder.removeFromSuperview() }
        pages = stride(from: 0, to: items.count, by: Self.pageSize).map { start in
            let range = start..<min(start + Self.pageSize, items.count)
            let page = Page(range: range, height: estimatedHeight(of: range))
            stack.addArrangedSubview(page.holder)
            return page
        }
    }

    /// What a page not yet built is thought to need: a line for most rows, two for a rect,
    /// which has its title above, and more for a compound row.
    private func estimatedHeight(of range: Range<Int>) -> CGFloat {
        let rows = items[range].reduce(CGFloat(0)) { total, item in
            switch item {
            case .single(let attribute): total + (attribute.valueKind == .rect ? 52 : 28)
            case .cluster(let row): total + 28 * CGFloat(max(row.attributes.count, 2))
            }
        }
        return rows + Self.spacing * CGFloat(max(range.count - 1, 0))
    }

    /// Builds the pages that reach into `near` and takes down those that are wholly outside
    /// `keep`, both in `document`'s coordinates, unless `isPinned` holds for one of their rows.
    /// Returns the rows built and taken down.
    func arrange(
        near: NSRect, keep: NSRect, in document: NSView, isPinned: (any AttributeListRow) -> Bool
    ) -> (built: [any AttributeListRow], takenDown: [any AttributeListRow]) {
        var built: [any AttributeListRow] = []
        var takenDown: [any AttributeListRow] = []
        for page in pages {
            let frame = page.holder.convert(page.holder.bounds, to: document)
            if page.rows == nil, frame.intersects(near) {
                let rows = page.range.map { index in
                    madeForMatching.removeValue(forKey: positions[index]) ?? make(items[index])
                }
                for row in rows {
                    row.highlight(highlight)
                    page.holder.addArrangedSubview(row)
                }
                page.height.isActive = false
                page.rows = rows
                built += rows
            } else if let rows = page.rows, !frame.intersects(keep), !rows.contains(where: isPinned) {
                // Taken down to the height it has, so that what is below does not move.
                page.height.constant = frame.height
                page.height.isActive = true
                for row in rows { row.removeFromSuperview() }
                page.rows = nil
                takenDown += rows
            }
        }
        return (built, takenDown)
    }

    /// How many pages that reach into `rect` are not built. For tests.
    func pagesNotBuilt(in rect: NSRect, of document: NSView) -> Int {
        pages.filter { page in
            page.rows == nil && page.holder.convert(page.holder.bounds, to: document).intersects(rect)
        }.count
    }

    /// The frame, in `document`'s coordinates, of the first page built that is in `rect`; what
    /// the list keeps in place while pages change around it.
    func anchor(in rect: NSRect, of document: NSView) -> NSView? {
        pages.first { page in
            page.rows != nil && page.holder.convert(page.holder.bounds, to: document).intersects(rect)
        }?.holder
    }
}
