import AppKit
import DeclarativeAppKit

/// The editor of a text (C-ATTR-05): a field of several lines, so that a long text can be read
/// and changed whole. It is as tall as its text, from one line to four; a longer text scrolls
/// in it. Return sends what was typed, as leaving it does; Option-Return starts a new line; Esc
/// puts the text back. Like the one-line fields it keeps no undo of its own (C-ATTR-08), and
/// leaving it without typing sends nothing.
final class AttributeTextArea: NSView, NSTextViewDelegate {
    static let identifier = "attributes.editor.text"
    static let maximumLines = 4
    static let font = NSFont.systemFont(ofSize: 12)
    /// Around the text, so that one line is as tall as the other fields and starts where
    /// their text does.
    static let inset = NSSize(width: 7, height: 3.5)

    /// Called with the text when editing ends with something typed, unless it ended on Esc.
    var onCommit: (String) -> Void = { _ in }
    /// The text of the value shown: what Esc goes back to. Written in unless something is
    /// being typed.
    var shownText = "" {
        didSet { if !isTyping { showText(shownText) } }
    }

    /// Whether the text was changed by typing since it was last shown or sent.
    private(set) var isTyping = false
    private var isCancelling = false
    var isBeingEdited: Bool { isTyping }

    // TextKit 1 from the start: the height is measured with its layout manager, and asking a
    // TextKit 2 view for one swaps its text system and leaves the view alive.
    let textView = NSTextView(usingTextLayoutManager: false)
    let scrollView = NSScrollView()
    /// "None" while there is no text. For tests, too.
    let placeholder: NSTextField = PassThroughLabel(labelWithString: localized("attributes.value.none"))
    private var height: NSLayoutConstraint?
    private var measuredWidth: CGFloat = 0

    init(name: String) {
        super.init(frame: .zero)
        textView.configure {
            $0.isRichText = false
            $0.importsGraphics = false
            $0.allowsUndo = false
            $0.font = Self.font
            $0.textColor = .labelColor
            $0.drawsBackground = false
            $0.textContainerInset = Self.inset
            $0.textContainer?.lineFragmentPadding = 0
            $0.textContainer?.widthTracksTextView = true
            $0.isVerticallyResizable = true
            $0.isHorizontallyResizable = false
            $0.autoresizingMask = .width
            // What is typed is sent as it is: nothing replaces quotes, dashes or words.
            $0.isAutomaticQuoteSubstitutionEnabled = false
            $0.isAutomaticDashSubstitutionEnabled = false
            $0.isAutomaticTextReplacementEnabled = false
            $0.isAutomaticSpellingCorrectionEnabled = false
            $0.isContinuousSpellCheckingEnabled = false
            $0.isGrammarCheckingEnabled = false
            $0.isAutomaticLinkDetectionEnabled = false
            $0.isAutomaticDataDetectionEnabled = false
            $0.smartInsertDeleteEnabled = false
            $0.layoutManager?.allowsNonContiguousLayout = true
            $0.delegate = self
            $0.setAccessibilityIdentifier(Self.identifier)
            $0.setAccessibilityLabel(name)
        }
        scrollView.configure {
            $0.documentView = textView
            $0.drawsBackground = false
            $0.borderType = .noBorder
            $0.hasVerticalScroller = true
            $0.autohidesScrollers = true
            $0.scrollerStyle = .overlay
        }
        textView.frame = NSRect(x: 0, y: 0, width: 100, height: 22)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        addContent(scrollView)
        // Shown while there is no text, as a one-line field's placeholder is.
        placeholder.font = Self.font
        placeholder.textColor = .placeholderTextColor
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset.width),
            placeholder.topAnchor.constraint(equalTo: topAnchor, constant: Self.inset.height),
        ])
        let height = heightAnchor.constraint(equalToConstant: AttributeEditorView.fieldHeight)
        height.isActive = true
        self.height = height
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        if abs(bounds.width - measuredWidth) > 0.5 {
            measuredWidth = bounds.width
            fitHeight()
        }
    }

    /// The height of one line of text.
    static var lineHeight: CGFloat {
        NSLayoutManager().defaultLineHeight(for: font)
    }

    /// As tall as the text, from one line to `maximumLines`.
    private func fitHeight() {
        guard let manager = textView.layoutManager, let container = textView.textContainer else { return }
        if measuredWidth > 0 {
            textView.setFrameSize(NSSize(width: scrollView.contentSize.width, height: textView.frame.height))
        }
        // Only as far as the lines shown: a long text is laid out as it scrolls.
        manager.ensureLayout(
            forBoundingRect: NSRect(
                x: 0, y: 0, width: max(measuredWidth, 1),
                height: Self.lineHeight * CGFloat(Self.maximumLines + 1) + 2 * Self.inset.height),
            in: container)
        let line = Self.lineHeight
        let used = max(manager.usedRect(for: container).height, line)
        let shown = min(used, line * CGFloat(Self.maximumLines))
        let wanted = max(shown + 2 * Self.inset.height, AttributeEditorView.fieldHeight)
        if let height, abs(height.constant - wanted) > 0.5 {
            height.constant = wanted
            onHeightChange()
        }
    }

    /// Called when the field grows or shrinks by a line.
    var onHeightChange: () -> Void = {}
    /// Whether it shows more than one line.
    var isTall: Bool { (height?.constant ?? 0) > AttributeEditorView.fieldHeight + 0.5 }

    /// How many lines the field shows now. For tests.
    var shownLines: Int {
        Int(((height?.constant ?? 0) - 2 * Self.inset.height) / Self.lineHeight + 0.5)
    }

    private func showText(_ text: String) {
        textView.string = text
        textView.textColor = isReadOnly ? .secondaryLabelColor : .labelColor
        placeholder.isHidden = !text.isEmpty || !showsNone
        fitHeight()
    }

    /// Whether the value shown is none, rather than an empty text: only none says "None".
    var showsNone = true {
        didSet { placeholder.isHidden = !textView.string.isEmpty || !showsNone }
    }

    /// Whether it only shows its text (C-ATTR-04).
    private(set) var isReadOnly = false

    /// Shows the text without letting it be typed: grey, still selectable and scrolled.
    func makeReadOnly() {
        isReadOnly = true
        textView.isEditable = false
        textView.textColor = .secondaryLabelColor
    }

    /// Puts the shown text back and ends editing without sending anything, as Esc does.
    func cancelTyping() {
        isCancelling = true
        isTyping = false
        showText(shownText)
        if window?.firstResponder === textView { window?.makeFirstResponder(nil) }
        isCancelling = false
    }

    private func commit() {
        guard isTyping else { return }
        isTyping = false
        onCommit(textView.string)
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        isTyping = true
        placeholder.isHidden = true
        fitHeight()
    }

    func textDidEndEditing(_ notification: Notification) {
        guard !isCancelling else { return }
        commit()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            commit()
            return true
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            textView.insertText("\n", replacementRange: textView.selectedRange())
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancelTyping()
            return true
        case #selector(NSResponder.insertTab(_:)):
            window?.selectNextKeyView(nil)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            window?.selectPreviousKeyView(nil)
            return true
        default:
            return false
        }
    }
}

/// A label that clicks go through, to the text below it.
private final class PassThroughLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
