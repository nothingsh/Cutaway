import AppKit

/// The title of an attribute (C-ATTR-12): it wraps at words, takes at most two lines and cuts
/// the second short only when even two lines cannot hold it; only then is the whole title in
/// its tooltip. It gives way to the inspector's width rather than widen it. A filter's match is
/// highlighted in it (C-ATTR-14).
final class WrappingTitleField: NSTextField {
    static let maximumLines = 2

    let title: String

    /// What a click on the title does, if anything: a checkbox's title toggles it.
    var onClick: (() -> Void)?

    init(title: String, font: NSFont = Theme.Font.caption, color: NSColor = .secondaryLabelColor) {
        self.title = title
        super.init(frame: .zero)
        stringValue = title
        self.font = font
        textColor = color
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        lineBreakMode = .byWordWrapping
        maximumNumberOfLines = Self.maximumLines
        // A field made with a frame scrolls its text on one line: a label wraps it.
        cell?.isScrollable = false
        cell?.wraps = true
        cell?.truncatesLastVisibleLine = true
        setContentCompressionResistancePriority(Theme.textGivesWay, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// A label of more than one line has the height of the width it was last given: give it
    /// the width it has now.
    /// Whether something else gives the title its width ahead of layout (`give(width:)`), as a
    /// row does; otherwise the title takes the width it was laid out at.
    var widthIsGiven = false

    override func layout() {
        if !widthIsGiven { give(width: bounds.width) }
        super.layout()
    }

    /// As tall as the lines the title is drawn in, at most two. Measured as the cell draws
    /// it: the size Auto Layout is given otherwise can find one line enough for a title the
    /// cell wraps, and the second line is then cut off ("Layout Margins" at 78 points).
    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        guard preferredMaxLayoutWidth > 0 else { return size }
        let lines = min(Self.maximumLines, Self.lineCount(of: self, width: preferredMaxLayoutWidth))
        return NSSize(width: size.width, height: CGFloat(lines) * Self.lineHeight(of: font ?? Theme.Font.caption))
    }

    /// Wraps the title for this width, ahead of the layout that gives it.
    func give(width: CGFloat) {
        guard width > 0, abs(preferredMaxLayoutWidth - width) > 0.5 else { return }
        preferredMaxLayoutWidth = width
        invalidateIntrinsicContentSize()
    }

    /// The tooltip asks for its text when it is about to show (`view(_:stringForToolTip:…)`),
    /// so that it says the whole title only if the title is cut short then.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        removeAllToolTips()
        addToolTip(bounds, owner: self, userData: nil)
    }

    /// The tooltip's text: the whole title when it is cut short, otherwise none.
    var toolTipText: String? { isTruncated ? title : nil }

    /// Highlights where the title holds a filter, or shows it plain for nil (C-ATTR-14).
    func highlight(_ filter: String?) {
        let font = self.font ?? Theme.Font.caption
        let color = textColor ?? .secondaryLabelColor
        guard let text = Self.highlighted(title, filter: filter, font: font, color: color) else {
            guard showsMatch else { return }
            stringValue = title
            showsMatch = false
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        attributedStringValue = text
        showsMatch = true
    }

    /// Whether a filter's match is highlighted now. For tests.
    private(set) var showsMatch = false

    /// `title` with where it holds `filter` marked, or nil when it does not hold it.
    static func highlighted(
        _ title: String, filter: String?, font: NSFont, color: NSColor
    ) -> NSMutableAttributedString? {
        guard let filter, let range = AttributesViewModel.match(of: filter, in: title) else { return nil }
        let text = NSMutableAttributedString(
            string: title, attributes: [.font: font, .foregroundColor: color])
        text.addAttributes(
            [
                .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.25),
                .foregroundColor: NSColor.labelColor,
            ],
            range: NSRange(range, in: title))
        return text
    }

    override func mouseDown(with event: NSEvent) {
        guard let onClick else {
            super.mouseDown(with: event)
            return
        }
        onClick()
    }

    /// How many lines the title needs, whole, at its width now.
    var linesNeeded: Int {
        Self.lineCount(of: self, width: bounds.width)
    }

    /// Whether the title is cut short at its width now.
    var isTruncated: Bool { linesNeeded > Self.maximumLines }

    /// The height of one line of a title in this font, as a label lays it out.
    static func lineHeight(of font: NSFont) -> CGFloat {
        let label = NSTextField(labelWithString: "X")
        label.font = font
        return label.intrinsicContentSize.height
    }

    /// How many lines `text` takes, whole, in a label `width` points wide: measured as a label
    /// draws it.
    static func lineCount(of text: String, font: NSFont, width: CGFloat) -> Int {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        return lineCount(of: label, width: width)
    }

    /// How many lines a label's text takes, whole, `width` points wide, as its cell draws it.
    static func lineCount(of label: NSTextField, width: CGFloat) -> Int {
        guard width > 0, let cell = label.cell?.copy() as? NSCell else { return .max }
        // The whole text, not cut after the label's last line.
        (cell as? NSTextFieldCell)?.truncatesLastVisibleLine = false
        cell.wraps = true
        cell.stringValue = label.stringValue
        let whole = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10_000)).height
        let line = lineHeight(of: label.font ?? Theme.Font.caption)
        return line > 0 ? max(1, Int((whole / line).rounded())) : 1
    }
}

extension WrappingTitleField: NSViewToolTipOwner {
    func view(
        _ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
        userData: UnsafeMutableRawPointer?
    ) -> String {
        toolTipText ?? ""
    }
}
