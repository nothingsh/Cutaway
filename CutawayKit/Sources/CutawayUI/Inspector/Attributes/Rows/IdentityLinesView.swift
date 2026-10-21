import AppKit
import CutawayModel
import DeclarativeAppKit

/// The top of the Identity section (C-ATTR-10, C-ATTR-11, C-HIER-07): the view and the layer,
/// each with its class and under it its address, the view controller whose root view the layer
/// backs, with its address, and the members that hold the layer. A line with nothing to say is
/// left out. A filter keeps the lines whose titles hold it (C-ATTR-14). A class declared in the
/// app's project folder has a button that opens it in Xcode (C-SRC-03).
final class IdentityLinesView: NSView {
    static let lineIdentifier = "attributes.identity.line"
    /// The class of the view, or of the layer for a layer that backs no view.
    static let classIdentifier = "attributes.identity.class"
    /// The class of a layer that backs a view.
    static let layerClassIdentifier = "attributes.identity.layerClass"
    static let viewAddressIdentifier = "attributes.identity.viewAddress"
    static let layerAddressIdentifier = "attributes.identity.layerAddress"
    static let controllerIdentifier = "attributes.identity.controller"
    static let controllerAddressIdentifier = "attributes.identity.controllerAddress"
    static let referencesIdentifier = "attributes.identity.references"
    static let copyIdentifier = "attributes.identity.copy"
    static let openInXcodeIdentifier = "attributes.identity.openInXcode"
    static let copySymbol = "doc.on.doc"

    /// Puts an address on the clipboard.
    private let copy: @MainActor (String) -> Void
    /// Opens a class's declaration, or offers the choice among several below the button.
    private let openInXcode: @MainActor ([SourceLocation], NSView) -> Void
    private let stack = VStack(alignment: .fill, spacing: 0) {}
    /// What is shown, so that the same layer sent again builds nothing.
    private(set) var summary: LayerSummary?
    /// Each line with its title, as shown.
    private(set) var lines: [(title: WrappingTitleField, view: NSView)] = []
    private var filter: String?

    init(
        copy: @escaping @MainActor (String) -> Void,
        openInXcode: @escaping @MainActor ([SourceLocation], NSView) -> Void = { _, _ in }
    ) {
        self.copy = copy
        self.openInXcode = openInXcode
        super.init(frame: .zero)
        addContent(stack)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows what the panel knows about this layer, or nothing.
    func show(_ summary: LayerSummary?) {
        guard summary != self.summary || lines.isEmpty else { return }
        self.summary = summary
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        lines = summary.map(makeLines) ?? []
        for line in lines { stack.addArrangedSubview(line.view) }
        _ = apply(filter: filter)
    }

    /// Keeps the lines whose titles hold the filter, all of them for nil, and says how many are
    /// left.
    func apply(filter: String?) -> Int {
        self.filter = filter
        var shown = 0
        for line in lines {
            let keeps = filter == nil
                || AttributesViewModel.match(of: filter ?? "", in: line.title.title) != nil
            line.view.isHidden = !keeps
            line.title.highlight(filter)
            if keeps { shown += 1 }
        }
        return shown
    }

    private func makeLines(_ summary: LayerSummary) -> [(title: WrappingTitleField, view: NSView)] {
        var lines: [(title: WrappingTitleField, view: NSView)] = []
        if summary.backsView {
            lines.append(line(localized("attributes.identity.view"), entries: [
                Entry(
                    text: summary.className ?? "", identifier: Self.classIdentifier,
                    sources: summary.openable.view),
                summary.viewAddress.map {
                    Entry(text: $0, identifier: Self.viewAddressIdentifier, copies: true)
                },
            ]))
            lines.append(line(localized("attributes.identity.layer"), entries: [
                Entry(
                    text: summary.layerClassName ?? "", identifier: Self.layerClassIdentifier,
                    sources: summary.openable.layer),
                summary.layerAddress.map {
                    Entry(text: $0, identifier: Self.layerAddressIdentifier, copies: true)
                },
            ]))
        } else {
            let title = summary.isVirtual
                ? localized("attributes.identity.virtualNode") : localized("attributes.identity.layer")
            lines.append(line(title, entries: [
                Entry(
                    text: summary.className ?? "", identifier: Self.classIdentifier,
                    sources: summary.openable.layer),
                summary.layerAddress.map {
                    Entry(text: $0, identifier: Self.layerAddressIdentifier, copies: true)
                },
            ]))
        }
        if let controller = summary.controller {
            lines.append(line(localized("attributes.header.viewController"), entries: [
                Entry(
                    text: controller, identifier: Self.controllerIdentifier,
                    sources: summary.openable.controller),
                summary.controllerAddress.map {
                    Entry(text: $0, identifier: Self.controllerAddressIdentifier, copies: true)
                },
            ]))
        }
        if !summary.references.isEmpty {
            lines.append(line(localized("attributes.header.referencedBy"), entries: [
                Entry(
                    text: summary.references.joined(separator: "\n"),
                    identifier: Self.referencesIdentifier),
            ]))
        }
        return lines
    }

    /// One text of a line: a value, an address with a button that copies it, or a class with
    /// a button that opens where it is declared.
    private struct Entry {
        var text: String
        var identifier: String
        var copies = false
        var sources: [SourceLocation] = []
    }

    /// A line as an attribute row lays it out: the title in its column, the texts beside it,
    /// one under the other.
    private func line(_ title: String, entries: [Entry?]) -> (title: WrappingTitleField, view: NSView) {
        let titleField = WrappingTitleField(title: title)
        let titleColumn = VStack(alignment: .fill) { titleField }
        let line = NSView()
        line.addHStack(alignment: .top, spacing: Theme.Spacing.small) {
            titleColumn
            VStack(alignment: .leading, spacing: 1) {
                entries.compactMap { $0 }.map(entry)
            }
            .contentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        }
        .padding(horizontal: Theme.Spacing.large, vertical: 3)
        // The same column as the attributes' titles (C-ATTR-12).
        titleColumn.widthAnchor.constraint(equalToConstant: AttributeRowView.titleWidth).isActive = true
        line.setAccessibilityIdentifier(Self.lineIdentifier)
        return (titleField, line)
    }

    private func entry(_ entry: Entry) -> NSView {
        let text = NSTextField(wrappingLabelWithString: entry.text)
            .font(entry.copies ? Theme.Font.captionDigits : Theme.Font.caption)
            .textColor(entry.copies ? .secondaryLabelColor : .labelColor)
            .compressionResistancePriority(Theme.textGivesWay, for: .horizontal)
            .isSelectable(true)
            .accessibilityIdentifier(entry.identifier)
        if !entry.sources.isEmpty {
            return HStack(alignment: .center, spacing: Theme.Spacing.tight) {
                text
                openInXcodeButton(entry.sources)
            }
        }
        guard entry.copies else { return text }
        let address = entry.text
        let button = NSButton()
            .configure {
                $0.image = Theme.symbol(Self.copySymbol, size: 10)
                $0.isBordered = false
                $0.imagePosition = .imageOnly
            }
            .contentTintColor(.tertiaryLabelColor)
            .toolTip(localized("attributes.identity.copyAddress"))
            .accessibilityIdentifier(Self.copyIdentifier)
            .sink(\.clickPublisher) { [copy] in copy(address) }
        button.setAccessibilityLabel(localized("attributes.identity.copyAddress"))
        return HStack(alignment: .center, spacing: Theme.Spacing.tight) {
            text
            button
        }
    }

    private func openInXcodeButton(_ sources: [SourceLocation]) -> NSButton {
        let button = NSButton()
            .configure {
                $0.image = Theme.symbol(Theme.Symbol.openInXcode, size: 10)
                $0.isBordered = false
                $0.imagePosition = .imageOnly
            }
            .contentTintColor(.tertiaryLabelColor)
            .toolTip(DeclarationChoices.toolTip(for: sources))
            .accessibilityIdentifier(Self.openInXcodeIdentifier)
        button.sink(\.clickPublisher) { [openInXcode, weak button] in
            guard let button else { return }
            openInXcode(sources, button)
        }
        button.setAccessibilityLabel(localized("source.openInXcode"))
        return button
    }
}
