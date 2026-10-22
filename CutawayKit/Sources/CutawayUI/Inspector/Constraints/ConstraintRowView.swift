import AppKit
import CutawayWire
import DeclarativeAppKit

/// Where the pointer is among the constraints of the attribute panel (C-LAYOUT-07): on some,
/// by their places in the server's order, or off those it was on. A row's ends are stressed;
/// those of the folded UIKit ones are not.
enum ConstraintPointer: Equatable {
    case entered([Int], stresses: Bool)
    case left([Int])
}

/// One constraint: whether it holds, its equation, and the lines below it. Pointing anywhere
/// on it marks its other ends on the preview (C-LAYOUT-07), and fills it as the hierarchy
/// fills a hovered row. The section says which row the pointer is on (`ConstraintsSectionView`).
final class ConstraintRowView: NSView {
    static let identifier = "constraints.row"
    static let statusIdentifier = "constraints.status"
    static let detailIdentifier = "constraints.detail"
    static let ownerIdentifier = "constraints.owner"
    static let classIdentifier = "constraints.class"
    static let notInEffectIdentifier = "constraints.notInEffect"

    let text: ConstraintRow
    let equationView: ConstraintEquationView
    var onPoint: (ConstraintPointer) -> Void = { _ in }
    private(set) var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            needsDisplay = true
            onPoint(isHovered ? .entered([text.index], stresses: true) : .left([text.index]))
        }
    }

    init(
        _ text: ConstraintRow, showsClass: Bool, onShowLayer: @escaping (UInt64) -> Void,
        onHoverEnd: @escaping (ConstraintRow.End?) -> Void = { _ in }
    ) {
        self.text = text
        equationView = ConstraintEquationView(
            text.equation, dimmed: text.status == .unsatisfied, onShowLayer: onShowLayer)
        equationView.onHoverEnd = onHoverEnd
        super.init(frame: .zero)
        setAccessibilityIdentifier(Self.identifier)
        let status = Self.status(text.status)
        let lines = text.guideOwners + [text.details].compactMap { $0 }
        addHStack(alignment: .top, spacing: Theme.Spacing.small) {
            NSImageView()
                .image(Theme.symbol(status.symbol, size: status.size, weight: .semibold))
                .contentTintColor(status.color)
                .accessibilityIdentifier(Self.statusIdentifier)
                .accessibilityLabel(status.label)
                .frame(width: 12, height: 15)
            VStack(alignment: .fill, spacing: 2) {
                equationView
                // The owners come first, then the details: told apart by place, as a detail
                // may read as an owner does.
                lines.enumerated().map { index, line in
                    NSTextField(wrappingLabelWithString: line)
                        .font(Theme.Font.caption)
                        .textColor(.secondaryLabelColor)
                        .compressionResistancePriority(Theme.textGivesWay, for: .horizontal)
                        .accessibilityIdentifier(
                            index < text.guideOwners.count
                                ? Self.ownerIdentifier : Self.detailIdentifier)
                }
                if showsClass, let className = text.generatedClassName {
                    NSTextField(wrappingLabelWithString: className)
                        .font(Theme.Font.caption)
                        .textColor(.tertiaryLabelColor)
                        .compressionResistancePriority(Theme.textGivesWay, for: .horizontal)
                        .accessibilityIdentifier(Self.classIdentifier)
                }
                if text.status == .unsatisfied {
                    HStack(alignment: .center) {
                        NSBox()
                            .configure {
                                $0.boxType = .custom
                                $0.borderWidth = 1
                                $0.borderColor = .separatorColor
                                $0.cornerRadius = 4
                                $0.fillColor = .clear
                                $0.titlePosition = .noTitle
                                $0.contentViewMargins = NSSize(width: 6, height: 1)
                                $0.contentView?.addContent(
                                    NSTextField(labelWithString: localized("constraints.status.notInEffect"))
                                        .font(Theme.Font.caption)
                                        .textColor(.secondaryLabelColor))
                            }
                            .accessibilityIdentifier(Self.notInEffectIdentifier)
                        Spacer()
                    }
                    .padding(top: 2, leading: 0, bottom: 0, trailing: 0)
                }
            }
        }
        .padding(horizontal: Theme.Spacing.large, vertical: 5)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Puts the pointer on the row, or off it.
    func point(_ inside: Bool) {
        isHovered = inside
    }

    /// The hover fill, as the hierarchy's (C-HIER-15), inset from the panel's edges.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHovered else { return }
        Theme.hoverFill.setFill()
        let inset = Theme.Spacing.large - 6
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: inset, dy: 0), xRadius: Theme.Radius.control,
            yRadius: Theme.Radius.control
        ).fill()
    }

    /// How a status is marked.
    struct StatusMark {
        let symbol: String
        let size: CGFloat
        let color: NSColor
        let label: String
    }

    /// The mark of each status: three that tell apart at a glance (C-LAYOUT-02).
    static func status(_ status: ConstraintStatus) -> StatusMark {
        switch status {
        case .satisfied:
            StatusMark(symbol: "circle.fill", size: 7, color: .systemGreen,
                       label: localized("constraints.status.inEffect"))
        case .unsatisfied:
            StatusMark(symbol: "circle", size: 7, color: .tertiaryLabelColor,
                       label: localized("constraints.status.notInEffect"))
        case .unknown:
            StatusMark(symbol: "questionmark.circle", size: 10, color: .tertiaryLabelColor,
                       label: localized("constraints.status.unknown"))
        }
    }
}
