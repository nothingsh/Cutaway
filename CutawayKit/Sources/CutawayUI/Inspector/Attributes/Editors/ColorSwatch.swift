import AppKit

/// How the panel draws a colour (C-ATTR-22): a small rounded square with a hairline, and for no
/// colour a white one struck through in red, as in the design.
enum SwatchDrawing {
    static func draw(_ color: NSColor?, in bounds: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        if let color, color.alphaComponent > 0 {
            // A colour that is not opaque shows over white, as over a page.
            NSColor.white.setFill()
            path.fill()
            color.setFill()
            path.fill()
        } else {
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: rect.minX, y: rect.minY))
            slash.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
            slash.lineWidth = 1.5
            NSColor.systemRed.setStroke()
            slash.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor.black.withAlphaComponent(0.3).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}

/// A swatch: shows a colour, and when it holds a colour well, a click on it opens the
/// system's colour panel as the well does (C-ATTR-05). The well is there but not drawn: the
/// system draws a well as a round button, the design a small square.
final class ColorSwatch: NSView {
    static let side: CGFloat = 14

    var color: NSColor? {
        didSet { needsDisplay = true }
    }

    init(color: NSColor?, well: NSColorWell? = nil) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        if let well {
            well.alphaValue = 0
            addContent(well)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.side, height: Self.side) }

    override func draw(_ dirtyRect: NSRect) {
        SwatchDrawing.draw(color, in: bounds)
    }
}
