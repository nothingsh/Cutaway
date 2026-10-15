import AppKit

/// The background of a row of the hierarchy list: the hover fill (C-HIER-15) and the guides
/// of the rows it is inside (C-HIER-12). The selection is the table's own.
final class HierarchyTableRowView: NSTableRowView {
    /// The outline view the row is in, which says where each level's guide goes.
    weak var outline: HierarchyOutlineView?

    var guides: [HierarchyGuide] = [] {
        didSet { if guides != oldValue { needsDisplay = true } }
    }

    var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }

    /// Where the hover fill goes: the shape of the source list's selection.
    static func hoverRect(in bounds: NSRect) -> NSRect {
        bounds.insetBy(dx: 10, dy: 0)
    }

    static func color(_ style: HierarchyGuide.Style) -> NSColor {
        switch style {
        case .plain: .separatorColor
        case .hovered: .tertiaryLabelColor
        case .selected: .controlAccentColor
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if isHovered, !isSelected {
            Theme.hoverFill.setFill()
            NSBezierPath(roundedRect: Self.hoverRect(in: bounds), xRadius: 5, yRadius: 5).fill()
        }
        guard let outline else { return }
        for guide in guides {
            guard let x = outline.guideX(level: guide.level) else { continue }
            Self.color(guide.style).setFill()
            NSRect(x: (x - frame.minX).rounded(.down), y: 0, width: 1, height: bounds.height).fill()
        }
    }
}
