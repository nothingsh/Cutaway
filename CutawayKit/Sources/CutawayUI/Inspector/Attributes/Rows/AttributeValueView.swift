import AppKit
import CutawayWire
import DeclarativeAppKit

/// A value of an attribute, by its type: a line of text, a group of labelled numbers, a colour
/// swatch, a check mark, a matrix or a tag. A nil value shows a grey "None" and keeps its row.
final class AttributeValueView: NSView {
    static let identifier = "attributes.value"
    static let swatchIdentifier = "attributes.swatch"
    static let fieldIdentifier = "attributes.field"
    /// The most characters of a string the row shows (C-ATTR-09).
    static let longestShownString = 1_000

    let value: AttributeValue?
    /// The value as plain text, as Copy Value copies it (`AttributeText`).
    let plainText: String
    /// The colour the swatch shows, or nil when there is no swatch. For tests.
    private(set) var swatchColor: Color?
    /// How far below the top the first line of text starts, for the title beside it.
    private(set) var firstLineInset: CGFloat = 0

    init(value: AttributeValue?) {
        self.value = value
        plainText = AttributeText.text(of: value)
        super.init(frame: .zero)
        setAccessibilityIdentifier(Self.identifier)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityValue(plainText)
        addContent(makeContent())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func makeContent() -> NSView {
        guard let value else { return Self.text(plainText, color: .tertiaryLabelColor) }
        switch value {
        case .bool(let bool):
            let symbol = NSImageView()
                .image(Theme.symbol(bool ? "checkmark.circle.fill" : "circle", size: 12))
                .contentTintColor(bool ? .systemGreen : .tertiaryLabelColor)
            // The spacer keeps the word beside its mark: the stack is as wide as the column.
            return HStack(alignment: .center, spacing: 5) {
                symbol
                Self.text(
                    bool ? localized("attributes.value.yes") : localized("attributes.value.no"),
                    color: bool ? .labelColor : .secondaryLabelColor)
                Spacer()
            }
        case .integer, .double:
            return Self.text(plainText, digits: true)
        case .string(let string):
            guard !string.isEmpty else {
                // An empty string is not the same as no value.
                return Self.text("\"\"", color: .tertiaryLabelColor)
            }
            // A long text is cut: laying out a megabyte of wrapped text would hold up the
            // panel. The whole of it is in the tooltip, and Copy Value copies it (C-ATTR-09).
            // Counted in scalars: one character may carry any number of combining marks.
            let scalars = string.unicodeScalars
            guard scalars.count > Self.longestShownString else {
                return Self.text(string, wraps: true)
            }
            let shown = String(String.UnicodeScalarView(scalars.prefix(Self.longestShownString)))
            let label = Self.text(shown + "\u{2026}", wraps: true)
            label.toolTip = string
            return label
        case .color(let color):
            return colorContent(color)
        case .point(let point):
            return Self.fields([("X", point.x), ("Y", point.y)], perLine: 2)
        case .size(let size):
            return Self.fields([("W", size.width), ("H", size.height)], perLine: 2)
        case .rect(let rect):
            return Self.fields(
                [("X", rect.origin.x), ("Y", rect.origin.y), ("W", rect.size.width),
                 ("H", rect.size.height)], perLine: 2)
        case .insets(let insets):
            return Self.fields(
                [("T", insets.top), ("L", insets.left), ("B", insets.bottom),
                 ("R", insets.right)], perLine: 2)
        case .transform(let transform):
            guard transform != .identity else {
                return Self.text(localized("attributes.value.identity"), color: .tertiaryLabelColor)
            }
            return matrix(transform)
        case .enumeration:
            let box = Self.box(radius: 5)
            box.addContent(VStack(alignment: .leading) {
                Self.text(plainText, size: 12)
            }
            .padding(horizontal: 6, vertical: 1))
            firstLineInset = 1
            return HStack(alignment: .top) {
                box
                Spacer()
            }
        }
    }

    private func colorContent(_ color: Color) -> NSView {
        swatchColor = color
        let swatch = SwatchView(color: color)
            .accessibilityIdentifier(Self.swatchIdentifier)
            .frame(width: 16, height: 16)
        // Components that a hexadecimal code cannot write are shown as they are.
        let text = AttributeText.hexRGB(of: color).map { hex in
            [hex, AttributeText.alpha(of: color)].compactMap { $0 }.joined(separator: "  ")
        } ?? plainText
        let label = Self.text(text, digits: true)
        label.toolTip = plainText
        return HStack(alignment: .center, spacing: 6) {
            swatch
            label
            Spacer()
        }
    }

    private func matrix(_ t: Transform3D) -> NSView {
        let rows = [
            [t.m11, t.m12, t.m13, t.m14], [t.m21, t.m22, t.m23, t.m24],
            [t.m31, t.m32, t.m33, t.m34], [t.m41, t.m42, t.m43, t.m44],
        ]
        let grid = NSGridView(views: rows.map { row in
            row.map { number in
                Self.text(
                    AttributeText.number(number),
                    font: .monospacedSystemFont(ofSize: 10.5, weight: .regular))
                    .alignment(.right)
            }
        })
        grid.columnSpacing = 8
        grid.rowSpacing = 2
        for index in 0..<grid.numberOfColumns { grid.column(at: index).xPlacement = .trailing }
        let box = Self.box(radius: Theme.Radius.control)
        box.addContent(VStack(alignment: .leading) { grid }.padding(horizontal: 8, vertical: 6))
        firstLineInset = 6
        return HStack(alignment: .top) {
            box
            Spacer()
        }
    }

    // MARK: - Parts

    /// A label that can be selected and copied.
    private static func text(
        _ string: String, color: NSColor = .labelColor, digits: Bool = false,
        wraps: Bool = false, size: CGFloat = 12, font: NSFont? = nil
    ) -> NSTextField {
        let label = wraps
            ? NSTextField(wrappingLabelWithString: string)
            : NSTextField(labelWithString: string)
        label.font = font ?? (digits
            ? .monospacedDigitSystemFont(ofSize: size, weight: .regular)
            : .systemFont(ofSize: size))
        label.textColor = color
        label.isSelectable = true
        if !wraps { label.lineBreakMode = .byTruncatingTail }
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    /// Numbers with a small letter before each, `perLine` to a line.
    private static func fields(_ fields: [(String, Double)], perLine: Int) -> NSView {
        let lines = stride(from: 0, to: fields.count, by: perLine).map {
            Array(fields[$0..<min($0 + perLine, fields.count)])
        }
        return VStack(alignment: .fill, spacing: 2) {
            for line in lines {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    for (letter, number) in line {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            NSTextField(labelWithString: letter)
                                .font(.systemFont(ofSize: 10, weight: .medium))
                                .textColor(.tertiaryLabelColor)
                            text(AttributeText.number(number), digits: true)
                                .accessibilityIdentifier(fieldIdentifier)
                                .toolTip(AttributeText.number(number))
                            Spacer()
                        }
                    }
                }
                .distribution(.fillEqually)
            }
        }
    }

    /// A rounded box filled with the system's faintest fill, which follows the appearance.
    private static func box(radius: CGFloat) -> NSBox {
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 0
        box.cornerRadius = radius
        box.fillColor = .quaternarySystemFill
        box.contentViewMargins = .zero
        box.titlePosition = .noTitle
        return box
    }
}

/// A colour swatch: the colour over a checkerboard, so that transparency shows, in a rounded
/// square with a hairline edge.
final class SwatchView: NSView {
    let color: Color

    init(color: Color) {
        self.color = color
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: 4, yRadius: 4)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSColor.white.setFill()
        bounds.fill()
        NSColor(white: 0.8, alpha: 1).setFill()
        let square: CGFloat = 4
        for row in 0..<Int(ceil(bounds.height / square)) {
            for column in 0..<Int(ceil(bounds.width / square)) where (row + column) % 2 == 0 {
                NSRect(
                    x: CGFloat(column) * square, y: CGFloat(row) * square, width: square,
                    height: square
                ).fill()
            }
        }
        // sRGB, as images are (P-IMG-01); components out of 0...1 are drawn as extended sRGB.
        let components = [color.red, color.green, color.blue, color.alpha].map { CGFloat($0) }
        NSColor(colorSpace: .extendedSRGB, components: components, count: 4).setFill()
        bounds.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.separatorColor.setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
    }
}
