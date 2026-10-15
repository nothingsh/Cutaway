import AppKit

/// Folding the sections, filtering them and the header that stays at the top of the list.
extension AttributesViewController {
    // MARK: - Folding

    func fold(_ key: String, _ isCollapsed: Bool) {
        if isCollapsed { collapsed.insert(key) } else { collapsed.remove(key) }
        updateStickyAfterLayout()
    }

    /// Folds or unfolds every section, as Option and a click on any header do (C-ATTR-15).
    func foldAll(_ isCollapsed: Bool) {
        for section in sectionViews {
            section.setCollapsed(isCollapsed)
            if isCollapsed { collapsed.insert(section.foldKey) } else { collapsed.remove(section.foldKey) }
        }
        updateStickyAfterLayout()
    }

    // MARK: - Filtering (C-ATTR-14)

    @objc func filterChanged(_ sender: NSSearchField) {
        setFilter(sender.stringValue)
    }

    /// Keeps the rows whose titles or IDs hold `text`, from the top of the list.
    func setFilter(_ text: String) {
        if filterField.stringValue != text { filterField.stringValue = text }
        let new = AttributesViewModel.filterText(text)
        guard new != filter else { return }
        filter = new
        applyFilter()
        scrollToTop()
    }

    /// Shows the sections, rows and lines the filter keeps, and the lines between sections
    /// shown one after another.
    func applyFilter() {
        guard isViewLoaded else { return }
        var shown = 0
        var total = 0
        for section in sectionViews {
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
        updateStickyAfterLayout()
    }

    // MARK: - The header at the top (C-ATTR-15)

    func updateStickyAfterLayout() {
        guard isViewLoaded else { return }
        view.layoutSubtreeIfNeeded()
        updateSticky()
    }

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
        return allSections.first { section in
            guard !section.isHidden, !section.isCollapsed,
                  let offsets = offsets(of: section) else { return false }
            return offsets.top < -2 && offsets.bottom > barHeight
        }
    }

    /// Folds the section whose header is at the top, and brings its header back into view.
    @objc func toggleSticky(_ sender: Any?) {
        guard let section = stickySection else { return }
        section.toggle(all: SectionHeader.clickFoldsAll)
        view.layoutSubtreeIfNeeded()
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

/// A section of the attribute panel that folds (C-ATTR-15).
@MainActor
protocol FoldingSection: NSView {
    var title: String { get }
    var icon: SectionHeader.Icon? { get }
    var isCollapsed: Bool { get }
    /// Folds or unfolds it as a click on its header does, every section if `all`.
    func toggle(all: Bool)
    func setCollapsed(_ isCollapsed: Bool)
}

extension AttributeGroupView: FoldingSection {}

extension AttributesViewController: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSSearchField === filterField else { return }
        setFilter(filterField.stringValue)
    }
}
