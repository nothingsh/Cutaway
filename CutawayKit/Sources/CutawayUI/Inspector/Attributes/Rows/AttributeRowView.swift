import AppKit
import CutawayWire
import DeclarativeAppKit

/// One attribute in the attribute panel: its title, and its value shown the way its type reads
/// best (C-ATTR-02), or an editor for it (C-ATTR-05). Values can be selected and copied. A
/// row being changed shows a spinner, and one whose change failed a warning sign, both at the
/// end of the field that changed (C-ATTR-06). It has no menu of its own (reported by the user).
final class AttributeRowView: NSView {
    static let identifier = "attributes.row"
    static let titleIdentifier = "attributes.title"
    /// The share of the row the title takes.
    static let titleShare: CGFloat = 0.38

    let title: String
    /// The value as text; on screen only when there is no editor.
    private(set) var valueView: AttributeValueView
    let editor: AttributeEditorView?
    private let titleLabel: NSTextField
    private let valueSlot = NSView()

    init(title: String, value: AttributeValue?, editor: AttributeEditorView? = nil) {
        self.title = title
        self.editor = editor
        valueView = AttributeValueView(value: value)
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        setAccessibilityIdentifier(Self.identifier)
        titleLabel
            .font(Theme.Font.caption)
            .textColor(.secondaryLabelColor)
            .lineBreakMode(.byTruncatingTail)
            .accessibilityIdentifier(Self.titleIdentifier)
        // A cut title is read in full from its tooltip.
        titleLabel.toolTip = title
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        valueSlot.addContent(editor ?? valueView)
        // The title lines up with the value's first line; it is a point smaller. Beside an
        // editor it lines up with the middle of the field.
        let titleInset = editor == nil
            ? valueView.firstLineInset + 1 : (AttributeEditorView.fieldHeight - 13) / 2
        let titleColumn = VStack(alignment: .fill) { titleLabel }
            .padding(top: titleInset, leading: 0, bottom: 0, trailing: 0)
        addHStack(alignment: .top, spacing: Theme.Spacing.small) {
            titleColumn
            valueSlot
        }
        .padding(horizontal: Theme.Spacing.large, vertical: 3)
        titleColumn.widthAnchor.constraint(
            equalTo: widthAnchor, multiplier: Self.titleShare, constant: -Theme.Spacing.large
        ).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows another value in place (C-ATTR-06): an editor keeps what is being typed or
    /// dragged; a value without an editor is drawn again.
    func show(_ value: AttributeValue?) {
        guard value != valueView.value else { return }
        valueView = AttributeValueView(value: value)
        if let editor {
            editor.show(value)
        } else {
            for subview in valueSlot.subviews { subview.removeFromSuperview() }
            valueSlot.addContent(valueView)
        }
    }

    /// Whether a change is on its way, and why the last one failed, if it did.
    func show(sending: Bool, failure: String?) {
        editor?.showStatus(sending: sending, failure: failure)
        // Faint while sending, unless it is the field being typed in or dragged.
        editor?.alphaValue = sending && !(editor?.isBeingEdited ?? false) ? 0.7 : 1
    }

    /// The reason the warning sign gives, or nil. For tests.
    var failureText: String? { editor?.failureText }
    /// Whether the spinner shows. For tests.
    var isSending: Bool { editor?.isShowingSending ?? false }
}
