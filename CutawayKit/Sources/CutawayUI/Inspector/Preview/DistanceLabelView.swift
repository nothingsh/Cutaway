import AppKit

/// A distance's value written over the preview (C-PREV-10): white on a rounded patch of the
/// measuring colour, 16 points high.
final class DistanceLabelView: NSView {
    /// The accessibility identifier.
    static let identifier = "preview.distanceLabel"

    private let field = NSTextField(labelWithString: "").configure {
        $0.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        $0.textColor = .white
    }

    var text: String {
        get { field.stringValue }
        set {
            field.stringValue = newValue
            field.sizeToFit()
            let size = field.frame.size
            setFrameSize(NSSize(width: size.width + 10, height: 16))
            field.setFrameOrigin(NSPoint(x: 5, y: (16 - size.height) / 2))
            setAccessibilityLabel(newValue)
        }
    }

    var color = NSColor.systemRed {
        didSet { layer?.backgroundColor = color.cgColor }
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 10, height: 16))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = color.cgColor
        addSubview(field)
        setAccessibilityIdentifier(Self.identifier)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
