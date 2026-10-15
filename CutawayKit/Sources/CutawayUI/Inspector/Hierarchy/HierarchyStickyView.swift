import AppKit
import CutawayModel

/// The ancestors of the rows at the top of the list, kept at the top while the list scrolls
/// (C-HIER-13). Laid over the list; each row stands where the list has it sideways, so they
/// scroll sideways with it.
final class HierarchyStickyView: NSView {
    static let identifier = "hierarchy.sticky"
    static let moreIdentifier = "hierarchy.sticky.more"

    /// One row as shown: its layer, what it says, and where its triangle and its cell go,
    /// in the sticky view's coordinates.
    struct Row: Equatable {
        var id: UInt64
        var row: HierarchyRow
        var triangleX: CGFloat?
        var cellX: CGFloat
        var cellWidth: CGFloat
        var isSelected: Bool
        var isHovered: Bool
    }

    private(set) var rows: [Row] = []
    /// How many ancestors are above the first row and not shown.
    private(set) var moreAbove = 0
    private var rowHeight: CGFloat = 24

    var onClick: ((UInt64) -> Void)?
    /// The layer under the pointer, or nil when it left.
    var onHover: ((UInt64?) -> Void)?

    private let background = NSVisualEffectView().configure {
        $0.material = .sidebar
        $0.blendingMode = .behindWindow
        $0.state = .followsWindowActiveState
    }

    private let separator = NSBox().configure { $0.boxType = .separator }
    private let moreLabel = NSTextField(labelWithString: "").configure {
        $0.font = Theme.Font.caption
        $0.textColor = .tertiaryLabelColor
        $0.setAccessibilityIdentifier(HierarchyStickyView.moreIdentifier)
    }

    private var rowViews: [StickyRowView] = []
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityIdentifier(Self.identifier)
        addSubview(background)
        addSubview(separator)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    /// The height the rows take; 0 when there are none.
    var height: CGFloat { rows.isEmpty ? 0 : CGFloat(rows.count) * rowHeight + 1 }

    /// Shows these rows, `more` ancestors above them hidden.
    func show(_ rows: [Row], more: Int, rowHeight: CGFloat) {
        let changed = rows.map(\.id) != self.rows.map(\.id) || rowHeight != self.rowHeight
        self.rows = rows
        moreAbove = rows.isEmpty ? 0 : more
        self.rowHeight = rowHeight
        isHidden = rows.isEmpty
        while rowViews.count < rows.count {
            let view = StickyRowView()
            view.onClick = { [weak self] id in self?.onClick?(id) }
            rowViews.append(view)
            addSubview(view, positioned: .below, relativeTo: separator)
        }
        for (index, view) in rowViews.enumerated() {
            view.isHidden = index >= rows.count
            if index < rows.count { view.show(rows[index]) }
        }
        // A count, so it follows the region (C-LOC-02).
        moreLabel.stringValue = "\u{22EF}" + moreAbove.formatted(.number)
        if moreAbove > 0, moreLabel.superview == nil { addSubview(moreLabel) }
        moreLabel.isHidden = moreAbove == 0
        if changed { superview?.needsLayout = true }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        background.frame = bounds
        for (index, view) in rowViews.enumerated() where index < rows.count {
            view.frame = NSRect(x: 0, y: CGFloat(index) * rowHeight, width: bounds.width, height: rowHeight)
        }
        separator.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        moreLabel.sizeToFit()
        moreLabel.frame.origin = NSPoint(x: 4, y: (rowHeight - moreLabel.frame.height) / 2)
    }

    // MARK: - The pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { pointerMoved(to: event.locationInWindow) }
    override func mouseMoved(with event: NSEvent) { pointerMoved(to: event.locationInWindow) }
    override func mouseExited(with event: NSEvent) { onHover?(nil) }

    /// The layer of the row at a point in the window, if any.
    func layer(at point: NSPoint) -> UInt64? {
        let local = convert(point, from: nil)
        guard !isHidden, bounds.contains(local) else { return nil }
        let index = Int(local.y / rowHeight)
        return rows.indices.contains(index) ? rows[index].id : nil
    }

    private func pointerMoved(to point: NSPoint) {
        onHover?(layer(at: point))
    }
}

/// One sticky row: the hover or selection fill, the open triangle, and the row's own view.
private final class StickyRowView: NSView {
    var onClick: ((UInt64) -> Void)?
    private var id: UInt64 = 0
    private var isSelected = false
    private var isHovered = false
    private let triangle = NSImageView().configure {
        $0.image = Theme.symbol(Theme.Symbol.stickyRowOpen, size: 9, weight: .semibold)
        $0.contentTintColor = .tertiaryLabelColor
    }

    private let cell = HierarchyRowView()
    private var triangleX: CGFloat?
    private var cellX: CGFloat = 0
    private var cellWidth: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(triangle)
        // The row's view joins once it has a size (`layout()`): laid out at 0 × 0, its icon and
        // gaps cannot fit, and Auto Layout logs a conflict for each sticky row (reported by
        // the user).
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ row: HierarchyStickyView.Row) {
        id = row.id
        cell.configure(row.row)
        isSelected = row.isSelected
        isHovered = row.isHovered
        cell.backgroundStyle = isSelected ? .emphasized : .normal
        triangle.contentTintColor = isSelected ? .alternateSelectedControlTextColor : .tertiaryLabelColor
        triangleX = row.triangleX
        cellX = row.cellX
        cellWidth = row.cellWidth
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        triangle.isHidden = triangleX == nil
        if let triangleX {
            triangle.frame = NSRect(x: triangleX - 6, y: 0, width: 12, height: bounds.height)
        }
        let frame = NSRect(x: cellX, y: 0, width: cellWidth, height: bounds.height)
        guard frame.width >= 1, frame.height >= 1 else {
            cell.removeFromSuperview()
            return
        }
        cell.frame = frame
        if cell.superview == nil { addSubview(cell) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isSelected || isHovered else { return }
        (isSelected ? NSColor.controlAccentColor : .quaternaryLabelColor).setFill()
        NSBezierPath(
            roundedRect: HierarchyTableRowView.hoverRect(in: bounds), xRadius: 5, yRadius: 5
        ).fill()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(id)
    }
}

/// The list's scroll view with the sticky rows laid over the top of what it shows.
final class HierarchyListView: NSView {
    let scrollView: NSScrollView
    let stickyView: HierarchyStickyView

    init(scrollView: NSScrollView, stickyView: HierarchyStickyView) {
        self.scrollView = scrollView
        self.stickyView = stickyView
        super.init(frame: .zero)
        addSubview(scrollView)
        addSubview(stickyView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        // Over the clip view's top, as wide as it: the scroller stays uncovered.
        let clip = convert(scrollView.contentView.frame, from: scrollView)
        let height = stickyView.height
        stickyView.frame = NSRect(
            x: clip.minX, y: isFlipped ? clip.minY : clip.maxY - height, width: clip.width, height: height)
    }
}
