import AppKit
import DeclarativeAppKit

/// The Constraints section of the attribute panel (C-LAYOUT-02), after the app's groups: a
/// header that folds it away as theirs do, then one row to a constraint, in the server's
/// order. The constraints UIKit made are folded into one last row that opens to list them.
/// Names in the accent colour select their layer (C-LAYOUT-03).
final class ConstraintsSectionView: NSView {
    static let headerIdentifier = "constraints.header"
    static let emptyIdentifier = "constraints.empty"
    static let generatedIdentifier = "constraints.generated"

    let list: ConstraintList
    /// The rows of the app's constraints, then those of UIKit's.
    let rows: [ConstraintRowView]
    var onToggle: (Bool) -> Void = { _ in }
    var onToggleGenerated: (Bool) -> Void = { _ in }
    private(set) var isCollapsed: Bool {
        didSet { apply() }
    }

    private(set) var showsGenerated: Bool {
        didSet { apply() }
    }

    private(set) lazy var header: NSButton = .init().configure {
        $0.isBordered = false
        $0.imageHugsTitle = true
        $0.target = self
        $0.action = #selector(toggle(_:))
    }

    private(set) lazy var generatedButton: NSButton = .init().configure {
        $0.isBordered = false
        $0.imageHugsTitle = true
        // The class names after the count are cut short rather than widen the inspector.
        ($0.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        $0.target = self
        $0.action = #selector(toggleGenerated(_:))
    }

    private let body: VStack
    private let generatedRows: VStack

    init(
        rows: [ConstraintRow], isCollapsed: Bool, showsGenerated: Bool,
        onShowLayer: @escaping (UInt64) -> Void
    ) {
        let list = ConstraintList(rows)
        self.list = list
        self.isCollapsed = isCollapsed
        self.showsGenerated = showsGenerated
        let generated = list.generated
        let ownRows = list.own.map {
            ConstraintRowView($0, showsClass: false, onShowLayer: onShowLayer)
        }
        let generatedRowViews = generated.map {
            ConstraintRowView($0, showsClass: true, onShowLayer: onShowLayer)
        }
        self.rows = ownRows + generatedRowViews
        generatedRows = VStack(alignment: .fill, spacing: 0) { generatedRowViews }
            .padding(top: 0, leading: Theme.Spacing.medium, bottom: 0, trailing: 0)
        body = VStack(alignment: .fill, spacing: 0) {}
        super.init(frame: .zero)

        body.addContent(VStack(alignment: .fill, spacing: 0) {
            ownRows
            if !generated.isEmpty {
                VStack(alignment: .fill) {
                    NSBox().configure {
                        $0.boxType = .custom
                        $0.borderWidth = 0
                        $0.cornerRadius = Theme.Radius.control
                        $0.fillColor = .quaternarySystemFill
                        $0.titlePosition = .noTitle
                        $0.contentViewMargins = NSSize(width: 6, height: 3)
                        $0.contentView?.addContent(HStack(alignment: .center) {
                            generatedButton
                                .buttonType(.momentaryChange)
                                .imagePosition(.imageLeading)
                                .alignment(.left)
                                .contentTintColor(.secondaryLabelColor)
                                .compressionResistancePriority(
                                    Theme.textGivesWay, for: .horizontal)
                                .accessibilityIdentifier(Self.generatedIdentifier)
                            Spacer()
                        })
                    }
                }
                .padding(top: 4, leading: Theme.Spacing.large - 6, bottom: 2,
                         trailing: Theme.Spacing.large - 6)
                generatedRows
            }
            if rows.isEmpty {
                VStack(alignment: .leading) {
                    NSTextField(labelWithString: localized("constraints.empty"))
                        .font(Theme.Font.caption)
                        .textColor(.tertiaryLabelColor)
                        .accessibilityIdentifier(Self.emptyIdentifier)
                }
                .padding(horizontal: Theme.Spacing.large + 4, vertical: 2)
            }
        })
        addVStack(alignment: .fill, spacing: 4) {
            HStack(alignment: .center) {
                header
                    .buttonType(.momentaryChange)
                    .imagePosition(.imageLeading)
                    .alignment(.left)
                    .contentTintColor(.secondaryLabelColor)
                    .accessibilityIdentifier(Self.headerIdentifier)
                Spacer()
            }
            .padding(horizontal: Theme.Spacing.large - 2, vertical: 0)
            body
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

    @objc func toggleGenerated(_ sender: Any?) {
        showsGenerated.toggle()
        onToggleGenerated(showsGenerated)
    }

    private func apply() {
        body.isHidden = isCollapsed
        header.image = Theme.symbol(
            isCollapsed ? "chevron.right" : "chevron.down", size: 9, weight: .bold)
        let title = NSMutableAttributedString(
            string: " " + localized("constraints.header"),
            attributes: [
                .font: Theme.Font.captionEmphasized,
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        if !list.rows.isEmpty {
            title.append(NSAttributedString(
                string: "  \(list.count)",
                attributes: [
                    .font: Theme.Font.captionDigits,
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]))
        }
        header.attributedTitle = title
        header.setAccessibilityLabel(localized("constraints.header"))
        header.setAccessibilityValue(
            isCollapsed ? localized("disclosure.collapsed") : localized("disclosure.expanded"))

        generatedRows.isHidden = !showsGenerated
        generatedButton.image = Theme.symbol(
            showsGenerated ? "chevron.down" : "chevron.right", size: 9, weight: .bold)
        let label = localized("constraints.generated", list.generatedCount)
        let generatedTitle = NSMutableAttributedString(
            string: " " + label,
            attributes: [.font: Theme.Font.caption, .foregroundColor: NSColor.labelColor])
        if let generatedSummary = list.generatedSummary, !showsGenerated {
            generatedTitle.append(NSAttributedString(
                string: "  " + generatedSummary,
                attributes: [
                    .font: Theme.Font.caption, .foregroundColor: NSColor.tertiaryLabelColor,
                ]))
        }
        generatedButton.attributedTitle = generatedTitle
        generatedButton.setAccessibilityLabel(label)
        generatedButton.setAccessibilityValue(
            showsGenerated ? localized("disclosure.expanded") : localized("disclosure.collapsed"))
    }
}
