import AppKit
import CutawayModel
import CutawayWire
import DeclarativeAppKit

/// The editor of one attribute, by the kind of its value (C-ATTR-05): a switch, a number, a
/// text, a colour, numbers by component, a matrix or a menu of cases. It is built for one kind
/// and shows new values in place (`show(_:)`), leaving alone what is being typed or dragged.
/// Nothing here depends on the attribute's ID (C-ATTR-03).
final class AttributeEditorView: NSView {
    static let identifier = "attributes.editor"
    static let fieldIdentifier = "attributes.editor.field"
    static let handleIdentifier = "attributes.editor.handle"
    static let switchIdentifier = "attributes.editor.switch"
    static let wellIdentifier = "attributes.editor.well"
    static let hexIdentifier = "attributes.editor.hex"
    static let popUpIdentifier = "attributes.editor.popup"
    static let disclosureIdentifier = "attributes.editor.disclosure"
    static let spinnerIdentifier = "attributes.editor.spinner"
    static let failureIdentifier = "attributes.editor.failure"
    static let fieldHeight: CGFloat = 22
    /// Transparent black, which an emptied hex field sends and which shows as "None".
    static let transparent = Color(red: 0, green: 0, blue: 0, alpha: 0)

    let kind: AttributeValueKind
    /// The attribute's title, which names its controls for accessibility.
    let title: String
    private(set) var value: AttributeValue?
    private let onSet: (AttributeValue?, _ continuous: Bool) -> Void
    private let onFinish: () -> Void
    private var showValue: (AttributeValue?) -> Void = { _ in }
    private var editing: () -> Bool = { false }
    /// How long the colour panel stays still before a change of colour counts as finished.
    private let colorPauseDelay: TimeInterval
    private var colorPause: DispatchWorkItem?
    /// The colour well, for a colour. The colour panel sends to it while it is active.
    private weak var colorWell: NSColorWell?
    /// Set once the editor has left its window: the panel moving then changes nothing.
    private var hasLeftWindow = false
    /// Where a change of this attribute shows: the field changed last, or the first one.
    private var badges: [EditBadge] = []
    private var activeBadge: EditBadge?
    /// Opens or closes the matrix of a transform.
    private var disclosureAction: () -> Void = {}
    /// The cases of an enum and their raw values, as the app last gave them (P-ATTR-07).
    private var cases: [String] = []
    private var caseValues: [Int64] = []

    /// Whether something in it is being typed or dragged: new values leave it alone.
    var isBeingEdited: Bool { editing() }

    init(
        attribute: Attribute, onSet: @escaping (AttributeValue?, _ continuous: Bool) -> Void,
        onFinish: @escaping () -> Void, colorPauseDelay: TimeInterval = 0.5
    ) {
        kind = attribute.valueKind
        title = AttributeText.title(attribute.title, id: attribute.id)
        value = attribute.value
        self.onSet = onSet
        self.onFinish = onFinish
        self.colorPauseDelay = colorPauseDelay
        super.init(frame: .zero)
        setAccessibilityIdentifier(Self.identifier)
        // Nothing sets it to nil (reported by the user): no button after the field, no menu.
        addContent(makeContent(attribute))
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

    /// Shows a value, keeping what is being typed or dragged.
    func show(_ value: AttributeValue?) {
        self.value = value
        showValue(value)
    }

    /// Shows a spinner while a change is on its way, or a warning sign with the reason in its
    /// tooltip when it failed, at the end of the field that was changed. They float over the
    /// field, so the row keeps its size.
    func showStatus(sending: Bool, failure: String?) {
        let shown = activeBadge ?? badges.first
        for badge in badges where badge !== shown { badge.show(sending: false, failure: nil) }
        shown?.show(sending: sending, failure: failure)
    }

    /// Whether a spinner shows. For tests.
    var isShowingSending: Bool { badges.contains(where: \.isShowingSpinner) }
    /// The reason a warning sign gives, if one shows. For tests.
    var failureText: String? { badges.lazy.compactMap(\.failureText).first }

    /// A badge for a field, kept for `showStatus`.
    private func makeBadge() -> EditBadge {
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
        case .point, .size, .rect, .insets: return componentsContent(attribute.valueKind)
        case .transform: return transformContent()
        case .enumeration: return enumContent()
        case .none: return NSView()
        }
    }

    private func boolContent() -> NSView {
        let toggle = NSSwitch()
            .controlSize(.mini)
            .accessibilityIdentifier(Self.switchIdentifier)
            .accessibilityLabel(title)
            .configure {
                $0.target = self
                $0.action = #selector(switchChanged(_:))
            }
        showValue = { value in
            guard case .bool(let on) = value else { return toggle.state = .off }
            toggle.state = on ? .on : .off
        }
        let badge = makeBadge()
        return HStack(alignment: .center, spacing: 6) {
            toggle
            badge
            Spacer()
        }
        .frame(height: Self.fieldHeight)
    }

    @objc private func switchChanged(_ sender: NSSwitch) {
        activeBadge = nil
        onSet(.bool(sender.state == .on), false)
    }

    private func numberContent(isInteger: Bool) -> NSView {
        let number = NumberFieldView(letter: nil, isInteger: isInteger, name: title)
        badges.append(number.badge)
        // The badge, not the number: the number keeps this closure (C-SCALE-02).
        let badge = number.badge
        number.onSet = { [weak self] value, continuous in
            self?.activeBadge = badge
            if isInteger {
                guard let integer = Int64(exactly: value) else { return }
                self?.onSet(.integer(integer), continuous)
            } else {
                self?.onSet(.double(value), continuous)
            }
        }
        showValue = { value in
            switch value {
            case .integer(let integer): number.show(Double(integer))
            case .double(let double): number.show(double)
            default: number.show(nil)
            }
        }
        editing = { number.isBeingEdited }
        return number
    }

    private func stringContent() -> NSView {
        let field = AttributeEditField(digits: false)
            .accessibilityLabel(title)
        let badge = makeBadge()
        field.onCommit = { [weak self] text in
            guard let self else { return }
            self.activeBadge = badge
            // An empty field sends an empty string, not nil (C-ATTR-05); an attribute that is
            // nil and stays empty sends nothing.
            if self.value == nil, text.isEmpty { return }
            guard self.value != .string(text) else { return }
            self.onSet(.string(text), false)
        }
        showValue = { value in
            guard case .string(let string) = value else { return field.shownText = "" }
            field.shownText = string
        }
        editing = { field.isBeingEdited }
        return Self.box(around: field, badge: badge)
    }

    private func colorContent() -> NSView {
        let well = NSColorWell(style: .minimal)
            .accessibilityIdentifier(Self.wellIdentifier)
            .accessibilityLabel(title)
            .configure {
                $0.isContinuous = true
                $0.target = self
                $0.action = #selector(colorChanged(_:))
            }
        colorWell = well
        let hex = AttributeEditField()
            .accessibilityIdentifier(Self.hexIdentifier)
            .accessibilityLabel(localized("attributes.editor.hexadecimal", title))
        let badge = makeBadge()
        hex.onCommit = { [weak self, weak hex] text in
            guard let self, let hex else { return }
            self.activeBadge = badge
            // An emptied field clears the colour to transparent: the panel's "no colour" swatch
            // has no public switch. A colour that is nil stays nil (C-ATTR-05).
            let cleared = text.trimmingCharacters(in: .whitespaces).isEmpty
            if cleared, self.value == nil { return hex.revert() }
            guard let color = cleared ? Self.transparent : AttributeValueEditing.color(fromHex: text),
                  self.value != .color(color)
            else {
                return hex.revert()
            }
            self.onSet(.color(color), false)
        }
        showValue = { value in
            // No colour and transparent black show alike: a transparent well, and "None".
            guard case .color(let color) = value, color != Self.transparent else {
                well.color = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
                return hex.shownText = ""
            }
            well.color = NSColor(
                colorSpace: .extendedSRGB,
                components: [color.red, color.green, color.blue, color.alpha].map { CGFloat($0) },
                count: 4)
            // A colour beyond sRGB has no hex code; its components are shown instead.
            hex.shownText = AttributeValueEditing.hexRGBA(of: color)
                ?? AttributeText.text(of: value)
        }
        editing = { [weak self] in hex.isBeingEdited || self?.colorPause != nil }
        return HStack(alignment: .center, spacing: 6) {
            well
                .frame(width: 26, height: 18)
            Self.box(around: hex, badge: badge)
        }
    }

    /// The colour well or its panel moves: sent as it goes, and finished once it is still a
    /// moment (C-ATTR-07, C-ATTR-08).
    @objc func colorChanged(_ sender: NSColorWell) {
        guard !hasLeftWindow, let color = Self.color(of: sender.color) else { return }
        activeBadge = badges.first
        onSet(.color(color), true)
        colorPause?.cancel()
        // The change ends even when this editor is gone by then (another layer was selected):
        // a change left open would show as sending, and record no undo.
        let finish = onFinish
        let work = DispatchWorkItem { [weak self] in
            self?.colorPause = nil
            finish()
        }
        colorPause = work
        DispatchQueue.main.asyncAfter(deadline: .now() + colorPauseDelay, execute: work)
    }

    private static let letters: [AttributeValueKind: [String]] = [
        .point: ["X", "Y"], .size: ["W", "H"], .rect: ["X", "Y", "W", "H"],
        .insets: ["T", "L", "B", "R"],
    ]

    private func componentsContent(_ kind: AttributeValueKind) -> NSView {
        let letters = Self.letters[kind] ?? []
        let numbers = letters.map {
            NumberFieldView(letter: $0, isInteger: false, name: localized("attributes.editor.component", title, $0))
        }
        badges += numbers.map(\.badge)
        for (index, number) in numbers.enumerated() {
            // The badge, not the number: the number keeps this closure (C-SCALE-02).
            let badge = number.badge
            number.onSet = { [weak self] component, continuous in
                guard let self else { return }
                self.activeBadge = badge
                var components = AttributeValueEditing.components(of: self.value)
                    ?? Array(repeating: 0, count: letters.count)
                components[index] = component
                self.onSet(AttributeValueEditing.value(kind, components), continuous)
            }
        }
        showValue = { value in
            let components = AttributeValueEditing.components(of: value)
            for (index, number) in numbers.enumerated() { number.show(components?[index]) }
        }
        editing = { numbers.contains(where: \.isBeingEdited) }
        return VStack(alignment: .fill, spacing: 4) {
            for line in stride(from: 0, to: numbers.count, by: 2) {
                HStack(alignment: .center, spacing: 4) {
                    for number in numbers[line..<min(line + 2, numbers.count)] { number }
                }
                .distribution(.fillEqually)
            }
        }
    }

    private func transformContent() -> NSView {
        let numbers = (0..<16).map { _ in
            NumberFieldView(
                letter: nil, isInteger: false, name: localized("attributes.editor.entry", title), showsHandle: false)
        }
        badges += numbers.map(\.badge)
        for (index, number) in numbers.enumerated() {
            // The badge, not the number: the number keeps this closure (C-SCALE-02).
            let badge = number.badge
            number.onSet = { [weak self] entry, continuous in
                guard let self else { return }
                self.activeBadge = badge
                var entries = AttributeValueEditing.components(of: self.value)
                    ?? AttributeValueEditing.entries(of: .identity)
                entries[index] = entry
                self.onSet(.transform(AttributeValueEditing.transform(entries)), continuous)
            }
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
        disclosureAction = { [weak grid, weak chevron] in
            guard let grid, let chevron else { return }
            grid.isHidden.toggle()
            chevron.image = Self.chevron(open: !grid.isHidden)
        }
        showValue = { value in
            let entries = AttributeValueEditing.components(of: value)
            for (index, number) in numbers.enumerated() { number.show(entries?[index]) }
            summary.stringValue = switch value {
            case .transform(.identity): localized("attributes.value.identity")
            case nil: localized("attributes.value.none")
            default: localized("attributes.value.matrix")
            }
        }
        editing = { numbers.contains(where: \.isBeingEdited) }
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

    private func enumContent() -> NSView {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
            .controlSize(.small)
            .font(.systemFont(ofSize: 12))
            .accessibilityIdentifier(Self.popUpIdentifier)
            .accessibilityLabel(title)
            .configure {
                $0.target = self
                $0.action = #selector(caseChosen(_:))
            }
        showValue = { [weak self] value in
            guard let self, case .enumeration(let enumeration) = value else { return }
            // A value on its way carries its raw value alone (P-SET-02): the cases stay as
            // the app last gave them.
            if !enumeration.cases.isEmpty, enumeration.caseValues.count == enumeration.cases.count {
                self.cases = enumeration.cases
                self.caseValues = enumeration.caseValues
            }
            if popUp.itemTitles != self.cases {
                popUp.removeAllItems()
                popUp.addItems(withTitles: self.cases)
            }
            if let index = self.caseValues.firstIndex(of: enumeration.value) {
                popUp.selectItem(at: index)
            } else {
                popUp.select(nil)
            }
        }
        let badge = makeBadge()
        return HStack(alignment: .center, spacing: 6) {
            popUp
            badge
            Spacer()
        }
    }

    /// Sends the chosen case by its raw value only (P-SET-02).
    @objc func caseChosen(_ sender: NSPopUpButton) {
        guard case .enumeration(let enumeration) = value,
              caseValues.indices.contains(sender.indexOfSelectedItem)
        else { return }
        let raw = caseValues[sender.indexOfSelectedItem]
        guard raw != enumeration.value else { return }
        activeBadge = nil
        onSet(.enumeration(EnumValue(value: raw, cases: [], caseName: nil)), false)
    }

    // MARK: - Values

    /// A colour as sent: sRGB, not premultiplied (P-ATTR-04). Components outside 0 to 1 go
    /// as they are; the app clamps them.
    static func color(of color: NSColor) -> Color? {
        guard let srgb = color.usingColorSpace(.extendedSRGB) else { return nil }
        return Color(
            red: Float(srgb.redComponent), green: Float(srgb.greenComponent),
            blue: Float(srgb.blueComponent), alpha: Float(srgb.alphaComponent))
    }

    /// A text field in its box, in the middle of it, with its badge floating at the end.
    private static func box(around field: NSTextField, badge: EditBadge) -> NSView {
        let box = fieldBox()
        box.contentView?.addHStack(alignment: .center) { field }
            .padding(horizontal: 7, vertical: 0)
        return box
            .frame(height: fieldHeight)
            .overlay(alignment: .trailing, offset: CGPoint(x: -4, y: 0)) { badge }
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
