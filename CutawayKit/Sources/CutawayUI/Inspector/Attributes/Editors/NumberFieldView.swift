import AppKit
import CutawayModel
import CutawayWire
import DeclarativeAppKit

/// A number that is typed (C-ATTR-05): a field in a rounded box, after the letter of its
/// component when it has one. It is not dragged: dragging sent values as it went, which sat
/// badly with the limits. What is typed outside its limit
/// (C-ATTR-13) is refused; `check` refuses what the whole value would not take.
///
/// A proportion is shown and typed in percent, and sent as a proportion; a number on its own
/// says its unit at the end of the field (C-ATTR-20). What it takes and sends is always the
/// value as the protocol has it.
final class NumberFieldView: NSView {
    static let unitIdentifier = "attributes.editor.unit"

    let isInteger: Bool
    let field = AttributeEditField()
    /// The spinner or warning sign shown at the field's end (C-ATTR-06).
    let badge = EditBadge()
    /// The number shown, nil for none.
    private(set) var number: Double?
    /// Called with a number to send.
    var onSet: (Double) -> Void = { _ in }
    /// Why a number may not be sent as part of the value, or nil when it may.
    var check: (Double) -> String? = { _ in nil }
    /// Why the number shown is outside its limit, or nil: the number is red, the reason its
    /// tooltip.
    private(set) var outOfRangeReason: String?
    /// Called when the field takes or loses the focus, or its refusal changes.
    var onStateChange: () -> Void = {}
    private let box = AttributeEditorView.fieldBox()

    var isBeingEdited: Bool { field.isTyping }
    /// Whether the field has the focus.
    var hasFocus: Bool { field.hasFocus }
    /// Whether the field had the focus when it last said so: while it is told it lost it, it
    /// may still have its field editor.
    private(set) var isFocused = false
    /// Why what was typed is refused, while it is.
    var refusal: String? { field.refusal }

    /// `letter` names a component, shown before the field; a click on it puts the focus in
    /// the field. `name` is what accessibility calls the number.
    /// How the number reads (C-ATTR-20). A proportion of an integer reads as a plain number.
    let unit: AttributeUnit
    private var inPercent: Bool { unit == .fraction && !isInteger }
    /// "pt" or "%" after the field, for a number on its own.
    private let unitLabel = NSTextField(labelWithString: "")
        .font(.systemFont(ofSize: 11))
        .textColor(.tertiaryLabelColor)
        .accessibilityIdentifier(NumberFieldView.unitIdentifier)

    init(
        letter: String?, isInteger: Bool, name: String = "", unit: AttributeUnit = .unspecified,
        showsUnit: Bool = true
    ) {
        self.isInteger = isInteger
        self.unit = unit
        super.init(frame: .zero)
        let suffix: String? = switch unit {
        case .points: "pt"
        case .fraction where !isInteger: "%"
        default: nil
        }
        unitLabel.stringValue = suffix ?? ""
        unitLabel.isHidden = suffix == nil || !showsUnit
        field.setAccessibilityLabel(name)
        field.onCommit = { [weak self] text, _ in self?.commit(text) ?? .accepted }
        field.onFocus = { [weak self] focused in
            self?.isFocused = focused
            self?.onStateChange()
        }
        field.onRefusal = { [weak self] reason in
            self?.showRefused(reason != nil)
            self?.onStateChange()
        }
        let letterLabel = letter.map { letter in
            NSTextField(labelWithString: letter)
                .font(.systemFont(ofSize: 10, weight: .medium))
                .textColor(.tertiaryLabelColor)
                .configure {
                    $0.setContentHuggingPriority(.required, for: .horizontal)
                    $0.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(focusField)))
                }
        }
        for label in [unitLabel] {
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        }
        box.contentView?.addHStack(alignment: .center, spacing: 5) {
            if let letterLabel { letterLabel }
            field
            unitLabel
        }
        .padding(horizontal: 6, vertical: 0)
        addContent(
            box
                .frame(height: AttributeEditorView.fieldHeight)
                .overlay(alignment: .trailing, offset: CGPoint(x: -4, y: 0)) { badge })
    }

    /// Whether it only shows its number (C-ATTR-04).
    private(set) var isReadOnly = false

    /// Shows the number without letting it be typed: no fill, grey, still selectable.
    func makeReadOnly() {
        isReadOnly = true
        field.isEditable = false
        box.fillColor = .clear
        if outOfRangeReason == nil { field.textColor = .secondaryLabelColor }
    }

    @objc private func focusField() {
        window?.makeFirstResponder(field)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows a number, keeping what is being typed. `outOfRange` says why it is outside its
    /// limit, if it is: the app may have set it so itself (C-ATTR-13).
    func show(_ number: Double?, outOfRange: String? = nil) {
        self.number = number
        field.shownText = number.map(text) ?? ""
        outOfRangeReason = outOfRange
        field.textColor = outOfRange != nil ? .systemRed : isReadOnly ? .secondaryLabelColor : .labelColor
        field.toolTip = outOfRange
    }

    /// What was typed: sent when it reads as a number the field can send, within its limit
    /// and taken by the whole value, and it differs from the one shown (C-ATTR-05,
    /// C-ATTR-13). Otherwise it is refused with the reason.
    @discardableResult
    func commit(_ text: String) -> AttributeEditField.Commit {
        var typed: Double
        switch AttributeValueEditing.number(typed: text, isInteger: isInteger) {
        case .success(let number): typed = number
        case .failure(let problem): return .refused(reason: LimitText.message(problem))
        }
        if inPercent { typed /= 100 }
        if let reason = check(typed) { return .refused(reason: reason) }
        guard typed != number else {
            field.revert()
            return .accepted
        }
        number = typed
        field.shownText = self.text(typed)
        onSet(typed)
        return .accepted
    }

    /// The number as the field shows it: in percent for a proportion.
    private func text(_ number: Double) -> String {
        inPercent ? AttributeText.percent(number) : AttributeText.number(number)
    }

    /// The unit after the field, or nil. For tests.
    var shownUnit: String? { unitLabel.isHidden ? nil : unitLabel.stringValue }

    /// A red outline while what was typed is refused (C-ATTR-13).
    private func showRefused(_ refused: Bool) {
        box.borderColor = refused ? .systemRed : .separatorColor
        box.borderWidth = refused ? 1 : isBare ? 0 : 0.5
    }

    /// Whether the number has no box of its own: in an insets box (C-ATTR-22).
    private(set) var isBare = false

    /// Shows the number without a box of its own, in the middle of its place; a refusal still
    /// outlines it.
    func makeBare() {
        isBare = true
        box.fillColor = .clear
        box.borderWidth = 0
        field.alignment = .center
    }

    /// Whether the outline is red. For tests.
    var isShowingRefusal: Bool { box.borderColor == .systemRed }
}
