import AppKit
import CutawayWire

/// How the panel draws a colour (C-ATTR-22): a small rounded square with a hairline, and for no
/// colour a white one struck through in red, as in the design. A colour that resolves
/// differently in light and dark is split down the middle, light on the left and dark on the
/// right (C-ATTR-25).
enum SwatchDrawing {
    static func draw(_ color: NSColor?, halves: (light: NSColor, dark: NSColor)? = nil, in bounds: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        if let halves {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            // Each half over white, as a colour that is not opaque shows over a page.
            NSColor.white.setFill()
            path.fill()
            let (left, right) = rect.divided(atDistance: rect.width / 2, from: .minXEdge)
            halves.light.setFill()
            left.fill(using: .sourceOver)
            halves.dark.setFill()
            right.fill(using: .sourceOver)
            NSGraphicsContext.restoreGraphicsState()
        } else if let color, color.alphaComponent > 0 {
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

    /// An sRGB colour as AppKit draws it.
    static func color(_ color: Color) -> NSColor {
        NSColor(
            colorSpace: .extendedSRGB,
            components: [color.red, color.green, color.blue, color.alpha].map { CGFloat($0) }, count: 4)
    }
}

/// A swatch: shows a colour, and when it holds a colour well, a click on it opens the
/// system's colour panel as the well does (C-ATTR-05). The well is there but not drawn: the
/// system draws a well as a round button, the design a small square.
///
/// A dynamic colour shows both appearances, and a short line in the accent colour under the
/// half the value is (C-ATTR-25). The line is inside the view: the square has room above and
/// below it, so that it stays in the middle of its field.
final class ColorSwatch: NSView {
    static let side: CGFloat = 14
    /// Room above and below the square, which the line under a half takes.
    static let underlineRoom: CGFloat = 3
    static let height = side + 2 * underlineRoom

    /// The half of a dynamic colour that the value is.
    enum Half: Equatable {
        case light, dark
    }

    var color: NSColor? {
        didSet { needsDisplay = true }
    }

    /// The colour in light and dark, or nil for a colour the same in both.
    private(set) var appearanceColors: AppearanceColors?
    /// The half the value is, or nil when it is neither or the colour is the same in both.
    private(set) var underlined: Half?

    init(color: NSColor?, well: NSColorWell? = nil) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.height))
        if let well {
            well.alphaValue = 0
            addContent(well)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.side, height: Self.height) }

    /// Shows a colour's two appearances, and underlines the one `value` is: the same when each
    /// component is rounded to 8 bits, as P-ATTR-17 compares them. Nil shows one colour.
    func show(_ appearance: AppearanceColors?, value: Color?) {
        appearanceColors = appearance
        underlined = appearance.flatMap { appearance in
            guard let value else { return nil }
            if Self.sameIn8Bits(value, appearance.light) { return .light }
            if Self.sameIn8Bits(value, appearance.dark) { return .dark }
            return nil
        }
        needsDisplay = true
    }

    static func sameIn8Bits(_ a: Color, _ b: Color) -> Bool {
        func byte(_ component: Float) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return [a.red, a.green, a.blue, a.alpha].map(byte) == [b.red, b.green, b.blue, b.alpha].map(byte)
    }

    /// Where the square is.
    var square: NSRect {
        NSRect(x: 0, y: (bounds.height - Self.side) / 2, width: Self.side, height: Self.side)
    }

    override func draw(_ dirtyRect: NSRect) {
        let halves = appearanceColors.map { (light: SwatchDrawing.color($0.light), dark: SwatchDrawing.color($0.dark)) }
        let square = square
        SwatchDrawing.draw(color, halves: halves, in: square)
        guard let underlined else { return }
        let width = square.width / 2
        let x = underlined == .light ? square.minX : square.midX
        // Under the square, whichever way the view is drawn.
        let y = isFlipped ? square.maxY + 1 : square.minY - 3
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: x + 0.5, y: y, width: width - 1, height: 2), xRadius: 1, yRadius: 1)
            .fill()
    }
}
