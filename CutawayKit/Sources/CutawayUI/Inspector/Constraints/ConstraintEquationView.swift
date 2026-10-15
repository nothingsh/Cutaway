import AppKit
import CutawayModel

/// A constraint's equation: text that wraps and can be selected, in which the other ends are
/// chips (C-LAYOUT-06). Pointing at a chip hovers its layer and stresses its mark on the
/// preview; clicking one selects its layer (C-LAYOUT-03).
final class ConstraintEquationView: NSTextView, NSTextViewDelegate {
    static let identifier = "constraints.equation"

    private let onShowLayer: (UInt64) -> Void
    /// The chip under the pointer, or nil when it leaves the chips (C-LAYOUT-06).
    var onHoverEnd: (ConstraintRow.End?) -> Void = { _ in }
    /// The equation as words, a chip by its name: what it says, for tests and accessibility.
    let plainText: String
    /// The chip under the pointer, by its character.
    private(set) var hoveredIndex: Int? {
        didSet {
            guard hoveredIndex != oldValue else { return }
            for index in [oldValue, hoveredIndex].compactMap({ $0 }) {
                chip(at: index)?.isHovered = index == hoveredIndex
            }
            needsDisplay = true
        }
    }

    private var trackingArea: NSTrackingArea?

    init(
        _ pieces: [ConstraintRow.Piece], dimmed: Bool, onShowLayer: @escaping (UInt64) -> Void
    ) {
        self.onShowLayer = onShowLayer
        plainText = ConstraintRow.plain(pieces)
        // TextKit 1, for the height of the laid-out text and the chips' cells.
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let container = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
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
        delegate = self
        setAccessibilityIdentifier(Self.identifier)
        setAccessibilityValue(plainText)
        storage.setAttributedString(Self.attributed(pieces, dimmed: dimmed))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @available(*, unavailable)
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        fatalError("init(frame:textContainer:) is not supported")
    }

    /// Every chip, with its character, in order.
    var chips: [(index: Int, cell: ConstraintChipCell)] {
        guard let storage = textStorage else { return [] }
        var chips: [(Int, ConstraintChipCell)] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) {
            value, range, _ in
            if let cell = (value as? NSTextAttachment)?.attachmentCell as? ConstraintChipCell {
                chips.append((range.location, cell))
            }
        }
        return chips
    }

    /// The layers the chips that can be clicked go to, in order. For tests.
    var linkedLayerIDs: [UInt64] {
        chips.compactMap(\.cell.end.layerID)
    }

    /// Clicks the chip of a layer, as the mouse does. For tests.
    func clickLink(to id: UInt64) {
        if let end = chips.first(where: { $0.cell.end.layerID == id })?.cell.end { select(end) }
    }

    /// Puts the pointer on the chip of an end, or on none, as the mouse does. For tests.
    func hoverEnd(at index: Int?) {
        point(at: index)
    }

    private func chip(at index: Int) -> ConstraintChipCell? {
        textStorage?.attribute(.attachment, at: index, effectiveRange: nil)
            .flatMap { ($0 as? NSTextAttachment)?.attachmentCell as? ConstraintChipCell }
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
        return chip(at: index) == nil ? nil : index
    }

    private func point(at index: Int?) {
        let end = index.flatMap(chip(at:))?.end
        let shown = end?.canHover == true ? index : nil
        guard shown != hoveredIndex else { return }
        hoveredIndex = shown
        onHoverEnd(shown == nil ? nil : end)
    }

    private func select(_ end: ConstraintRow.End) {
        guard let id = end.layerID else { return }
        onShowLayer(id)
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
           let end = chip(at: index)?.end, end.canSelect
        {
            select(end)
            return
        }
        super.mouseDown(with: event)
    }

    /// The pointing hand over the chips that go somewhere.
    override func resetCursorRects() {
        super.resetCursorRects()
        guard let manager = layoutManager, let container = textContainer else { return }
        for (index, cell) in chips where cell.end.canSelect {
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

    private static func attributed(
        _ pieces: [ConstraintRow.Piece], dimmed: Bool
    ) -> NSAttributedString {
        let font = Theme.Font.constraint
        let color: NSColor = dimmed ? .secondaryLabelColor : .labelColor
        let result = NSMutableAttributedString()
        for piece in pieces {
            switch piece {
            case .text(let text):
                result.append(NSAttributedString(
                    string: text, attributes: [.font: font, .foregroundColor: color]))
            case .selfItem:
                result.append(NSAttributedString(
                    string: "self",
                    attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
            case .end(let end):
                let attachment = NSTextAttachment()
                attachment.attachmentCell = ConstraintChipCell(end, dimmed: dimmed)
                let chip = NSMutableAttributedString(attachment: attachment)
                chip.addAttribute(.font, value: font, range: NSRange(location: 0, length: chip.length))
                result.append(chip)
            }
        }
        return result
    }
}

extension ConstraintRow {
    /// Pieces as words, a chip by its name.
    static func plain(_ pieces: [Piece]) -> String {
        pieces.map { piece in
            switch piece {
            case .text(let text): text
            case .selfItem: "self"
            case .end(let end): end.name
            }
        }.joined()
    }
}

/// The chip of a constraint's other end (C-LAYOUT-06): its icon and name on a light rounded
/// fill; a layout guide's dashed in the colour of its mark, without a fill; one that goes
/// nowhere without a fill, its name grey. The pointer on it gives it an accent edge.
final class ConstraintChipCell: NSTextAttachmentCell {
    static let height: CGFloat = 19
    static let iconSide: CGFloat = 13
    /// Before the icon, between it and the name, and after the name.
    static let insets = (leading: CGFloat(3), gap: CGFloat(4), trailing: CGFloat(6))
    static let font = NSFont.systemFont(ofSize: 11.5)
    /// Room on either side of the chip, so that it does not touch the text.
    static let margin: CGFloat = 1

    let end: ConstraintRow.End
    private let dimmed: Bool
    var isHovered = false
    /// Worked out when the chip is made: the text system asks for them off the main actor's
    /// guarantees.
    private nonisolated let size: NSSize
    private nonisolated let baseline: NSPoint

    init(_ end: ConstraintRow.End, dimmed: Bool) {
        self.end = end
        self.dimmed = dimmed
        let insets = Self.insets
        let name = NSAttributedString(string: end.name, attributes: [.font: Self.font])
        size = NSSize(
            width: insets.leading + Self.iconSide + insets.gap + ceil(name.size().width)
                + insets.trailing + 2 * Self.margin,
            height: Self.height)
        // The chip's middle on the middle of the text's capitals.
        baseline = NSPoint(x: 0, y: (Theme.Font.constraint.capHeight / 2 - Self.height / 2).rounded())
        super.init(textCell: "")
        setAccessibilityLabel(end.name)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private var icon: NSImage {
        switch end.kind {
        case .view(let icon): LayerIconImage.image(icon, side: Self.iconSide)
        case .guide: ConstraintIconImage.guide(side: Self.iconSide)
        }
    }

    private var text: NSAttributedString {
        let grey = dimmed || !end.canSelect
        return NSAttributedString(
            string: end.name,
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
        } else if case .guide = end.kind {
            shape.setLineDash([2.5, 1.5], count: 2, phase: 0)
            Theme.constraintEnd.withAlphaComponent(0.6).setStroke()
            shape.stroke()
        } else if end.canSelect {
            NSColor.quaternarySystemFill.setFill()
            shape.fill()
        }
        let insets = Self.insets
        let side = Self.iconSide
        let flipped = controlView?.isFlipped ?? true
        icon.draw(
            in: NSRect(x: frame.minX + insets.leading, y: frame.midY - side / 2, width: side, height: side),
            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: flipped, hints: nil)
        let text = text
        let height = ceil(text.size().height)
        text.draw(in: NSRect(
            x: frame.minX + insets.leading + side + insets.gap, y: frame.midY - height / 2,
            width: frame.width - insets.leading - side - insets.gap - insets.trailing / 2,
            height: height))
    }

    override func wantsToTrackMouse() -> Bool { false }
}
