import AppKit

/// A text field of the attribute panel. It sends what was typed when Return is pressed or it
/// loses the focus, and puts its text back on Esc (C-ATTR-05). Leaving it without typing sends
/// nothing: the text shown may be rounded. It keeps no undo of its own: the window's undo is
/// the attributes' (C-ATTR-08), and two kinds of undo in one stack would be hard to follow.
final class AttributeEditField: NSTextField, NSTextFieldDelegate {
    /// Called with the text when editing ends with something typed, unless it ended on Esc.
    var onCommit: (String) -> Void = { _ in }
    /// The text of the value shown: what Esc goes back to. Written into the field unless
    /// something is being typed there; after Return, which keeps the field in editing, the
    /// answer still comes in (P-SET-04).
    var shownText = "" {
        didSet { if !isTyping { showText(shownText) } }
    }

    /// Whether the text was changed by typing since it was last shown or sent.
    private(set) var isTyping = false
    private var isCancelling = false

    var isBeingEdited: Bool { isTyping }

    init(placeholder: String? = nil, digits: Bool = true) {
        super.init(frame: .zero)
        isBordered = false
        drawsBackground = false
        isEditable = true
        isSelectable = true
        focusRingType = .none
        usesSingleLineMode = true
        lineBreakMode = .byTruncatingTail
        placeholderString = placeholder ?? localized("attributes.value.none")
        font = digits
            ? .monospacedDigitSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 12)
        cell?.allowsUndo = false
        delegate = self
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setAccessibilityIdentifier(AttributeEditorView.fieldIdentifier)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Puts the shown text back and ends editing without sending anything, as Esc does.
    func cancelTyping() {
        isCancelling = true
        revert()
        if currentEditor() != nil { window?.makeFirstResponder(nil) }
        isCancelling = false
    }

    /// Puts the shown text back, as after what was typed could not be sent.
    func revert() {
        isTyping = false
        showText(shownText)
    }

    /// Into the field, and into its field editor while it has one.
    private func showText(_ text: String) {
        stringValue = text
        (currentEditor() as? NSTextView)?.string = text
    }

    func controlTextDidChange(_ notification: Notification) {
        isTyping = true
    }

    func control(
        _ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
    ) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        cancelTyping()
        return true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard !isCancelling, isTyping else { return }
        isTyping = false
        onCommit(stringValue)
    }
}
