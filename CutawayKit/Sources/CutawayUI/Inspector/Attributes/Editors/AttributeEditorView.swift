import AppKit
import CutawayModel
import CutawayWire
import DeclarativeAppKit

/// The editor of one attribute, by the kind of its value (C-ATTR-05): a checkbox, a number, a
/// text, a colour, numbers by component, a matrix or a menu of cases. It is built for one kind
/// and shows new values in place (`show(_:)`), leaving alone what is being typed or dragged.
/// Nothing here depends on the attribute's ID (C-ATTR-03).
///
/// A value that cannot be changed is shown by the same controls, read-only (C-ATTR-02,
/// C-ATTR-04): the boxes have no fill, the text is grey and cannot be typed into but can be
/// selected, and the checkbox, the colour well and the menu are disabled. Editable and
/// read-only rows look alike but for that.
final class AttributeEditorView: NSView {
    static let identifier = "attributes.editor"
    /// A read-only value's, in place of `identifier`.
    static let readOnlyIdentifier = "attributes.value"
    static let fieldIdentifier = "attributes.editor.field"
    static let checkboxIdentifier = AttributeRowView.checkboxIdentifier
    static let wellIdentifier = "attributes.editor.well"
    static let hexIdentifier = "attributes.editor.hex"
    static let popUpIdentifier = "attributes.editor.popup"
    static let segmentedIdentifier = "attributes.editor.segmented"
    static let alphaIdentifier = "attributes.editor.alpha"
    static let insetsIdentifier = "attributes.editor.insets"
    static let insetsSizeIdentifier = "attributes.editor.insets.size"
    static let disclosureIdentifier = "attributes.editor.disclosure"
    static let spinnerIdentifier = "attributes.editor.spinner"
    static let failureIdentifier = "attributes.editor.failure"
    static let fieldHeight: CGFloat = 22
    /// Transparent black, which an emptied hex field sends and which shows as "None".
    static let transparent = Color(red: 0, green: 0, blue: 0, alpha: 0)

    /// How a compound row (C-ATTR-19) wants a part drawn: other letters for the components,
    /// a letter before a single number, a rect's four numbers two by two, and a number below
    /// zero as "—" (no intrinsic size).
    struct Options {
        var letters: [String]?
        var letter: String?
        var grid = false
        var negativeIsNone = false
        /// Whether a single number says its unit; not in the table of priorities.
        var showsUnit = true
    }

    let kind: AttributeValueKind
    let options: Options
    /// Whether it only shows the value.
    let isReadOnly: Bool
    /// The attribute's title, which names its controls for accessibility.
    let title: String
    /// The attribute as the editor was built for it: its limits do not change while it
    /// lives, since new limits build the row anew.
    private let attribute: Attribute
    /// Called when the note changes.
    var onNote: (String?) -> Void = { _ in }
    /// What the row says under it while the editor is used (C-ATTR-13): why what is typed
    /// is refused, while it is. The range is not said ahead of time (user's decision,
    /// 2026-10-14).
    private(set) var note: String? {
        didSet { if note != oldValue { onNote(note) } }
    }

    /// The numbers of the value, for the note and for marking those outside their limits.
    private var numberFields: [NumberFieldView] = []
    private(set) var value: AttributeValue?
    let onSet: (AttributeValue?, _ continuous: Bool) -> Void
    let onFinish: () -> Void
    var showValue: (AttributeValue?) -> Void = { _ in }
    var editing: () -> Bool = { false }
    /// How long the colour panel stays still before a change of colour counts as finished.
    let colorPauseDelay: TimeInterval
    var colorPause: DispatchWorkItem?
    /// The colour well, for a colour. The colour panel sends to it while it is active.
    weak var colorWell: NSColorWell?
    /// Set once the editor has left its window: the panel moving then changes nothing.
    var hasLeftWindow = false
    /// Where a change of this attribute shows: the field changed last, or the first one.
    var badges: [EditBadge] = []
    var activeBadge: EditBadge?
    /// Opens or closes the matrix of a transform.
    private var disclosureAction: () -> Void = {}
    /// The cases of an enum and their raw values, as the app last gave them (P-ATTR-07).
    var cases: [String] = []
    var caseValues: [Int64] = []

    /// Whether something in it is being typed or dragged: new values leave it alone.
    var isBeingEdited: Bool { editing() }

    /// Whether the value is taller than one field: a box, numbers two by two, a text of
    /// several lines, an open matrix. Its title is then at its top (C-ATTR-12).
    var isTall: Bool { tallness() }
    var tallness: () -> Bool = { false }
    /// Called when `isTall` may have changed.
    var onTallChange: () -> Void = {}

    /// The name of the system colour the value is, for a colour (C-ATTR-22).
    var systemColorName: String?
    /// Why the value has no effect now, or nil (C-ATTR-21).
    private(set) var inactiveReason: String?
    /// Whether a change is on its way.
    private var isSending = false
    /// The tooltip when the value has an effect: a compound row's part names its attribute.
    var defaultToolTip: String? {
        didSet { if inactiveReason == nil { toolTip = defaultToolTip } }
    }

    /// The layer's size in the middle of an insets box.
    var showLayerSize: (String?) -> Void = { _ in }

    init(
        attribute: Attribute, isReadOnly: Bool = false,
        onSet: @escaping (AttributeValue?, _ continuous: Bool) -> Void = { _, _ in },
        onFinish: @escaping () -> Void = {}, colorPauseDelay: TimeInterval = 0.5,
        options: Options = Options()
    ) {
        kind = attribute.valueKind
        self.options = options
        self.isReadOnly = isReadOnly
        self.attribute = attribute
        title = AttributeText.title(attribute.title, id: attribute.id)
        value = attribute.value
        self.onSet = onSet
        self.onFinish = onFinish
        self.colorPauseDelay = colorPauseDelay
        super.init(frame: .zero)
        setAccessibilityIdentifier(isReadOnly ? Self.readOnlyIdentifier : Self.identifier)
        // Nothing sets it to nil (reported by the user): no button after the field, no menu.
        let content = makeContent(attribute)
        if isReadOnly { Self.makeReadOnly(content) }
        addContent(content)
        show(attribute.value)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// A row leaves its window when another layer is selected (its rows are built anew) or
    /// the panel closes. A colour panel still attached to its well would go on changing this
    /// attribute of the layer that was selected before: the well lets the panel go.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        hasLeftWindow = newWindow == nil && window != nil
        if hasLeftWindow { colorWell?.deactivate() }
    }

    /// Shows a value, keeping what is being typed or dragged. `systemColorName` names a
    /// colour that is one of UIKit's (C-ATTR-22).
    func show(_ value: AttributeValue?, systemColorName: String? = nil) {
        self.value = value
        self.systemColorName = systemColorName
        showValue(value)
        if isReadOnly { setAccessibilityValue(AttributeText.text(of: value)) }
    }

    /// Turns the controls below `view` into ones that only show (C-ATTR-04).
    private static func makeReadOnly(_ view: NSView) {
        switch view {
        case let number as NumberFieldView:
            number.makeReadOnly()
            return
        case let area as AttributeTextArea:
            area.makeReadOnly()
        case let field as AttributeEditField:
            field.isEditable = false
            field.textColor = .secondaryLabelColor
        case let box as NSBox where box.boxType == .custom:
            box.fillColor = .clear
        case let control as NSColorWell:
            control.isEnabled = false
        case let control as NSPopUpButton:
            control.isEnabled = false
        case let control as NSSegmentedControl:
            control.isEnabled = false
        default:
            break
        }
        for subview in view.subviews { makeReadOnly(subview) }
    }

    /// Why a value may not be sent, or nil (C-ATTR-13).
    func refusal(of value: AttributeValue?) -> String? {
        attribute.limitViolation(of: value).map { LimitText.message($0, kind: kind, unit: unit) }
    }

    /// Why each number of a value is outside its limit, or nil for each one within it.
    func outOfRangeReasons(of value: AttributeValue?) -> [String?] {
        let numbers = value?.numericComponents ?? []
        let outside = Set(attribute.componentsOutsideLimits(of: value))
        return numbers.indices.map { index in
            guard outside.contains(index), let limits = attribute.limits else { return nil }
            let violation = LimitViolation(
                component: numbers.count == 1 ? nil : index,
                reason: .outOfRange(limits.limit(forComponent: index)))
            return LimitText.message(violation, kind: kind, unit: unit)
        }
    }

    /// The unit numbers are read in (C-ATTR-20): a proportion's in percent, unless it is an
    /// integer.
    var unit: AttributeUnit {
        attribute.unit == .fraction && kind == .integer ? .unspecified : attribute.unit
    }

    /// Keeps the numbers' fields and the note they make.
    func track(_ numbers: [NumberFieldView]) {
        numberFields = numbers
        for number in numbers {
            number.onStateChange = { [weak self] in
                self?.updateNote()
                self?.updateFade()
            }
        }
    }

    /// Why what was typed is refused, while it is.
    private func updateNote() {
        note = numberFields.lazy.compactMap(\.refusal).first
    }

    /// Shows a spinner while a change is on its way, or a warning sign with the reason in its
    /// tooltip when it failed, at the end of the field that was changed. They float over the
    /// field, so the row keeps its size.
    func showStatus(sending: Bool, failure: String?) {
        let shown = activeBadge ?? badges.first
        for badge in badges where badge !== shown { badge.show(sending: false, failure: nil) }
        shown?.show(sending: sending, failure: failure)
        isSending = sending
        updateFade()
    }

    /// Fades the value, with the reason in the tooltip, or shows it plainly for nil
    /// (C-ATTR-21). Nothing is written beside it (user's decision, 2026-10-14).
    func showInactive(_ reason: String?) {
        guard reason != inactiveReason else { return }
        inactiveReason = reason
        toolTip = reason ?? defaultToolTip
        updateFade()
    }

    /// Faint while a change is on its way or the value has no effect, but never while it is
    /// typed in or its colour picked.
    private func updateFade() {
        let inUse = isBeingEdited || numberFields.contains(where: \.isFocused)
        alphaValue = inUse ? 1 : inactiveReason != nil ? 0.5 : isSending ? 0.7 : 1
    }

    /// The size of the layer, which an insets box shows in its middle (C-ATTR-22).
    func show(layerSize: String?) {
        showLayerSize(layerSize)
    }

    /// Whether a spinner shows. For tests.
    var isShowingSending: Bool { badges.contains(where: \.isShowingSpinner) }
    /// The reason a warning sign gives, if one shows. For tests.
    var failureText: String? { badges.lazy.compactMap(\.failureText).first }

    /// A badge for a field, kept for `showStatus`.
    func makeBadge() -> EditBadge {
        let badge = EditBadge()
        badges.append(badge)
        return badge
    }

    // MARK: - By kind

    private func makeContent(_ attribute: Attribute) -> NSView {
        switch attribute.valueKind {
        case .bool: return boolContent()
        case .integer, .double: return numberContent(isInteger: attribute.valueKind == .integer)
        case .string: return stringContent()
        case .color: return colorContent()
        case .insets: return insetsContent()
        case .point, .size, .rect: return componentsContent(attribute.valueKind)
        case .transform: return transformContent()
        case .enumeration: return enumContent(attribute.value)
        // References are never editable (P-ATTR-18).
        case .none, .references: return NSView()
        }
    }

    /// A checkbox with the attribute's title after it (C-ATTR-12): the row shows no title of
    /// its own.
    private func boolContent() -> NSView {
        let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(checkboxChanged(_:)))
            .accessibilityIdentifier(Self.checkboxIdentifier)
            .accessibilityLabel(title)
            .configure {
                $0.imagePosition = .imageOnly
                $0.controlSize = .small
                $0.isEnabled = !isReadOnly
            }
        showValue = { value in
            guard case .bool(let on) = value else { return checkbox.state = .off }
            checkbox.state = on ? .on : .off
        }
        let badge = makeBadge()
        return AttributeRowView.checkboxLine(checkbox, title: title, badge: badge)
    }

    @objc private func checkboxChanged(_ sender: NSButton) {
        activeBadge = nil
        onSet(.bool(sender.state == .on), false)
    }

    private func numberContent(isInteger: Bool) -> NSView {
        let number = NumberFieldView(
            letter: options.letter, isInteger: isInteger, name: title, unit: unit, showsUnit: options.showsUnit)
        if options.negativeIsNone { number.field.placeholderString = "—" }
        let negativeIsNone = options.negativeIsNone
        badges.append(number.badge)
        // The badge, not the number: the number keeps this closure (C-SCALE-02).
        let badge = number.badge
        func value(_ number: Double) -> AttributeValue? {
            guard isInteger else { return .double(number) }
            return Int64(exactly: number).map { .integer($0) }
        }
        number.onSet = { [weak self] number in
            self?.activeBadge = badge
            guard let value = value(number) else { return }
            self?.onSet(value, false)
        }
        number.check = { [weak self] number in self?.refusal(of: value(number)) }
        track([number])
        showValue = { [weak self] value in
            let reason = self?.outOfRangeReasons(of: value).first.flatMap { $0 }
            switch value {
            case .integer(let integer) where negativeIsNone && integer < 0: number.show(nil)
            case .double(let double) where negativeIsNone && double < 0: number.show(nil)
            case .integer(let integer): number.show(Double(integer), outOfRange: reason)
            case .double(let double): number.show(double, outOfRange: reason)
            default: number.show(nil)
            }
        }
        editing = { number.isBeingEdited }
        return number
    }

    /// A text of several lines (AttributeTextArea).
    private func stringContent() -> NSView {
        let area = AttributeTextArea(name: title)
        tallness = { [weak area] in area?.isTall ?? false }
        area.onHeightChange = { [weak self] in self?.onTallChange() }
        let badge = makeBadge()
        area.onCommit = { [weak self] text in
            guard let self else { return }
            self.activeBadge = badge
            // An empty field sends an empty string, not nil (C-ATTR-05); an attribute that is
            // nil and stays empty sends nothing.
            if self.value == nil, text.isEmpty { return }
            guard self.value != .string(text) else { return }
            self.onSet(.string(text), false)
        }
        showValue = { value in
            // An empty text is not none: only none says so (C-ATTR-02).
            area.showsNone = value == nil
            guard case .string(let string) = value else { return area.shownText = "" }
            area.shownText = string
        }
        editing = { area.isBeingEdited }
        let box = Self.fieldBox()
        box.contentView?.addContent(area)
        return box.overlay(alignment: .topTrailing, offset: CGPoint(x: -4, y: 3)) { badge }
    }

    /// Binds the numbers to the components of the value, in their order: each sends the
    /// value with its own component changed and the others as shown, checks it the same way,
    /// and is shown its component with whether it is outside its limits. `fallback` stands
    /// for the components while there is no value, `value` makes the value from them.
    func bindComponents(
        _ numbers: [NumberFieldView], fallback: [Double],
        value: @escaping ([Double]) -> AttributeValue?
    ) {
        badges += numbers.map(\.badge)
        for (index, number) in numbers.enumerated() {
            // The badge, not the number: the number keeps this closure (C-SCALE-02).
            let badge = number.badge
            let changed = { [weak self] (component: Double) -> AttributeValue? in
                var components = AttributeValueEditing.components(of: self?.value) ?? fallback
                components[index] = component
                return value(components)
            }
            number.onSet = { [weak self] component in
                guard let self else { return }
                self.activeBadge = badge
                self.onSet(changed(component), false)
            }
            number.check = { [weak self] component in self?.refusal(of: changed(component)) }
        }
        track(numbers)
        showValue = { [weak self] value in
            let components = AttributeValueEditing.components(of: value)
            let reasons = self?.outOfRangeReasons(of: value) ?? []
            for (index, number) in numbers.enumerated() {
                number.show(components?[index], outOfRange: reasons.indices.contains(index) ? reasons[index] : nil)
            }
        }
        editing = { numbers.contains(where: \.isBeingEdited) }
    }

    /// `bindComponents` with `count` zeros for the components while there is no value.
    func bindComponents(
        _ numbers: [NumberFieldView], zeros count: Int,
        value: @escaping ([Double]) -> AttributeValue?
    ) {
        bindComponents(numbers, fallback: Array(repeating: 0, count: count), value: value)
    }

    private static let letters: [AttributeValueKind: [String]] = [
        .point: ["X", "Y"], .size: ["W", "H"], .rect: ["X", "Y", "W", "H"],
        .insets: ["T", "L", "B", "R"],
    ]

    private func componentsContent(_ kind: AttributeValueKind) -> NSView {
        let letters = options.letters ?? Self.letters[kind] ?? []
        let numbers = letters.map {
            NumberFieldView(
                letter: $0, isInteger: false, name: localized("attributes.editor.component", title, $0),
                unit: unit, showsUnit: false)
        }
        bindComponents(numbers, zeros: letters.count) { AttributeValueEditing.value(kind, $0) }
        // All in one row: a rect's four under their title (C-ATTR-12), a point's and a size's
        // two beside it; or two by two in a compound row (C-ATTR-19).
        if options.grid, numbers.count == 4 {
            tallness = { true }
            return VStack(alignment: .fill, spacing: 4) {
                for pair in [numbers[0..<2], numbers[2..<4]] {
                    HStack(alignment: .center, spacing: 4) {
                        for number in pair { number }
                    }
                    .distribution(.fillEqually)
                }
            }
        }
        return HStack(alignment: .center, spacing: 4) {
            for number in numbers { number }
        }
        .distribution(.fillEqually)
    }

    private func transformContent() -> NSView {
        let numbers = (0..<16).map { _ in
            NumberFieldView(
                letter: nil, isInteger: false, name: localized("attributes.editor.entry", title))
        }
        bindComponents(numbers, fallback: AttributeValueEditing.entries(of: .identity)) {
            .transform(AttributeValueEditing.transform($0))
        }
        let grid = VStack(alignment: .fill, spacing: 4) {
            for row in 0..<4 {
                HStack(alignment: .center, spacing: 4) {
                    for number in numbers[(row * 4)..<(row * 4 + 4)] { number }
                }
                .distribution(.fillEqually)
            }
        }
        let summary = NSTextField(labelWithString: "")
        let chevron = NSImageView()
        disclosureAction = { [weak self, weak grid, weak chevron] in
            guard let grid, let chevron else { return }
            grid.isHidden.toggle()
            chevron.image = Self.chevron(open: !grid.isHidden)
            self?.onTallChange()
        }
        tallness = { [weak grid] in grid.map { !$0.isHidden } ?? false }
        let showEntries = showValue
        showValue = { value in
            showEntries(value)
            summary.stringValue = switch value {
            case .transform(let transform): AttributeText.summary(of: transform)
            default: localized("attributes.value.none")
            }
        }
        let disclosure = NSButton()
            .title("")
            .configure {
                $0.isBordered = false
                $0.target = self
                $0.action = #selector(toggleMatrix(_:))
                $0.addContent(HStack(alignment: .center) {
                    summary
                        .font(.systemFont(ofSize: 12))
                        .textColor(.secondaryLabelColor)
                    Spacer()
                    chevron
                        .image(Self.chevron(open: false))
                        .contentTintColor(.tertiaryLabelColor)
                }
                .padding(horizontal: 7, vertical: 0))
            }
        let box = Self.fieldBox()
        box.contentView?.addContent(VStack(alignment: .fill) {
            disclosure
                .accessibilityIdentifier(Self.disclosureIdentifier)
                .accessibilityLabel(localized("attributes.editor.showMatrix"))
        })
        return VStack(alignment: .fill, spacing: 4) {
            box.frame(height: Self.fieldHeight)
            grid.isHidden(true)
        }
    }

    private static func chevron(open: Bool) -> NSImage? {
        Theme.symbol(open ? "chevron.down" : "chevron.right", size: 9, weight: .bold)
    }

    @objc private func toggleMatrix(_ sender: Any?) {
        disclosureAction()
    }

    /// The rounded box a field sits in: the faintest fill and a hairline, as in the design.
    static func fieldBox() -> NSBox {
        NSBox().configure {
            $0.boxType = .custom
            $0.borderWidth = 0.5
            $0.borderColor = .separatorColor
            $0.cornerRadius = 5
            $0.fillColor = .quaternarySystemFill
            $0.contentViewMargins = .zero
            $0.titlePosition = .noTitle
        }
    }
}
