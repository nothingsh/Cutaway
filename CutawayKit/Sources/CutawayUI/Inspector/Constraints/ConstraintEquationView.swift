import AppKit

/// A constraint's equation: text that wraps and can be selected, with links that select the
/// layer they name (C-LAYOUT-03).
final class ConstraintEquationView: NSTextView, NSTextViewDelegate {
    static let identifier = "constraints.equation"
    private static let scheme = "cutaway-layer"

    private let onShowLayer: (UInt64) -> Void

    init(
        _ pieces: [ConstraintRow.Piece], dimmed: Bool, onShowLayer: @escaping (UInt64) -> Void
    ) {
        self.onShowLayer = onShowLayer
        // TextKit 1, for the height of the laid-out text.
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
        linkTextAttributes = [
            .foregroundColor: NSColor.controlAccentColor, .cursor: NSCursor.pointingHand,
        ]
        setAccessibilityIdentifier(Self.identifier)
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

    /// The layers the equation links to, in order. For tests.
    var linkedLayerIDs: [UInt64] {
        guard let storage = textStorage else { return [] }
        var ids: [UInt64] = []
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) {
            value, _, _ in
            if let id = (value as? URL).flatMap(Self.layerID) { ids.append(id) }
        }
        return ids
    }

    /// Clicks the link to a layer, as the mouse does. For tests.
    func clickLink(to id: UInt64) {
        guard let storage = textStorage else { return }
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) {
            value, range, stop in
            guard let url = value as? URL, Self.layerID(url) == id else { return }
            clicked(onLink: url, at: range.location)
            stop.pointee = true
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

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let id = (link as? URL).flatMap(Self.layerID) else { return false }
        onShowLayer(id)
        return true
    }

    private static func layerID(_ url: URL) -> UInt64? {
        guard url.scheme == scheme else { return nil }
        return UInt64(url.absoluteString.dropFirst(scheme.count + 1))
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
                    attributes: [
                        .font: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]))
            case .link(let name, let id):
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: NSColor.controlAccentColor,
                ]
                attributes[.link] = URL(string: "\(scheme):\(id)")
                result.append(NSAttributedString(string: name, attributes: attributes))
            }
        }
        return result
    }
}
