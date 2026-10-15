import AppKit
import CutawayModel
import CutawayWire
import DeclarativeAppKit

/// What a compound row is built with: the editor of a part, editable when the attribute can
/// be changed, and what changes an attribute, nil when it cannot be.
struct CompoundFactory {
    var editor: (Attribute, AttributeEditorView.Options) -> AttributeEditorView
    var sender: (Attribute) -> AttributeSender?
}

/// The attributes of one cluster in one row (C-ATTR-19): lines of a label in the title column
/// and the parts beside it, the first line's label the row's title. Each part is an attribute's
/// own editor, so editing, sending, undo and range checks are the attribute's (C-ATTR-04 to 08,
/// C-ATTR-13). A part that is missing is not drawn.
///
/// The labels are the panel's own, by the cluster's and the slots' names; a part's tooltip
/// gives the attribute's title and ID. A filter keeps the row when its labels, or a member's
/// title or ID, hold it (C-ATTR-14).
final class CompoundRowView: NSView, AttributeListRow {
    static let identifier = "attributes.compound"
    static let lineLabelIdentifier = "attributes.compound.label"

    let row: AttributeClusters.Row
    let title: String
    /// One cell for each member, in the order the members came (C-ATTR-06).
    private(set) var cells: [(attribute: Attribute, cell: any AttributeCell)] = []
    private let titleField: WrappingTitleField
    private var labels: [String] = []
    private var values: [String: AttributeValue?] = [:]
    private var views: [String: NSView] = [:]
    private let stack = VStack(alignment: .fill, spacing: 4) {}
    private lazy var noteLabel = NSTextField(wrappingLabelWithString: "")
        .font(.systemFont(ofSize: 11))
        .accessibilityIdentifier(AttributeRowView.noteIdentifier)
        .isHidden(true)
    var attributeCount: Int { row.attributes.count }

    init(_ row: AttributeClusters.Row, factory: CompoundFactory) {
        self.row = row
        title = Self.title(of: row)
        titleField = WrappingTitleField(title: title)
        titleField.widthIsGiven = true
        super.init(frame: .zero)
        setAccessibilityIdentifier(Self.identifier)
        for slot in row.order {
            guard let attribute = row[slot] else { continue }
            let (view, cell) = makePart(slot, attribute, factory)
            views[slot] = view
            values[slot] = attribute.value
            if let editor = view as? AttributeEditorView {
                editor.defaultToolTip = Self.tip(of: attribute)
            } else {
                view.toolTip = Self.tip(of: attribute)
            }
            cell.show(attribute.value, systemColorName: attribute.systemColorName)
            cells.append((attribute, ForwardingCell(cell) { [weak self] value in
                self?.values[slot] = value
                self?.refresh()
            }))
        }
        for slot in Self.compactSlots[row.kind] ?? [] {
            if let view = views[slot] { compact.insert(ObjectIdentifier(view)) }
        }
        if let clip = views["clip"], row.kind == .corners { hugs.insert(ObjectIdentifier(clip)) }
        build()
        addVStack(alignment: .fill, spacing: 2) {
            stack
            noteLabel
        }
        .padding(top: 3, leading: Theme.Spacing.large, bottom: 3, trailing: Theme.Spacing.large)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Parts

    /// The single numbers that sit beside other parts at `compactWidth`.
    private static let compactSlots: [AttributeClusters.Kind: [String]] = [
        .corners: ["radius"], .border: ["width"], .shadow: ["opacity"], .font: ["size"],
        .lines: ["count"],
    ]

    /// The title of a row: the cluster's, or "Visible" for a `visibility` of Hidden alone.
    static func title(of row: AttributeClusters.Row) -> String {
        switch row.kind {
        case .visibility:
            if row["opacity"] == nil {
                localized("attributes.cluster.visible")
            } else {
                localized("attributes.cluster.opacity")
            }
        case .corners: localized("attributes.cluster.corners")
        case .border: localized("attributes.cluster.border")
        case .shadow: localized("attributes.cluster.shadow")
        case .geometry:
            geometryLabel(
                ["frame", "position", "anchor", "bounds", "zPosition", "transform"]
                    .first { row[$0] != nil } ?? "frame")
        case .sizing: ""
        case .autoLayout: localized("attributes.cluster.autoLayout")
        case .font: localized("attributes.cluster.font")
        case .lines: localized("attributes.cluster.lines")
        case .state: localized("attributes.cluster.state")
        case .scrolling: localized("attributes.cluster.scrolling")
        }
    }

    /// "Border Width (layer.borderWidth)".
    private static func tip(of attribute: Attribute) -> String {
        let title = AttributeText.title(attribute.title, id: attribute.id)
        guard let id = attribute.id, id != title else { return title }
        return "\(title) (\(id))"
    }

    private func makePart(
        _ slot: String, _ attribute: Attribute, _ factory: CompoundFactory
    ) -> (NSView, any AttributeCell) {
        let name = AttributeText.title(attribute.title, id: attribute.id)
        func editor(_ options: AttributeEditorView.Options = .init()) -> AttributeEditorView {
            let editor = factory.editor(attribute, options)
            editor.onNote = { [weak self] note in self?.show(note, of: name) }
            return editor
        }
        func toggle(_ style: BoolToggle.Style) -> (NSView, any AttributeCell) {
            let toggle = BoolToggle(style: style, name: name, sender: factory.sender(attribute))
            return (toggle, toggle)
        }
        func plain(_ options: AttributeEditorView.Options = .init()) -> (NSView, any AttributeCell) {
            let view = editor(options)
            return (view, EditorPart(view))
        }
        switch (row.kind, slot) {
        case (.visibility, "hidden"): return toggle(.eye)
        case (.visibility, "opacity"):
            let part = OpacityPart(
                attribute: attribute, editor: editor(), sender: factory.sender(attribute))
            return (part, part)
        case (.corners, "clip"):
            var clip = attribute
            clip.title = localized("attributes.cluster.clip")
            let view = factory.editor(clip, .init())
            return (view, EditorPart(view))
        case (.autoLayout, "autoresizing"):
            return toggle(.mode(
                on: localized("attributes.cluster.autoresizing"), off: localized("attributes.cluster.constraints")))
        case (.autoLayout, "ambiguous"):
            let toggle = BoolToggle(
                style: .check(
                    on: localized("attributes.cluster.ambiguous"), off: localized("attributes.cluster.unambiguous")),
                name: name, sender: nil)
            return (toggle, toggle)
        case (.state, _), (.scrolling, _):
            return toggle(.chip(Self.chipTitle(slot)))
        case (.shadow, "radius"): return plain(.init(letter: "B"))
        case (.shadow, "offset"): return plain(.init(letters: ["X", "Y"]))
        case (.geometry, "frame"), (.geometry, "bounds"): return plain(.init(grid: true))
        case (.sizing, let slot) where slot.hasPrefix("intrinsic."):
            return plain(.init(negativeIsNone: true, showsUnit: false))
        case (.sizing, _): return plain(.init(showsUnit: false))
        default: return plain()
        }
    }

    private static func chipTitle(_ slot: String) -> String {
        switch slot {
        case "enabled": localized("attributes.cluster.enabled")
        case "selected": localized("attributes.cluster.selected")
        case "highlighted": localized("attributes.cluster.highlighted")
        case "paging": localized("attributes.cluster.paging")
        default: slot
        }
    }

    // MARK: - Lines

    /// A line: a label in the title column (the row's title on the first line), and the
    /// parts, then `trailing` at its own width. A single number takes `compactWidth`, as in
    /// the design, whether or not the other parts of its line are there; otherwise the parts
    /// share the width, equally when `equal`.
    private func line(
        _ label: String?, _ parts: [NSView], first: Bool = false, equal: Bool = false,
        trailing: NSView? = nil
    ) -> NSView {
        let labelView: NSView
        if first {
            labelView = titleField.accessibilityIdentifier(AttributeRowView.titleIdentifier)
        } else {
            let text = NSTextField(labelWithString: label ?? "")
                .font(Theme.Font.caption)
                .textColor(.secondaryLabelColor)
                .lineBreakMode(.byTruncatingTail)
                .accessibilityIdentifier(Self.lineLabelIdentifier)
            labelView = text
        }
        if let label, !label.isEmpty { labels.append(label) }
        let column = VStack(alignment: .fill) { labelView }
        if !equal {
            for part in parts where compact.contains(ObjectIdentifier(part)) {
                part.widthAnchor.constraint(equalToConstant: Self.compactWidth).isActive = true
                part.setContentHuggingPriority(.required, for: .horizontal)
            }
        }
        // Nothing to stretch: what is left goes after the parts.
        let stretches = equal || parts
            .contains { !compact.contains(ObjectIdentifier($0)) && !hugs.contains(ObjectIdentifier($0)) }
        let content = HStack(alignment: .center, spacing: 6) {
            for part in parts { part }
            if !stretches { Spacer() }
        }
        if equal { content.distribution = .fillEqually }
        let line = HStack(alignment: .center, spacing: Theme.Spacing.small) {
            column
                .frame(width: AttributeRowView.titleWidth)
            content
            if let trailing { trailing }
        }
        // Centred on parts one field tall, at the top of taller ones (C-ATTR-12).
        // The editors held weakly: each keeps this closure.
        let editors = parts.compactMap { $0 as? AttributeEditorView }
        let tallness = editors.map { editor in { [weak editor] in editor?.isTall ?? false } }
        let align = { [weak line, weak column] in
            guard let line, let column else { return }
            TitleAlignment.apply(line, title: column, isTall: tallness.contains { $0() })
        }
        for editor in editors { editor.onTallChange = align }
        align()
        return line
    }

    /// The width of a single number in a compound row: "100 %", "13 pt".
    static let compactWidth: CGFloat = 60
    /// The parts that take `compactWidth`, and those as wide as their content.
    private var compact: Set<ObjectIdentifier> = []
    private var hugs: Set<ObjectIdentifier> = []

    private func parts(_ slots: [String]) -> [NSView] {
        slots.compactMap { views[$0] }
    }

    private func build() {
        switch row.kind {
        case .shadow: buildShadow()
        case .geometry: buildGeometry()
        case .sizing: buildSizing()
        case .autoLayout, .state, .scrolling:
            let chips = HStack(alignment: .center, spacing: 4) {
                for view in parts(AttributeClusters.slotNames(of: row.kind)) { view }
                Spacer()
            }
            add(line(title, [chips], first: true))
        default:
            add(line(title, parts(AttributeClusters.slotNames(of: row.kind)), first: true))
        }
    }

    private func add(_ line: NSView) {
        stack.addArrangedSubview(line)
    }

    /// The colour and opacity on the first line, the blur and offset on the second, always
    /// shown (user's decision, 2026-10-14: a shadow that is off is not folded to "None").
    private func buildShadow() {
        let top = parts(["color", "opacity"])
        if !top.isEmpty { add(line(title, top, first: true)) }
        let second = parts(["radius", "offset"])
        if !second.isEmpty { add(line(nil, second, first: top.isEmpty, equal: true)) }
    }

    /// The geometry's labels, by slot.
    private static func geometryLabel(_ slot: String) -> String {
        switch slot {
        case "frame": localized("attributes.cluster.frame")
        case "position": localized("attributes.cluster.position")
        case "anchor": localized("attributes.cluster.anchor")
        case "bounds": localized("attributes.cluster.bounds")
        case "zPosition": localized("attributes.cluster.z")
        default: localized("attributes.cluster.transform")
        }
    }

    /// The frame, then position, anchor, bounds and Z, then the transform, all shown (user's
    /// decision, 2026-10-14). Without a frame the first line's label is the row's title.
    private func buildGeometry() {
        for slot in ["frame", "position", "anchor", "bounds", "zPosition", "transform"] {
            guard let view = views[slot] else { continue }
            add(line(Self.geometryLabel(slot), [view], first: stack.arrangedSubviews.isEmpty))
        }
    }

    private func buildSizing() {
        func header(_ text: String) -> NSTextField {
            NSTextField(labelWithString: text)
                .font(.systemFont(ofSize: 10.5, weight: .semibold))
                .textColor(.tertiaryLabelColor)
                .alignment(.center)
        }
        add(line(nil, [
            header(localized("attributes.cluster.horizontal")), header(localized("attributes.cluster.vertical")),
        ], equal: true))
        for (label, horizontal, vertical) in [
            (localized("attributes.cluster.hugging"), "hugging.horizontal", "hugging.vertical"),
            (localized("attributes.cluster.compression"), "compression.horizontal", "compression.vertical"),
            (localized("attributes.cluster.intrinsic"), "intrinsic.width", "intrinsic.height"),
        ] where views[horizontal] != nil || views[vertical] != nil {
            add(line(label, [views[horizontal] ?? NSView(), views[vertical] ?? NSView()], equal: true))
        }
    }

    // MARK: - Showing

    /// The value shown for a slot, nil when it has none or the row has no such member.
    private func value(of slot: String) -> AttributeValue? {
        values[slot].flatMap { $0 }
    }

    private func refresh() {
        switch row.kind {
        case .visibility:
            if case .bool(true) = value(of: "hidden") {
                views["opacity"]?.alphaValue = 0.4
            } else {
                views["opacity"]?.alphaValue = 1
            }
        default:
            break
        }
    }

    /// A note under the row: why a part's value is not sent, led by the part's attribute
    /// (C-ATTR-13).
    private func show(_ note: String?, of name: String) {
        guard let note else {
            noteLabel.stringValue = ""
            noteLabel.isHidden = true
            return
        }
        noteLabel.stringValue = "\(name): \(note)"
        noteLabel.textColor = .systemRed
        noteLabel.isHidden = false
    }

    /// What shows the attribute with this ID in the row, if it is a member.
    func view(forAttribute id: String) -> NSView? {
        row.members.first { $0.value.id == id }.flatMap { views[$0.key] }
    }

    /// The note under the row, or nil. For tests.
    var noteText: String? { noteLabel.isHidden ? nil : noteLabel.stringValue }

    // MARK: - Filtering

    func matches(_ filter: String) -> Bool {
        let texts = [title] + labels + row.attributes.flatMap { [$0.title, $0.id].compactMap { $0 } }
        return texts.contains { AttributesViewModel.match(of: filter, in: $0) != nil }
    }

    func highlight(_ filter: String?) {
        titleField.highlight(filter)
    }

    /// Whether a filter's match is marked in the title. For tests.
    var showsMatch: Bool { titleField.showsMatch }

    override func layout() {
        let insets = titleField.alignmentRectInsets.left + titleField.alignmentRectInsets.right
        titleField.give(width: AttributeRowView.titleWidth + insets)
        let width = bounds.width - 2 * Theme.Spacing.large
        if width > 0, noteLabel.preferredMaxLayoutWidth != width { noteLabel.preferredMaxLayoutWidth = width }
        super.layout()
    }
}

/// A part's cell that tells its row what it shows, so that the row can follow its values.
@MainActor
private final class ForwardingCell: AttributeCell {
    let inner: any AttributeCell
    let shown: (AttributeValue?) -> Void

    init(_ inner: any AttributeCell, shown: @escaping (AttributeValue?) -> Void) {
        self.inner = inner
        self.shown = shown
    }

    func show(_ value: AttributeValue?, systemColorName: String?) {
        inner.show(value, systemColorName: systemColorName)
        shown(value)
    }

    func show(sending: Bool, failure: String?) {
        inner.show(sending: sending, failure: failure)
    }

    func showInactive(_ reason: String?) {
        inner.showInactive(reason)
    }

    func show(layerSize: String?) {
        inner.show(layerSize: layerSize)
    }
}
