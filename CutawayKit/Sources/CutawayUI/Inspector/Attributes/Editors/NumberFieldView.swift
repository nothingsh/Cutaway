import AppKit
import DeclarativeAppKit

/// A number that can be typed or dragged (C-ATTR-05, C-ATTR-07): a grip or a letter, and a
/// field in a rounded box.
final class NumberFieldView: NSView {
    let isInteger: Bool
    let field = AttributeEditField()
    let handle: ScrubHandle?
    /// The spinner or warning sign shown at the field's end (C-ATTR-06).
    let badge = EditBadge()
    /// The number shown, nil for none.
    private(set) var number: Double?
    /// Called with a number to send; `continuous` while a drag goes on.
    var onSet: (Double, _ continuous: Bool) -> Void = { _, _ in }
    /// The number a drag started from, while one goes on.
    private var dragStart: Double?

    var isBeingEdited: Bool { field.isTyping || dragStart != nil }

    /// `letter` names a component; nil gives a grip. Without a handle the number is only typed.
    /// `name` is what accessibility calls the number.
    init(letter: String?, isInteger: Bool, name: String = "", showsHandle: Bool = true) {
        self.isInteger = isInteger
        handle = showsHandle
            ? ScrubHandle(content: letter.map { letter in
                NSTextField(labelWithString: letter)
                    .font(.systemFont(ofSize: 10, weight: .medium))
                    .textColor(.tertiaryLabelColor)
            } ?? NSImageView()
                .image(Theme.symbol(Theme.Symbol.scrub, size: 8, weight: .semibold))
                .contentTintColor(.tertiaryLabelColor))
            : nil
        super.init(frame: .zero)
        field.setAccessibilityLabel(name)
        handle?.setAccessibilityLabel(localized("attributes.editor.adjust", name))
        field.onCommit = { [weak self] text in self?.commit(text) }
        handle?.onScrub = { [weak self] distance, modifiers, ended in
            self?.scrub(by: distance, modifiers: modifiers, ended: ended)
        }
        handle?.onClick = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.field)
        }
        let box = AttributeEditorView.fieldBox()
        box.contentView?.addHStack(alignment: .center, spacing: 5) {
            if let handle { handle }
            field
        }
        .padding(horizontal: 6, vertical: 0)
        addContent(
            box
                .frame(height: AttributeEditorView.fieldHeight)
                .overlay(alignment: .trailing, offset: CGPoint(x: -4, y: 0)) { badge })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows a number, unless it is being typed or dragged.
    func show(_ number: Double?) {
        guard dragStart == nil else { return }
        self.number = number
        field.shownText = number.map(AttributeText.number) ?? ""
    }

    /// What was typed: sent when it reads as a finite number that differs from the one shown;
    /// otherwise the field goes back to the number (C-ATTR-05).
    func commit(_ text: String) {
        let typed = AttributeValueEditing.number(typed: text, isInteger: isInteger)
        guard let typed else {
            field.revert()
            return
        }
        guard typed != number else {
            field.revert()
            return
        }
        number = typed
        field.shownText = AttributeText.number(typed)
        onSet(typed, false)
    }

    /// A drag of `distance` points from where it started.
    func scrub(by distance: CGFloat, modifiers: NSEvent.ModifierFlags, ended: Bool) {
        let start = dragStart ?? number ?? 0
        // There is no step from a number that is not finite: it can only be typed over
        // (C-ATTR-09).
        guard start.isFinite else { return }
        dragStart = ended ? nil : start
        let step = Self.step(from: start, isInteger: isInteger, modifiers: modifiers)
        let value = AttributeValueEditing.scrubbed(start, by: distance, step: step)
        // Near the largest Double a step can overflow (C-ATTR-09).
        guard value.isFinite else { return }
        guard !isInteger || Int64(exactly: value) != nil else { return }
        number = value
        field.shownText = AttributeText.number(value)
        field.stringValue = field.shownText
        onSet(value, !ended)
    }

    /// How much one point of a drag changes a number (`AttributeValueEditing.step`): Option
    /// is a tenth, Shift ten times.
    static func step(
        from start: Double, isInteger: Bool, modifiers: NSEvent.ModifierFlags
    ) -> Double {
        AttributeValueEditing.step(
            from: start, isInteger: isInteger, tenth: modifiers.contains(.option),
            tenfold: modifiers.contains(.shift))
    }
}

/// What a number is dragged by: a small grip, or the letter of a component. Dragging left and
/// right changes the number; a click without a drag puts the focus in its field (C-ATTR-05).
final class ScrubHandle: NSView {
    /// The distance dragged so far in points, the keys held, and whether the drag ended.
    var onScrub: (_ distance: CGFloat, _ modifiers: NSEvent.ModifierFlags, _ ended: Bool) -> Void =
        { _, _, _ in }
    var onClick: () -> Void = {}
    private var start: NSPoint?
    private var moved = false

    init(content: NSView) {
        super.init(frame: .zero)
        setAccessibilityIdentifier(AttributeEditorView.handleIdentifier)
        addContent(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        start = event.locationInWindow
        moved = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let distance = event.locationInWindow.x - start.x
        if distance != 0 { moved = true }
        guard moved else { return }
        onScrub(distance, event.modifierFlags, false)
    }

    override func mouseUp(with event: NSEvent) {
        defer { start = nil }
        guard let start else { return }
        if moved {
            onScrub(event.locationInWindow.x - start.x, event.modifierFlags, true)
        } else {
            onClick()
        }
    }
}
