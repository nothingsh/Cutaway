import AppKit
import CutawayWire
import DeclarativeAppKit

/// One attribute in the attribute panel: its title, and its value in the editor of its kind
/// (C-ATTR-05), read-only when it cannot be changed (C-ATTR-02, C-ATTR-04). Values can be
/// selected and copied. A
/// row being changed shows a spinner, and one whose change failed a warning sign, both at the
/// end of the field that changed (C-ATTR-06). It has no menu of its own (reported by the user).
///
/// How the row is arranged depends on the kind of value (C-ATTR-12). Most have the title in a
/// column 78 points wide beside the value, wrapping to two lines and cut short past them. A
/// boolean is a checkbox followed by its title. A rect has its title above and its four numbers
/// in a row below it; insets are a box beside their title (C-ATTR-22).
///
/// While its editor is used, a line under the row may say, in red, why what is typed is
/// not sent (C-ATTR-13).
final class AttributeRowView: NSView {
    static let identifier = "attributes.row"
    static let noteIdentifier = "attributes.note"
    static let titleIdentifier = "attributes.title"
    static let checkboxIdentifier = "attributes.editor.checkbox"
    /// Between a checkbox and its title.
    static let checkboxGap: CGFloat = 6
    /// The width of the title's column beside the value.
    static let titleWidth: CGFloat = 78

    /// Where the title is.
    enum Arrangement: Equatable {
        case beside, above, checkbox
    }

    let title: String
    /// The ID of the attribute, which a filter matches as well as the title (C-ATTR-14).
    var attributeID: String?
    let kind: AttributeValueKind
    /// The value shown, and as plain text, as Copy Value copies it (`AttributeText`).
    private(set) var value: AttributeValue?
    var plainText: String { AttributeText.text(of: value) }
    /// The editor, when the value can be changed (C-ATTR-04).
    let editor: AttributeEditorView?
    /// The same controls, read-only, when it cannot (C-ATTR-02).
    let display: AttributeEditorView?
    private(set) var arrangement: Arrangement
    /// The title beside the value and the title above it; only the one in use is shown, and
    /// only it carries `titleIdentifier`.
    private let sideTitle: WrappingTitleField
    private let topTitle: WrappingTitleField
    private let titleColumn: NSStackView
    private let besideStack: NSStackView
    /// Where the rest starts: below the title above it, or at the top. The row is pinned by
    /// hand: another stack around the rest made a thousand rows take minutes to lay out.
    private var besideTop: NSLayoutConstraint?
    /// The column's width beside the value, and none: one of them is active.
    private var besideWidth: NSLayoutConstraint?
    private var noWidth: NSLayoutConstraint?

    /// Where the rest ends: at the bottom, or above the note.
    private var besideBottom: NSLayoutConstraint?
    /// The line under the row, in the row only while it has something to say.
    private lazy var noteLabel = NSTextField(wrappingLabelWithString: "")
        .font(.systemFont(ofSize: 11))
        .accessibilityIdentifier(Self.noteIdentifier)
        .configure { $0.setContentCompressionResistancePriority(Theme.textGivesWay, for: .horizontal) }

    private let valueSlot = NSView()

    init(
        title: String, value: AttributeValue?, kind: AttributeValueKind? = nil,
        editor: AttributeEditorView? = nil, unit: AttributeUnit = .unspecified
    ) {
        self.title = title
        self.editor = editor
        self.value = value
        // A value of another kind than its attribute's is shown as what it is (P-ATTR-03).
        // A server before 0.3 gives no kind: a missing value then reads as text.
        let given = kind == AttributeValueKind.none ? nil : kind
        let kind = editor?.kind ?? value.map(Self.kind(of:)) ?? given ?? Self.kind(of: value)
        self.kind = kind
        display = editor == nil
            ? AttributeEditorView(
                attribute: Attribute(id: nil, title: title, value: value, valueKind: kind, unit: unit),
                isReadOnly: true)
            : nil
        sideTitle = WrappingTitleField(title: title)
        topTitle = WrappingTitleField(title: title)
        sideTitle.widthIsGiven = true
        topTitle.widthIsGiven = true
        arrangement = switch kind {
        case .bool: .checkbox
        case .rect: .above
        default: .beside
        }
        // The title's first line starts at the field's top (reported by the user).
        let sideTitle = sideTitle
        titleColumn = VStack(alignment: .fill) { sideTitle }
        // Centred until the value turns out taller than a field (`layout()`).
        besideStack = HStack(alignment: .center, spacing: Theme.Spacing.small) {}
        super.init(frame: .zero)
        setAccessibilityIdentifier(Self.identifier)
        valueSlot.addContent(editor ?? display ?? NSView())
        besideStack.addArrangedSubview(titleColumn)
        besideStack.addArrangedSubview(valueSlot)
        pin(besideStack, top: false)
        apply(arrangement)
        editor?.onNote = { [weak self] note in self?.show(note) }
        (editor ?? display)?.onTallChange = { [weak self] in self?.alignTitle() }
        alignTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The title shown now: beside or above the value, or after the checkbox.
    var shownTitle: WrappingTitleField? {
        switch arrangement {
        case .beside: sideTitle
        case .above: topTitle
        case .checkbox:
            Descendants.first(in: valueSlot) { $0 is WrappingTitleField } as? WrappingTitleField
        }
    }

    /// Whether a filter keeps the row: its title or its attribute's ID holds it (C-ATTR-14).
    func matches(_ filter: String) -> Bool {
        AttributesViewModel.match(of: filter, in: title) != nil
            || attributeID.map { AttributesViewModel.match(of: filter, in: $0) != nil } == true
    }

    /// Highlights where the title holds a filter, or shows it plain for nil (C-ATTR-14).
    func highlight(_ filter: String?) {
        sideTitle.highlight(filter)
        topTitle.highlight(filter)
        let checkboxTitle = Descendants.first(in: valueSlot) { $0 is WrappingTitleField }
        (checkboxTitle as? WrappingTitleField)?.highlight(filter)
    }

    /// A checkbox and its title after it, which takes the rest of the line and toggles it when
    /// clicked; `badge` floats at the end of the title.
    static func checkboxLine(_ checkbox: NSButton, title: String, badge: NSView?) -> NSView {
        let label = WrappingTitleField(title: title, color: .labelColor)
            .accessibilityIdentifier(titleIdentifier)
        if checkbox.isEnabled {
            label.onClick = { [weak checkbox] in checkbox?.performClick(nil) }
        }
        // A little room between the box and its title (reported by the user).
        let line = HStack(alignment: .top, spacing: checkboxGap) {
            checkbox
            label
            if let badge { badge }
        }
        checkbox.setContentHuggingPriority(.required, for: .horizontal)
        return line
    }

    /// Puts the title beside the value, above it, or leaves it to the checkbox.
    private func apply(_ arrangement: Arrangement) {
        self.arrangement = arrangement
        let beside = arrangement == .beside
        sideTitle.isHidden = !beside
        // The title above is in the row only while it is used.
        besideTop?.isActive = false
        if arrangement == .above {
            if topTitle.superview == nil { pin(topTitle, top: true) }
            besideTop = besideStack.topAnchor.constraint(equalTo: topTitle.bottomAnchor, constant: 3)
        } else {
            topTitle.removeFromSuperview()
            besideTop = besideStack.topAnchor.constraint(equalTo: topAnchor, constant: Self.margin)
        }
        besideTop?.isActive = true
        sideTitle.setAccessibilityIdentifier(beside ? Self.titleIdentifier : nil)
        topTitle.setAccessibilityIdentifier(arrangement == .above ? Self.titleIdentifier : nil)
        // The column stays in the stack, so that its width can be set: none, unless it holds
        // the title.
        besideStack.spacing = beside ? Theme.Spacing.small : 0
        if besideWidth == nil {
            // Set to the title's width at each layout (`layout()`).
            besideWidth = titleColumn.widthAnchor.constraint(equalToConstant: Self.titleWidth)
            noWidth = titleColumn.widthAnchor.constraint(equalToConstant: 0)
        }
        // Off before on, so that the two never hold at once.
        (beside ? noWidth : besideWidth)?.isActive = false
        (beside ? besideWidth : noWidth)?.isActive = true
    }

    /// Above and below the row's content.
    private static let margin: CGFloat = 3

    /// Adds a part of the row across its width: the title above at the top, the rest at the
    /// bottom.
    private func pin(_ view: NSView, top: Bool) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        let end = top
            ? view.topAnchor.constraint(equalTo: topAnchor, constant: Self.margin)
            : view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.margin)
        if !top { besideBottom = end }
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.large),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.large),
            end,
        ])
    }

    /// Shows a note under the row, or takes it away (C-ATTR-13). It is added only while
    /// shown, as the title above is.
    private func show(_ note: String?) {
        guard let note else {
            guard noteLabel.superview != nil else { return }
            noteLabel.removeFromSuperview()
            besideBottom?.isActive = true
            return
        }
        noteLabel.stringValue = note
        noteLabel.textColor = .systemRed
        guard noteLabel.superview == nil else { return }
        besideBottom?.isActive = false
        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(noteLabel)
        NSLayoutConstraint.activate([
            noteLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.large),
            noteLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.large),
            noteLabel.topAnchor.constraint(equalTo: besideStack.bottomAnchor, constant: 2),
            noteLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.margin),
        ])
    }

    /// The note under the row, or nil. For tests.
    var noteText: String? { noteLabel.superview == nil ? nil : noteLabel.stringValue }
    /// Whether the note says why a value is not sent. For tests.
    var noteIsError: Bool { noteLabel.superview != nil && noteLabel.textColor == .systemRed }

    /// Both titles are given the width they will have before the row is laid out, so that a
    /// title is as tall as its lines in the same pass.
    override func layout() {
        // A label reaches past its place by its alignment insets, as labels do, so that its
        // text lines up with the column's edges.
        let insets = sideTitle.alignmentRectInsets.left + sideTitle.alignmentRectInsets.right
        if arrangement == .beside { sideTitle.give(width: Self.titleWidth + insets) }
        topTitle.give(width: bounds.width - 2 * Theme.Spacing.large + insets)
        if noteLabel.superview != nil {
            let width = bounds.width - 2 * Theme.Spacing.large
            if noteLabel.preferredMaxLayoutWidth != width { noteLabel.preferredMaxLayoutWidth = width }
        }
        super.layout()
    }

    /// Centred on a value one field tall, at the top of a taller one (C-ATTR-12).
    private func alignTitle() {
        TitleAlignment.apply(besideStack, title: titleColumn, isTall: (editor ?? display)?.isTall ?? false)
    }

    /// The name of the system colour shown, if any (C-ATTR-22).
    private var systemColorName: String?

    /// Shows another value in place (C-ATTR-06): an editor keeps what is being typed.
    /// `systemColorName` names a colour that is one of UIKit's (C-ATTR-22).
    func show(_ value: AttributeValue?, systemColorName: String? = nil) {
        guard value != self.value || systemColorName != self.systemColorName else { return }
        self.value = value
        self.systemColorName = systemColorName
        (editor ?? display)?.show(value, systemColorName: systemColorName)
    }

    /// Whether a change is on its way, and why the last one failed, if it did. The editor is
    /// faint while it is on its way.
    func show(sending: Bool, failure: String?) {
        editor?.showStatus(sending: sending, failure: failure)
    }

    /// Fades the row and says why the value has no effect, or shows it plainly for nil
    /// (C-ATTR-21).
    func showInactive(_ reason: String?) {
        (editor ?? display)?.showInactive(reason)
        let color: NSColor = reason == nil ? .secondaryLabelColor : .tertiaryLabelColor
        sideTitle.textColor = color
        topTitle.textColor = color
    }

    /// Why the value has no effect, or nil. For tests.
    var inactiveReason: String? { (editor ?? display)?.inactiveReason }

    /// The layer's size, for an insets box (C-ATTR-22).
    func show(layerSize: String?) {
        (editor ?? display)?.show(layerSize: layerSize)
    }

    /// The reason the warning sign gives, or nil. For tests.
    var failureText: String? { editor?.failureText }
    /// Whether the spinner shows. For tests.
    var isSending: Bool { editor?.isShowingSending ?? false }

    /// The kind of a value, for a row given none: a nil value reads as text.
    private static func kind(of value: AttributeValue?) -> AttributeValueKind {
        switch value {
        case .bool: .bool
        case .integer: .integer
        case .double: .double
        case .string, nil: .string
        case .color: .color
        case .point: .point
        case .size: .size
        case .rect: .rect
        case .insets: .insets
        case .transform: .transform
        case .enumeration: .enumeration
        }
    }
}

/// Finds views below another, for the row's checkbox title.
private enum Descendants {
    @MainActor
    static func first(in view: NSView, where matches: (NSView) -> Bool) -> NSView? {
        for subview in view.subviews {
            if matches(subview) { return subview }
            if let found = first(in: subview, where: matches) { return found }
        }
        return nil
    }
}
