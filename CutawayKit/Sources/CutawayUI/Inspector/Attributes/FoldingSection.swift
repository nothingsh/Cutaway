import AppKit

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
