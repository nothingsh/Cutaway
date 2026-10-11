import AppKit
import DeclarativeAppKit

/// One group of the attribute panel: a header that folds the group away, and its attributes.
final class AttributeGroupView: NSView {
    static let headerIdentifier = "attributes.group"

    let title: String
    let rows: [AttributeRowView]
    private let rowStack: VStack
    var onToggle: (Bool) -> Void = { _ in }

    private(set) var isCollapsed: Bool {
        didSet { apply() }
    }

    private lazy var header: NSButton = .init().configure {
        $0.isBordered = false
        $0.imageHugsTitle = true
        // A long group title is cut short rather than widen the inspector.
        ($0.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        $0.target = self
        $0.action = #selector(toggle(_:))
    }

    init(title: String, rows: [AttributeRowView], isCollapsed: Bool) {
        self.title = title
        self.rows = rows
        self.isCollapsed = isCollapsed
        rowStack = VStack(alignment: .fill, spacing: 2) { rows }
        super.init(frame: .zero)
        addVStack(alignment: .fill, spacing: 4) {
            HStack(alignment: .center) {
                header
                    .buttonType(.momentaryChange)
                    .imagePosition(.imageLeading)
                    .alignment(.left)
                    .contentTintColor(.secondaryLabelColor)
                    .compressionResistancePriority(Theme.textGivesWay, for: .horizontal)
                    .accessibilityIdentifier(Self.headerIdentifier)
                Spacer()
            }
            .padding(horizontal: Theme.Spacing.large - 2, vertical: 0)
            rowStack
        }
        .padding(top: 10, leading: 0, bottom: 10, trailing: 0)
        apply()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc func toggle(_ sender: Any?) {
        isCollapsed.toggle()
        onToggle(isCollapsed)
    }

    private func apply() {
        rowStack.isHidden = isCollapsed
        header.image = Theme.symbol(
            isCollapsed ? "chevron.right" : "chevron.down", size: 9, weight: .bold)
        header.attributedTitle = NSAttributedString(
            string: " " + title,
            attributes: [
                .font: Theme.Font.captionEmphasized,
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        header.setAccessibilityLabel(title)
        header.setAccessibilityValue(
            isCollapsed ? localized("disclosure.collapsed") : localized("disclosure.expanded"))
    }
}
