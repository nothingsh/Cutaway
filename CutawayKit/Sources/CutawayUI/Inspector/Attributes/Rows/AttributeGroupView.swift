import AppKit
import DeclarativeAppKit

/// One section of the attribute panel (C-ATTR-10, C-ATTR-15): a header that folds it away, and
/// its attributes in parts, one to a group. A part may have a heading with its group's title:
/// one after the first in Content, every one in App (C-ATTR-23). The Object section has the
/// lines that say what the object is before its attributes, and the Layout section the
/// constraints after them (C-LAYOUT-02). A filter keeps
/// the rows whose titles or IDs hold it, all of a part whose heading holds it, or all of them
/// when the section's title does, and opens a folded section while it finds something there
/// (C-ATTR-14).
final class AttributeGroupView: NSView {
    static let headerIdentifier = "attributes.group"
    static let partHeadingIdentifier = "attributes.group.part"

    /// One group's rows, under a heading or not: built at once, or, for a layer with very many
    /// attributes, page by page as the list comes near them (C-SCALE-03).
    struct Part {
        var heading: String?
        var rows: [any AttributeListRow]
        var lazy: LazyRowsView?

        init(heading: String?, rows: [any AttributeListRow], lazy: LazyRowsView? = nil) {
            self.heading = heading
            self.rows = rows
            self.lazy = lazy
        }
    }

    let title: String
    /// The icon before the title (C-ATTR-17).
    var icon: SectionHeader.Icon? {
        didSet { if icon != oldValue { apply() } }
    }

    /// What a folded section says after its title instead of a count: the Object section's
    /// summary (C-ATTR-10).
    var summary: String? {
        didSet { if summary != oldValue { apply() } }
    }

    /// Every row built at once, an attribute's own or a compound one (C-ATTR-19), part after
    /// part.
    let rows: [any AttributeListRow]
    /// The parts built page by page (C-SCALE-03), in order.
    let lazyParts: [LazyRowsView]

    /// How many attributes the rows show, built or not.
    var attributeCount: Int {
        rows.reduce(0) { $0 + $1.attributeCount } + lazyParts.reduce(0) { $0 + $1.attributeCount }
    }

    let parts: [Part]
    /// The lines before the attributes, in the Object section.
    let lines: IdentityLinesView?
    /// The constraints after the attributes, in the Layout section.
    private(set) var constraintsPart: ConstraintsSectionView?
    private let rowStack: VStack
    private let headings: [NSView?]
    private let constraintsSlot: VStack
    /// Folds or unfolds this section, or every section when Option is held.
    var onToggle: (Bool) -> Void = { _ in }
    var onToggleAll: (Bool) -> Void = { _ in }
    /// What the panel remembers the folding by.
    var foldKey = ""

    private(set) var isCollapsed: Bool {
        didSet { apply() }
    }

    /// Whether a filter finds something here: shown open however it is folded.
    private(set) var isOpenedByFilter = false {
        didSet { apply() }
    }

    let header = SectionHeader()

    init(
        title: String, icon: SectionHeader.Icon? = nil, parts: [Part],
        lines: IdentityLinesView? = nil, isCollapsed: Bool
    ) {
        self.title = title
        self.icon = icon
        self.parts = parts
        rows = parts.flatMap(\.rows)
        lazyParts = parts.compactMap(\.lazy)
        self.lines = lines
        self.isCollapsed = isCollapsed
        let headings = parts.map { part in part.heading.map(Self.heading) }
        self.headings = headings
        let constraintsSlot = VStack(alignment: .fill, spacing: 0) {}
        self.constraintsSlot = constraintsSlot
        rowStack = VStack(alignment: .fill, spacing: 2) {
            if let lines { lines }
            for (part, heading) in zip(parts, headings) {
                if let heading { heading }
                part.rows
                if let lazy = part.lazy { lazy }
            }
            constraintsSlot
        }
        super.init(frame: .zero)
        header.target = self
        header.action = #selector(toggle(_:))
        addVStack(alignment: .fill, spacing: 4) {
            VStack(alignment: .fill) {
                header
                    .accessibilityIdentifier(Self.headerIdentifier)
            }
            .padding(top: 0, leading: Theme.Spacing.large, bottom: 0, trailing: Theme.Spacing.medium)
            rowStack
        }
        .padding(top: 8, leading: 0, bottom: 10, trailing: 0)
        apply()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The heading of a part: its group's title.
    private static func heading(_ text: String) -> NSView {
        VStack(alignment: .fill) {
            NSTextField(labelWithString: text)
                .font(.systemFont(ofSize: 10.5, weight: .semibold))
                .textColor(.tertiaryLabelColor)
                .lineBreakMode(.byTruncatingTail)
                .compressionResistancePriority(Theme.textGivesWay, for: .horizontal)
        }
        .padding(top: 8, leading: Theme.Spacing.large, bottom: 2, trailing: Theme.Spacing.large)
        .accessibilityIdentifier(partHeadingIdentifier)
    }

    /// Puts the constraints after the attributes, or takes them away.
    func setConstraints(_ view: ConstraintsSectionView?) {
        guard view !== constraintsPart else { return }
        constraintsPart?.removeFromSuperview()
        constraintsPart = view
        if let view { constraintsSlot.addArrangedSubview(view) }
        apply()
    }

    /// Folds the section, or with Option held every section (C-ATTR-15).
    @objc func toggle(_ sender: Any?) {
        toggle(all: SectionHeader.clickFoldsAll)
    }

    func toggle(all: Bool) {
        // A folded section a filter opened folds again, and stays folded once the filter goes.
        if isOpenedByFilter, isCollapsed, !all {
            isOpenedByFilter = false
            return
        }
        isCollapsed.toggle()
        if all { onToggleAll(isCollapsed) } else { onToggle(isCollapsed) }
    }

    /// Folds or unfolds the section as the panel says.
    func setCollapsed(_ isCollapsed: Bool) {
        guard isCollapsed != self.isCollapsed else { return }
        self.isCollapsed = isCollapsed
    }

    /// Whether the rows show: unfolded, or opened by a filter.
    var showsRows: Bool { !isCollapsed || isOpenedByFilter }

    /// Keeps the rows a filter finds, and says how many attributes are left and whether
    /// anything is (C-ATTR-14). Nil keeps everything. A row stays when its title or its ID
    /// holds the filter; all of a part when its heading does; all of the section when its
    /// title does. The constraints stay only when the section's title or their heading holds
    /// it.
    func apply(filter: String?) -> (attributes: Int, isEmpty: Bool) {
        let keepsAll = filter.map { AttributesViewModel.match(of: $0, in: title) != nil } ?? true
        let sectionFilter = keepsAll ? nil : filter
        var shown = 0
        for (part, heading) in zip(parts, headings) {
            let keepsPart = sectionFilter.flatMap { filter in
                part.heading.map { AttributesViewModel.match(of: filter, in: $0) != nil }
            } ?? false
            let rowFilter = keepsPart ? nil : sectionFilter
            if let lazy = part.lazy {
                // Worked out from the items: most of the rows are not there (C-SCALE-03).
                lazy.apply(filter: rowFilter)
                shown += lazy.shownAttributeCount
                heading?.isHidden = lazy.items.isEmpty
                continue
            }
            for row in part.rows {
                let keeps = rowFilter.map { row.matches($0) } ?? true
                row.isHidden = !keeps
                row.highlight(rowFilter)
                if keeps { shown += row.attributeCount }
            }
            heading?.isHidden = part.rows.allSatisfy(\.isHidden)
        }
        let lineCount = lines?.apply(filter: sectionFilter) ?? 0
        var keepsConstraints = false
        if let constraints = constraintsPart {
            keepsConstraints = sectionFilter.map {
                AttributesViewModel.match(of: $0, in: constraints.title) != nil
            } ?? true
            constraints.isHidden = !keepsConstraints
        }
        let isEmpty = shown == 0 && lineCount == 0 && !keepsConstraints && !keepsAll
        isOpenedByFilter = filter != nil && !isEmpty
        return (shown, isEmpty)
    }

    /// Whether the section has nothing at all to show, whatever the filter.
    var isBlank: Bool {
        rows.isEmpty && lazyParts.allSatisfy(\.allItems.isEmpty) && (lines?.lines.isEmpty ?? true)
            && constraintsPart == nil
    }

    private func apply() {
        rowStack.isHidden = !showsRows
        // A folded section says how many attributes it holds, the Layout section its
        // constraints too, or its summary when it has one.
        let count = attributeCount + (lines?.lines.count ?? 0) + (constraintsPart?.list.count ?? 0)
        let folded = !showsRows
        header.show(
            title: title, count: folded && summary == nil ? count : nil, isCollapsed: folded,
            icon: icon, summary: folded ? summary : nil)
    }
}
