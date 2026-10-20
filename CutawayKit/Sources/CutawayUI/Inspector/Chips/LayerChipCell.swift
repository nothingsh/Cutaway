import AppKit
import CutawayModel

/// A chip that names a layer in a line of text (C-LAYOUT-06, C-ATTR-28): its icon and name.
/// One that goes to a layer of the hierarchy can be pointed at and clicked.
struct LayerChip: Equatable {
    enum Icon: Equatable {
        /// The layer's icon, as the hierarchy has it.
        case layer(LayerIcon)
        /// A layout guide's, drawn dashed.
        case guide
        /// None: an object the hierarchy does not have.
        case none
    }

    var name: String
    var icon: Icon
    /// The layer a click selects, or nil when it goes nowhere.
    var layerID: UInt64?
    /// Whether pointing at it does something.
    var canHover: Bool
    var toolTip: String?

    var canSelect: Bool { layerID != nil }
}

/// The chip in a text (C-LAYOUT-06): its icon and name on a light rounded fill; a layout
/// guide's dashed in the colour of its mark, without a fill; one that goes nowhere without a
/// fill, its name grey. The pointer on it gives it an accent edge.
class LayerChipCell: NSTextAttachmentCell {
    static let height: CGFloat = 19
    static let iconSide: CGFloat = 13
    /// Before the icon, between it and the name, and after the name.
    static let insets = (leading: CGFloat(3), gap: CGFloat(4), trailing: CGFloat(6))
    static let font = NSFont.systemFont(ofSize: 11.5)
    /// Room on either side of the chip, so that it does not touch the text.
    static let margin: CGFloat = 1

    let chip: LayerChip
    private let dimmed: Bool
    var isHovered = false
    /// Worked out when the chip is made: the text system asks for them off the main actor's
    /// guarantees.
    private nonisolated let size: NSSize
    private nonisolated let baseline: NSPoint

    /// `textFont` is the font of the text around it, whose capitals the chip is centred on.
    init(_ chip: LayerChip, dimmed: Bool, textFont: NSFont) {
        self.chip = chip
        self.dimmed = dimmed
        let insets = Self.insets
        let name = NSAttributedString(string: chip.name, attributes: [.font: Self.font])
        let icon = chip.icon == .none ? insets.trailing - insets.leading : Self.iconSide + insets.gap
        size = NSSize(
            width: insets.leading + icon + ceil(name.size().width) + insets.trailing + 2 * Self.margin,
            height: Self.height)
        // The chip's middle on the middle of the text's capitals.
        baseline = NSPoint(x: 0, y: (textFont.capHeight / 2 - Self.height / 2).rounded())
        super.init(textCell: "")
        setAccessibilityLabel(chip.name)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var icon: NSImage? {
        switch chip.icon {
        case .layer(let icon): LayerIconImage.image(icon, side: Self.iconSide)
        case .guide: ConstraintIconImage.guide(side: Self.iconSide)
        case .none: nil
        }
    }

    private var text: NSAttributedString {
        let grey = dimmed || !chip.canSelect
        return NSAttributedString(
            string: chip.name,
            attributes: [
                .font: Self.font,
                .foregroundColor: grey ? NSColor.secondaryLabelColor : .labelColor,
            ])
    }

    override nonisolated func cellSize() -> NSSize { size }

    override nonisolated func cellBaselineOffset() -> NSPoint { baseline }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let frame = cellFrame.insetBy(dx: Self.margin, dy: 0)
        let shape = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), xRadius: 4.5, yRadius: 4.5)
        shape.lineWidth = 1
        if isHovered {
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
            shape.fill()
            NSColor.controlAccentColor.setStroke()
            shape.stroke()
        } else if chip.icon == .guide {
            shape.setLineDash([2.5, 1.5], count: 2, phase: 0)
            Theme.constraintEnd.withAlphaComponent(0.6).setStroke()
            shape.stroke()
        } else if chip.canSelect {
            NSColor.quaternarySystemFill.setFill()
            shape.fill()
        }
        let insets = Self.insets
        let side = Self.iconSide
        var textX = frame.minX + insets.trailing
        if let icon {
            let flipped = controlView?.isFlipped ?? true
            icon.draw(
                in: NSRect(x: frame.minX + insets.leading, y: frame.midY - side / 2, width: side, height: side),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: flipped, hints: nil)
            textX = frame.minX + insets.leading + side + insets.gap
        }
        let text = text
        let height = ceil(text.size().height)
        text.draw(in: NSRect(
            x: textX, y: frame.midY - height / 2, width: frame.maxX - textX - insets.trailing / 2, height: height))
    }

    override func wantsToTrackMouse() -> Bool { false }
}

/// Text that wraps and can be selected, in which some characters are chips (C-LAYOUT-06,
/// C-ATTR-28). Pointing at a chip that does something marks it and calls `pointed(at:)`;
/// clicking one that goes to a layer calls `chose(_:)`; anywhere else the text is selected.
class ChipTextView: NSTextView {
    /// The chip under the pointer, by its character.
    private(set) var hoveredIndex: Int? {
        didSet {
            guard hoveredIndex != oldValue else { return }
            for index in [oldValue, hoveredIndex].compactMap({ $0 }) {
                chipCell(at: index)?.isHovered = index == hoveredIndex
            }
            needsDisplay = true
        }
    }

    private var trackingArea: NSTrackingArea?

    init() {
        // TextKit 1, for the height of the laid-out text and the chips' cells.
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        drawsBackground = false
        textContainerInset = .zero
        isVerticallyResizable = false
        isHorizontallyResizable = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @available(*, unavailable)
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        fatalError("init(frame:textContainer:) is not supported")
    }

    /// The pointer came onto a chip, or left the chips for nil.
    func pointed(at cell: LayerChipCell?) {}

    /// A chip that goes to a layer was clicked.
    func chose(_ cell: LayerChipCell) {}

    /// Every chip, with its character, in order.
    var chipCells: [(index: Int, cell: LayerChipCell)] {
        guard let storage = textStorage else { return [] }
        var chips: [(Int, LayerChipCell)] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) {
            value, range, _ in
            if let cell = (value as? NSTextAttachment)?.attachmentCell as? LayerChipCell {
                chips.append((range.location, cell))
            }
        }
        return chips
    }

    func chipCell(at index: Int) -> LayerChipCell? {
        guard let storage = textStorage, index < storage.length else { return nil }
        return storage.attribute(.attachment, at: index, effectiveRange: nil)
            .flatMap { ($0 as? NSTextAttachment)?.attachmentCell as? LayerChipCell }
    }

    /// A chip as a character of text in `font`.
    static func attachment(_ cell: LayerChipCell, font: NSFont) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.attachmentCell = cell
        let chip = NSMutableAttributedString(attachment: attachment)
        chip.addAttribute(.font, value: font, range: NSRange(location: 0, length: chip.length))
        if let tip = cell.chip.toolTip {
            chip.addAttribute(.toolTip, value: tip, range: NSRange(location: 0, length: chip.length))
        }
        return chip
    }

    /// The character of the chip under a point in the view, if any.
    private func chipIndex(at point: NSPoint) -> Int? {
        guard let manager = layoutManager, let container = textContainer else { return nil }
        let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = manager.glyphIndex(for: inContainer, in: container, fractionOfDistanceThroughGlyph: &fraction)
        guard glyph < manager.numberOfGlyphs else { return nil }
        let rect = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
        guard rect.contains(inContainer) else { return nil }
        let index = manager.characterIndexForGlyph(at: glyph)
        return chipCell(at: index) == nil ? nil : index
    }

    /// Puts the pointer on the chip at a character, or on none, as the mouse does.
    func point(at index: Int?) {
        let cell = index.flatMap(chipCell(at:))
        let shown = cell?.chip.canHover == true ? index : nil
        guard shown != hoveredIndex else { return }
        hoveredIndex = shown
        pointed(at: shown == nil ? nil : cell)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        point(at: chipIndex(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        point(at: nil)
    }

    /// A click on a chip that goes somewhere selects its layer; anywhere else it selects text.
    override func mouseDown(with event: NSEvent) {
        if let index = chipIndex(at: convert(event.locationInWindow, from: nil)),
           let cell = chipCell(at: index), cell.chip.canSelect
        {
            chose(cell)
            return
        }
        super.mouseDown(with: event)
    }

    /// The pointing hand over the chips that go somewhere.
    override func resetCursorRects() {
        super.resetCursorRects()
        guard let manager = layoutManager, let container = textContainer else { return }
        for (index, cell) in chipCells where cell.chip.canSelect {
            let glyphs = manager
                .glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
            var rect = manager.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += textContainerOrigin.x
            rect.origin.y += textContainerOrigin.y
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    override var intrinsicContentSize: NSSize {
        guard let manager = layoutManager, let container = textContainer else {
            return super.intrinsicContentSize
        }
        manager.ensureLayout(for: container)
        let height = manager.usedRect(for: container).height
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(max(height, 15)))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        // The text wraps to the new width.
        if widthChanged { invalidateIntrinsicContentSize() }
    }

    /// The text is given anew: the chip under the pointer is gone.
    func setText(_ text: NSAttributedString) {
        if hoveredIndex != nil { point(at: nil) }
        textStorage?.setAttributedString(text)
        invalidateIntrinsicContentSize()
        window?.invalidateCursorRects(for: self)
    }
}
