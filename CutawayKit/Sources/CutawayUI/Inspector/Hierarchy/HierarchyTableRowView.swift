import AppKit
import CutawayScene

/// The background of a row of the hierarchy list: the hover fill (C-HIER-15), the guides
/// of the rows it is inside (C-HIER-12), and what the last refresh did to its layer, fading
/// (C-LIVE-05). The selection is the table's own.
final class HierarchyTableRowView: NSTableRowView {
    /// The outline view the row is in, which says where each level's guide goes.
    weak var outline: HierarchyOutlineView?

    var guides: [HierarchyGuide] = [] {
        didSet { if guides != oldValue { needsDisplay = true } }
    }

    var isHovered = false {
        didSet { if isHovered != oldValue { needsDisplay = true } }
    }

    /// How strong a change's tint is just after the refresh.
    static let changeOpacity: CGFloat = 0.22
    /// How wide the strip at the leading edge of a selected row is: the selection's look
    /// stays, and the change shows beside it.
    static let changeStripWidth: CGFloat = 3

    /// What the last refresh did to the row's layer, and which refresh that was; the tint
    /// showing it lies behind the cell.
    private(set) var change: ChangeMark?
    private var changeGeneration: Int?
    private let changeTint = NSView()

    override var isSelected: Bool {
        didSet { if isSelected != oldValue { needsLayout = true } }
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

    /// Marks the row for `change` of the refresh `generation`, `elapsed` seconds into the
    /// marks' `duration`: faded that far and fading on, or with motion reduced, at full
    /// strength until the list takes it away. Nil, or a mark whose time is up, shows nothing.
    /// The same mark again leaves its fade alone.
    func show(
        _ change: ChangeMark?, generation: Int?, elapsed: Double, duration: Double, reducesMotion: Bool
    ) {
        guard change != self.change || generation != changeGeneration else { return }
        self.change = change
        changeGeneration = generation
        guard let change, elapsed < duration else {
            changeTint.isHidden = true
            return
        }
        if changeTint.superview == nil {
            changeTint.wantsLayer = true
            changeTint.layer?.cornerRadius = 5
            addSubview(changeTint, positioned: .below, relativeTo: nil)
        }
        changeTint.isHidden = false
        changeTint.layer?.backgroundColor = Theme.change(change).cgColor
        needsLayout = true
        let start = Self.changeOpacity * (reducesMotion ? 1 : CGFloat(1 - elapsed / duration))
        changeTint.alphaValue = start
        guard !reducesMotion else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration - elapsed
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            changeTint.animator().alphaValue = 0
        }
    }

    override func layout() {
        super.layout()
        let rect = Self.hoverRect(in: bounds)
        changeTint.frame = isSelected
            ? NSRect(x: rect.minX, y: rect.minY, width: Self.changeStripWidth, height: rect.height)
            : rect
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if let change { changeTint.layer?.backgroundColor = Theme.change(change).cgColor }
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
