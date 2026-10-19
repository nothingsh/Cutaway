import AppKit
import CutawayModel
import CutawayWire
import DeclarativeAppKit

/// What shows one attribute in the list and is updated in place (C-ATTR-06): a row of its own,
/// or a part of a compound row (C-ATTR-19).
@MainActor
protocol AttributeCell: AnyObject {
    func show(_ value: AttributeValue?, names: ValueNames)
    func show(sending: Bool, failure: String?)
    func showInactive(_ reason: String?)
    func show(layerSize: String?)
}

/// A row of the list that a filter keeps or hides (C-ATTR-14): an attribute's own row, or a
/// compound one.
@MainActor
protocol AttributeListRow: NSView {
    /// What it is called: the attribute's title, or the compound row's.
    var title: String { get }
    /// How many attributes it shows: what the counts add up.
    var attributeCount: Int { get }
    func matches(_ filter: String) -> Bool
    func highlight(_ filter: String?)
}

extension AttributeRowView: AttributeCell, AttributeListRow {
    var attributeCount: Int { 1 }
}

/// Changes an attribute: sends a value, as it goes or once, and ends a change that went on.
struct AttributeSender {
    var set: (AttributeValue?, _ continuous: Bool) -> Void
    var finish: () -> Void
}

/// A part of a compound row that is an attribute editor, editable or read-only.
@MainActor
final class EditorPart: AttributeCell {
    let editor: AttributeEditorView

    init(_ editor: AttributeEditorView) {
        self.editor = editor
    }

    func show(_ value: AttributeValue?, names: ValueNames) {
        editor.show(value, names: names)
    }

    func show(sending: Bool, failure: String?) {
        editor.showStatus(sending: sending, failure: failure)
    }

    func showInactive(_ reason: String?) {
        editor.showInactive(reason)
    }

    func show(layerSize: String?) {
        editor.show(layerSize: layerSize)
    }
}

/// A boolean as a small button (C-ATTR-19), drawn as in the design: a chip that is filled with
/// the accent when on, a chip that names the current mode, a chip that says whether something
/// is wrong, or the eye of the `visibility` cluster. A click sends the other value; one that
/// cannot be changed does nothing and looks the same.
final class BoolToggle: NSView, AttributeCell {
    static let identifier = "attributes.compound.toggle"

    enum Style {
        /// `title`, on an accent fill when on.
        case chip(String)
        /// The mode it is in, always as a chip that is on: "Autoresizing" or "Constraints".
        case mode(on: String, off: String)
        /// "✓ Unambiguous" in green when off, "Ambiguous" in orange when on.
        case check(on: String, off: String)
        /// The eye of Hidden: open when off, struck through when on.
        case eye
    }

    let style: Style
    let badge = EditBadge()
    private let label = NSTextField(labelWithString: "")
    private let image = NSImageView()
    private let sender: AttributeSender?
    private(set) var isOn = false
    /// Whether a click changes it.
    var isEnabled: Bool { sender != nil }
    /// Called after a new value is shown.
    var onChange: () -> Void = {}

    init(style: Style, name: String, sender: AttributeSender?) {
        self.style = style
        self.sender = sender
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderColor = NSColor.separatorColor.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(name)
        setAccessibilityIdentifier(Self.identifier)
        label.font = .systemFont(ofSize: 11.5)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)
        if case .eye = style {
            layer?.cornerRadius = 5
            addContent(image)
            NSLayoutConstraint.activate([
                widthAnchor.constraint(equalToConstant: 24),
                heightAnchor.constraint(equalToConstant: AttributeEditorView.fieldHeight),
            ])
        } else {
            layer?.cornerRadius = AttributeEditorView.fieldHeight / 2
            addContent(HStack(alignment: .center) { label }
                .padding(horizontal: 8, vertical: 0))
            heightAnchor.constraint(equalToConstant: AttributeEditorView.fieldHeight).isActive = true
        }
        addSubview(badge)
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.leadingAnchor.constraint(equalTo: trailingAnchor, constant: 2),
        ])
        apply()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func mouseDown(with event: NSEvent) {
        click()
    }

    override func accessibilityPerformPress() -> Bool {
        click()
        return isEnabled
    }

    /// Sends the other value, if it can be changed.
    func click() {
        sender?.set(.bool(!isOn), false)
    }

    /// What it says now. For tests.
    var shownTitle: String { label.stringValue }

    func show(_ value: AttributeValue?, names: ValueNames) {
        guard case .bool(let on) = value else { return }
        isOn = on
        apply()
        onChange()
    }

    func show(sending: Bool, failure: String?) {
        badge.show(sending: sending, failure: failure)
    }

    func showInactive(_ reason: String?) {
        alphaValue = reason == nil ? 1 : 0.5
        toolTip = reason
    }

    func show(layerSize: String?) {}

    override func updateLayer() {
        super.updateLayer()
        layer?.borderColor = NSColor.separatorColor.cgColor
        apply()
    }

    private func apply() {
        var fill = NSColor.quaternarySystemFill
        var border: CGFloat = 0.5
        switch style {
        case .chip(let title):
            label.stringValue = title
            if isOn {
                fill = .controlAccentColor.withAlphaComponent(0.15)
                border = 0
            }
            label.textColor = isOn ? .controlAccentColor : .secondaryLabelColor
        case .mode(let on, let off):
            label.stringValue = isOn ? on : off
            fill = .controlAccentColor.withAlphaComponent(0.15)
            border = 0
            label.textColor = .controlAccentColor
        case .check(let on, let off):
            label.stringValue = isOn ? on : "✓ " + off
            label.textColor = isOn ? .systemOrange : .systemGreen
        case .eye:
            image.image = Theme.symbol(isOn ? "eye.slash" : "eye", size: 13, weight: .regular)
            image.contentTintColor = isOn ? .tertiaryLabelColor : .labelColor
        }
        layer?.backgroundColor = fill.cgColor
        layer?.borderWidth = border
        setAccessibilityValue(isOn)
    }
}

/// The opacity of the `visibility` cluster (C-ATTR-19): a slider beside the number. The slider
/// is there only when the opacity has both ends; dragging it sends as it goes, as the colour
/// panel does (C-ATTR-07), and the drag is one step to undo (C-ATTR-08).
final class OpacityPart: NSView, AttributeCell {
    static let sliderIdentifier = "attributes.compound.slider"

    let editor: AttributeEditorView
    let slider: NSSlider?
    private let sender: AttributeSender?
    private var isDragging = false

    init(attribute: Attribute, editor: AttributeEditorView, sender: AttributeSender?) {
        self.editor = editor
        self.sender = sender
        let limit = attribute.limits?.limit(forComponent: 0)
        if attribute.valueKind == .double, let minimum = limit?.minimum, let maximum = limit?.maximum,
           minimum < maximum
        {
            slider = NSSlider(value: minimum, minValue: minimum, maxValue: maximum, target: nil, action: nil)
        } else {
            slider = nil
        }
        super.init(frame: .zero)
        if let slider {
            slider.target = self
            slider.action = #selector(slid(_:))
            slider.isContinuous = true
            slider.controlSize = .small
            slider.isEnabled = sender != nil
            slider.setAccessibilityIdentifier(Self.sliderIdentifier)
            slider.setAccessibilityLabel(editor.title)
        }
        let slider = slider
        addHStack(alignment: .center, spacing: 6) {
            if let slider { slider }
            editor
                .frame(width: CompoundRowView.compactWidth)
            if slider == nil { Spacer() }
        }
        show(attribute.value, names: .none)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Sends as the slider moves; the mouse going up ends the change. A move by the keyboard
    /// is a change of its own.
    @objc func slid(_ sender: NSSlider) {
        let type = NSApp.currentEvent?.type
        let value = AttributeValue.double(sender.doubleValue)
        switch type {
        case .leftMouseDown, .leftMouseDragged:
            isDragging = true
            self.sender?.set(value, true)
        case .leftMouseUp:
            isDragging = false
            self.sender?.set(value, true)
            self.sender?.finish()
        default:
            self.sender?.set(value, false)
        }
    }

    func show(_ value: AttributeValue?, names: ValueNames) {
        editor.show(value, names: names)
        if !isDragging, case .double(let double) = value, double.isFinite {
            slider?.doubleValue = double
        }
    }

    func show(sending: Bool, failure: String?) {
        editor.showStatus(sending: sending, failure: failure)
    }

    func showInactive(_ reason: String?) {
        editor.showInactive(reason)
    }

    func show(layerSize: String?) {}
}
