import AppKit
import DeclarativeAppKit

/// What the attribute panel puts around its list: the filter (C-ATTR-14), with the line under
/// the sections that says how many attributes it keeps or that it keeps none; the header of
/// the section scrolled under the top of the list, which stays there (C-ATTR-15); and the
/// pointer, which counts again only once the list is still.
@MainActor
final class AttributesListChrome: NSObject {
    /// How long the list stays still before the pointer counts again.
    static let scrollPause: TimeInterval = 0.15

    private let list: NSScrollView
    /// Every section in the order of the list.
    private let sections: @MainActor () -> [any FoldingSection]
    /// Called once the filter's text changed: the panel applies it, from the top of the list.
    private let filterDidChange: @MainActor () -> Void
    /// What is under the pointer is not pointed at while the list moves under it, and is
    /// pointed at again once the list is still.
    private let pausePointer: @MainActor () -> Void
    private let resumePointer: @MainActor () -> Void
    /// The panel's view, laid out before the list scrolls to a section's header.
    private weak var root: NSView?

    /// The filter: kept while the panel lives, whatever is selected, refreshed or changed; nil
    /// when it keeps everything.
    private(set) var filter: String?
    /// How many attributes the filter keeps of how many, or nil without a filter.
    private(set) var filterCounts: (shown: Int, total: Int)?
    /// The section whose header stays at the top of the list, if any.
    private(set) var stickySection: (any FoldingSection)?
    /// Points again at what is under the pointer, once the list is still.
    private var pointerResume: DispatchWorkItem?

    private(set) lazy var filterField: NSSearchField = FilterSearchField().configure {
        $0.sendsSearchStringImmediately = true
        $0.placeholderString = localized("attributes.filter.placeholder")
        // Each change of the text as it is typed; the action, for Esc and the clear button.
        $0.delegate = self
        $0.target = self
        $0.action = #selector(filterChanged(_:))
    }

    private let countLabel = NSTextField(labelWithString: "")
    private let noMatchLabel = NSTextField(wrappingLabelWithString: "").isSelectable(false)
    private lazy var stickyHeader: SectionHeader = .init().configure {
        $0.target = self
        $0.action = #selector(toggleSticky(_:))
    }

    /// The header that stays at the top, on the same backdrop as the panel
    /// (`AttributesViewController.backdrop()`), so that it is of a piece with the list under
    /// it (reported by the user: the sidebar's material let much more of the desktop through
    /// than the panel does).
    private let stickyBar: NSVisualEffectView = AttributesViewController.backdrop().configure {
        $0.isHidden = true
    }

    init(
        list: NSScrollView, sections: @escaping @MainActor () -> [any FoldingSection],
        filterDidChange: @escaping @MainActor () -> Void,
        pausePointer: @escaping @MainActor () -> Void, resumePointer: @escaping @MainActor () -> Void
    ) {
        self.list = list
        self.sections = sections
        self.filterDidChange = filterDidChange
        self.pausePointer = pausePointer
        self.resumePointer = resumePointer
        super.init()
    }

    // MARK: - Views

    /// The filter as the design draws it: a field 24 points tall with the fields' fill and
    /// hairline and corners of 6 points, the system's search field without its own bezel
    /// inside, so that typing, Esc and the clear button work as before.
    func makeFilterBox() -> NSView {
        let field = filterField
            .compressionResistancePriority(Theme.textGivesWay, for: .horizontal)
            .accessibilityIdentifier(AttributesViewController.filterIdentifier)
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.controlSize = .small
        field.font = .systemFont(ofSize: 12)
        // The design's magnifier is 11 points, in the secondary colour.
        if let search = (field.cell as? NSSearchFieldCell)?.searchButtonCell {
            search.image = Theme.symbol("magnifyingglass", size: 11, weight: .medium)
            search.image?.isTemplate = true
        }
        let box = AttributeEditorView.fieldBox()
        box.cornerRadius = 6
        box.contentView?.addVStack(alignment: .fill) {
            Spacer()
            field
            Spacer()
        }
        .padding(horizontal: 2, vertical: 0)
        return box.frame(height: 24)
    }

    /// What follows the sections while a filter is on: how many attributes it keeps, or that
    /// it keeps none.
    func makeFilterResults() -> NSView {
        VStack(alignment: .fill, spacing: 0) {
            VStack(alignment: .center) {
                noMatchLabel
                    .font(Theme.Font.body)
                    .textColor(.secondaryLabelColor)
                    .alignment(.center)
                    .accessibilityIdentifier(AttributesViewController.noMatchIdentifier)
            }
            .padding(horizontal: Theme.Spacing.large, vertical: 28)
            VStack(alignment: .leading) {
                countLabel
                    .font(Theme.Font.caption)
                    .textColor(.tertiaryLabelColor)
                    .accessibilityIdentifier(AttributesViewController.filterCountIdentifier)
            }
            .padding(top: Theme.Spacing.small, leading: Theme.Spacing.large, bottom: 0,
                     trailing: Theme.Spacing.large)
        }
    }

    /// Puts the bar that holds the header of the section scrolled under the top of the list
    /// over the top of the list, in `root`, the panel's view.
    func installStickyBar(in root: NSView) {
        self.root = root
        stickyBar.addVStack(alignment: .fill, spacing: 0) {
            VStack(alignment: .fill) {
                stickyHeader
                    .accessibilityIdentifier(AttributesViewController.stickyIdentifier)
            }
            .padding(top: 8, leading: Theme.Spacing.large, bottom: 6, trailing: Theme.Spacing.medium)
            NSBox().configure { $0.boxType = .separator }
        }
        stickyBar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stickyBar)
        NSLayoutConstraint.activate([
            stickyBar.topAnchor.constraint(equalTo: list.topAnchor),
            stickyBar.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            stickyBar.trailingAnchor.constraint(equalTo: list.trailingAnchor),
        ])
    }

    // MARK: - Filtering (C-ATTR-14)

    @objc private func filterChanged(_ sender: NSSearchField) {
        setFilter(sender.stringValue)
    }

    /// Keeps the rows whose titles or IDs hold `text`, from the top of the list.
    func setFilter(_ text: String) {
        if filterField.stringValue != text { filterField.stringValue = text }
        let new = AttributesViewModel.filterText(text)
        guard new != filter else { return }
        filter = new
        filterDidChange()
    }

    /// Shows the sections, rows and lines the filter keeps, the lines between sections shown
    /// one after another, and how many attributes it keeps.
    func apply(to sections: [AttributeGroupView], separators: [(line: NSView, section: NSView)]) {
        var shown = 0
        var total = 0
        for section in sections {
            let result = section.apply(filter: filter)
            shown += result.attributes
            total += section.attributeCount
            // The Object section has nothing to say until a layer is selected.
            section.isHidden = result.isEmpty || section.isBlank
        }
        var anyAbove = false
        for (line, section) in separators {
            line.isHidden = section.isHidden || !anyAbove
            if !section.isHidden { anyAbove = true }
        }
        filterCounts = filter == nil ? nil : (shown, total)
        noMatchLabel.stringValue = filter.map { localized("attributes.filter.none", $0) } ?? ""
        noMatchLabel.superview?.isHidden = filter == nil || anyAbove
        countLabel.stringValue = filterCounts.map {
            localized(
                "attributes.filter.count", $0.shown.formatted(.number), $0.total.formatted(.number))
        } ?? ""
        countLabel.superview?.isHidden = filter == nil || !anyAbove
    }

    // MARK: - The pointer

    /// The list moves under the pointer: what passes under it is not pointed at (reported by
    /// the user, 2026-10-20: rows of constraints were filled and their ends marked as they
    /// scrolled by). What is under the pointer is pointed at once the list is still.
    func pauseThePointerWhileScrolling() {
        pausePointer()
        pointerResume?.cancel()
        let resume = DispatchWorkItem { [weak self] in
            self?.pointerResume = nil
            self?.resumePointer()
        }
        pointerResume = resume
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scrollPause, execute: resume)
    }

    // MARK: - The header at the top (C-ATTR-15)

    /// Shows the header of the section whose own header is scrolled above the top of the list
    /// while its rows still show there; none otherwise.
    func updateSticky() {
        stickySection = list.isHidden ? nil : sectionUnderTop()
        stickyBar.isHidden = stickySection == nil
        if let stickySection {
            stickyHeader.show(
                title: stickySection.title, count: nil, isCollapsed: false, icon: stickySection.icon)
        }
    }

    /// How far below the top of the visible list a section's top and bottom are.
    private func offsets(of section: NSView) -> (top: CGFloat, bottom: CGFloat)? {
        guard let document = list.documentView else { return nil }
        let visible = list.contentView.bounds
        let frame = section.convert(section.bounds, to: document)
        return document.isFlipped
            ? (frame.minY - visible.minY, frame.maxY - visible.minY)
            : (visible.maxY - frame.maxY, visible.maxY - frame.minY)
    }

    private func sectionUnderTop() -> (any FoldingSection)? {
        let barHeight = max(stickyBar.fittingSize.height, 28)
        return sections().first { section in
            guard !section.isHidden, !section.isCollapsed,
                  let offsets = offsets(of: section) else { return false }
            return offsets.top < -2 && offsets.bottom > barHeight
        }
    }

    /// Folds the section whose header is at the top, and brings its header back into view.
    @objc private func toggleSticky(_ sender: Any?) {
        guard let section = stickySection else { return }
        section.toggle(all: SectionHeader.clickFoldsAll)
        root?.layoutSubtreeIfNeeded()
        if let document = list.documentView, let offsets = offsets(of: section) {
            var origin = list.contentView.bounds.origin
            origin.y += document.isFlipped ? offsets.top : -offsets.top
            list.contentView.scroll(to: list.contentView.constrainBoundsRect(
                NSRect(origin: origin, size: list.contentView.bounds.size)).origin)
            list.reflectScrolledClipView(list.contentView)
        }
        updateSticky()
    }
}

extension AttributesListChrome: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSSearchField === filterField else { return }
        setFilter(filterField.stringValue)
    }
}
