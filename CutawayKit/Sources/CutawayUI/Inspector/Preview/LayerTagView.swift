import AppKit

/// A layer's tag on the preview (C-PREV-16): its icon, its title and its size, white on the
/// accent colour for the selected layer, on dark grey for the one under the pointer. 20 points
/// high, as wide as it says.
final class LayerTagView: NSView {
    /// The accessibility identifiers of the two tags.
    static let selectedIdentifier = "preview.tag.selected"
    static let hoveredIdentifier = "preview.tag.hovered"
    static let height: CGFloat = 20

    enum Kind {
        case selected
        case hovered
    }

    let kind: Kind
    /// The layer it names; nil while it shows none.
    private(set) var summary: LayerSummary?

    private let icon = NSImageView()
    private let titleField = NSTextField(labelWithString: "").configure {
        $0.font = .systemFont(ofSize: 11, weight: .semibold)
        $0.textColor = .white
        $0.lineBreakMode = .byTruncatingTail
    }

    private let sizeField = NSTextField(labelWithString: "").configure {
        $0.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        $0.textColor = NSColor.white.withAlphaComponent(0.72)
    }

    /// What the tag says, for tests.
    var title: String { titleField.stringValue }
    var size: String { sizeField.stringValue }

    init(_ kind: Kind) {
        self.kind = kind
        super.init(frame: NSRect(x: 0, y: 0, width: 40, height: Self.height))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        self.shadow = shadow
        for view in [icon, titleField, sizeField] as [NSView] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityIdentifier(kind == .selected ? Self.selectedIdentifier : Self.hoveredIdentifier)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Shows a layer, sized to what it says; nil hides the tag.
    func show(_ summary: LayerSummary?) {
        guard summary != self.summary else { return }
        self.summary = summary
        guard let summary else {
            isHidden = true
            return
        }
        icon.image = LayerIconImage.image(summary.icon, side: 14, isSelected: kind == .selected)
        titleField.stringValue = summary.title
        sizeField.stringValue = summary.size ?? ""
        titleField.sizeToFit()
        sizeField.sizeToFit()
        // 4 points before the icon, 5 between the parts, 7 after the last.
        var x: CGFloat = 4
        icon.frame = NSRect(x: x, y: 3, width: 14, height: 14)
        x += 14 + 5
        let title = titleField.frame.size
        titleField.frame = NSRect(x: x, y: (Self.height - title.height) / 2, width: title.width, height: title.height)
        x += title.width
        if !sizeField.stringValue.isEmpty {
            x += 5
            let size = sizeField.frame.size
            sizeField.frame = NSRect(x: x, y: (Self.height - size.height) / 2, width: size.width, height: size.height)
            x += size.width
        }
        sizeField.isHidden = sizeField.stringValue.isEmpty
        setFrameSize(NSSize(width: ceil(x + 7), height: Self.height))
        setAccessibilityLabel([summary.title, summary.size].compactMap { $0 }.joined(separator: ", "))
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = switch kind {
        case .selected: NSColor.controlAccentColor.cgColor
        case .hovered: Self.hoveredBackground.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// Dark grey, a little lighter in the dark appearance so that it stands off the canvas.
    private static let hoveredBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 58 / 255, green: 58 / 255, blue: 62 / 255, alpha: 0.92)
            : NSColor(srgbRed: 36 / 255, green: 36 / 255, blue: 40 / 255, alpha: 0.88)
    }
}
