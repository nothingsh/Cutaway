import AppKit

/// A thin bar that fills from the left with the share of the work done (C-DET-02). It is
/// drawn, not animated: a new round starts it empty at once, where the system's bar ran back
/// from full and read as a countdown.
final class ProgressBarView: NSView {
    static let size = NSSize(width: 72, height: 4)

    /// From 0 to 1; anything else is brought into that range, and NaN counts as 0.
    var fraction: Double = 0 {
        didSet {
            let clamped = fraction.isNaN ? 0 : min(max(fraction, 0), 1)
            if clamped != fraction { fraction = clamped }
            if fraction != oldValue {
                needsDisplay = true
                setAccessibilityValue(fraction)
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel(localized("preview.screenshots"))
        setAccessibilityValue(0.0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize { Self.size }

    /// The part of the bar that is filled.
    var fillRect: NSRect {
        NSRect(
            x: bounds.minX, y: bounds.minY, width: bounds.width * fraction,
            height: bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.labelColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let fill = fillRect
        guard fill.width > 0 else { return }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(
            roundedRect: fill, xRadius: min(radius, fill.width / 2), yRadius: radius
        ).fill()
    }
}
