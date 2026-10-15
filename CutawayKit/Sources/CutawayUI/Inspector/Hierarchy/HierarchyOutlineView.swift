import AppKit

/// The hierarchy's outline view. Tells whether the collapse under way collapses every row
/// inside too, as ⌥ does, which its notifications do not tell; reports the row under the
/// pointer (C-HIER-15); and says where the guides of each level go (C-HIER-12).
final class HierarchyOutlineView: NSOutlineView {
    private(set) var isCollapsingChildren = false
    /// Called with the row under the pointer, or -1 when there is none, whenever that may have
    /// changed.
    var pointerDidMove: ((Int) -> Void)?
    /// Whether a point in the window is under something laid over the list, which reports the
    /// pointer there itself: the sticky rows (C-HIER-13).
    var isCovered: (NSPoint) -> Bool = { _ in false }
    private(set) var isPointerInside = false
    private var trackingArea: NSTrackingArea?
    /// The x of the guide of level 0, once measured; nil inside when no row could tell.
    private var levelZeroGuideX: CGFloat??

    override func collapseItem(_ item: Any?, collapseChildren: Bool) {
        let wasCollapsingChildren = isCollapsingChildren
        isCollapsingChildren = collapseChildren
        super.collapseItem(item, collapseChildren: collapseChildren)
        isCollapsingChildren = wasCollapsingChildren
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

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isPointerInside = true
        pointerMoved(to: event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        isPointerInside = true
        pointerMoved(to: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isPointerInside = false
        pointerDidMove?(-1)
    }

    /// The rows moved under a pointer that stayed: after scrolling or a change of the rows.
    func pointerMayHaveMoved() {
        guard isPointerInside, let window else { return }
        pointerMoved(to: window.mouseLocationOutsideOfEventStream)
    }

    /// The pointer is at a point in the window.
    func pointerMoved(to point: NSPoint) {
        guard !isCovered(point) else { return }
        let local = convert(point, from: nil)
        pointerDidMove?(visibleRect.contains(local) ? row(at: local) : -1)
    }

    // MARK: - Guides

    /// Where the guide of a level goes, in the outline view's coordinates: the middle of the
    /// disclosure triangles of the rows at that level. Nil while no row has a triangle.
    func guideX(level: Int) -> CGFloat? {
        if levelZeroGuideX == nil { levelZeroGuideX = measureLevelZeroGuide() }
        return levelZeroGuideX?.map { $0 + CGFloat(level) * indentationPerLevel }
    }

    /// The rows changed: the guides are measured again when next asked for.
    func invalidateGuides() {
        levelZeroGuideX = nil
    }

    private func measureLevelZeroGuide() -> CGFloat? {
        for row in 0..<numberOfRows {
            guard let item = item(atRow: row), isExpandable(item) else { continue }
            let triangle = frameOfOutlineCell(atRow: row)
            guard triangle.width > 0 else { continue }
            return triangle.midX - CGFloat(level(forRow: row)) * indentationPerLevel
        }
        return nil
    }
}
