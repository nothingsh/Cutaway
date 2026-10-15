import AppKit

/// A text field of the attribute panel. It sends what was typed when Return is pressed or it
/// loses the focus, and puts its text back on Esc (C-ATTR-05). Leaving it without typing sends
/// nothing: the text shown may be rounded. It keeps no undo of its own: the window's undo is
/// the attributes' (C-ATTR-08), and two kinds of undo in one stack would be hard to follow.
///
/// What was typed may be refused (C-ATTR-05, C-ATTR-13). Refused on Return, the field keeps
/// it, selected, and stays in editing with the reason told; refused on leaving, the field goes
/// back to the value shown.
final class AttributeEditField: NSTextField, NSTextFieldDelegate {
    /// What becomes of typed text.
    enum Commit: Equatable {
        case accepted
        case refused(reason: String)
    }

    /// Called with the text when editing ends with something typed, unless it ended on Esc;
    /// `byReturn` tells Return from leaving the field.
    var onCommit: (_ text: String, _ byReturn: Bool) -> Commit = { _, _ in .accepted }
    /// Called with the reason when Return was refused, and with nil once the reason is no
    /// longer the field's to tell.
    var onRefusal: (String?) -> Void = { _ in }
    /// Called when the field takes the focus, and when its editing ends.
    var onFocus: (Bool) -> Void = { _ in }
    /// The text of the value shown: what Esc goes back to. Written into the field unless
    /// something is being typed there; after Return, which keeps the field in editing, the
    /// answer still comes in (P-SET-04).
    var shownText = "" {
        didSet { if !isTyping { showText(shownText) } }
    }

    /// Whether the text was changed by typing since it was last shown or sent.
    private(set) var isTyping = false
    /// The reason Return was refused, until the field's editing ends or Return is pressed
    /// again: typing on leaves it shown.
    private(set) var refusal: String?
    private var isCancelling = false

    /// Whether the field has the focus.
    var hasFocus: Bool { currentEditor() != nil }

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

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocus(true) }
        return became
    }

    /// Puts the shown text back and ends editing without sending anything, as Esc does.
    func cancelTyping() {
        isCancelling = true
        revert()
        if currentEditor() != nil { window?.makeFirstResponder(nil) }
        isCancelling = false
        endEditingTold()
    }

    /// Puts the shown text back, as after what was typed could not be sent.
    func revert() {
        isTyping = false
        showText(shownText)
        setRefusal(nil)
    }

    /// Into the field, and into its field editor while it has one.
    private func showText(_ text: String) {
        stringValue = text
        (currentEditor() as? NSTextView)?.string = text
    }

    private func setRefusal(_ reason: String?) {
        guard reason != refusal else { return }
        refusal = reason
        onRefusal(reason)
    }

    /// The focus is gone: the hint and any reason go with it.
    private func endEditingTold() {
        setRefusal(nil)
        onFocus(false)
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
        guard !isCancelling else { return }
        let movement = notification.userInfo?["NSTextMovement"] as? Int
        let byReturn = movement == NSTextMovement.return.rawValue
        guard isTyping else {
            if !byReturn { endEditingTold() }
            return
        }
        switch onCommit(stringValue, byReturn) {
        case .accepted:
            isTyping = false
            setRefusal(nil)
            if !byReturn { onFocus(false) }
        case .refused(let reason) where byReturn:
            // Kept as typed and selected, to be typed over (C-ATTR-05).
            setRefusal(reason)
            if currentEditor() == nil { window?.makeFirstResponder(self) }
            currentEditor()?.selectAll(nil)
        case .refused:
            revert()
            onFocus(false)
        }
    }
}
