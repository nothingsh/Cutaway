import AppKit
import CutawayModel

/// The header of a section of the attribute panel (C-ATTR-15): the section's icon and title at
/// the start (C-ATTR-17), a count or a summary after it when one is given, and the chevron at
/// the end of the row. The whole row is the button that folds the section; with Option held, the panel folds
/// every section.
final class SectionHeader: NSButton {
    /// What the icon before the title shows (C-ATTR-17).
    enum Icon: Equatable {
        /// The class of the Content section's group.
        case layer(LayerIcon)
        case constraints
        /// A symbol of the system's, for the sections named by what they are for.
        case symbol(String)
    }

    static let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let iconSide: CGFloat = 14
    /// Between the icon and the title.
    static let iconSpacing: CGFloat = 7

    /// The title without the count, as said to accessibility.
    private(set) var sectionTitle = ""
    private(set) var icon: Icon?

    /// The title and the count as shown, without the icon.
    var shownText: String {
        attributedTitle.string.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    init() {
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryChange)
        imagePosition = .imageTrailing
        // The chevron at the end of the row, not after the title.
        imageHugsTitle = false
        alignment = .left
        contentTintColor = .tertiaryLabelColor
        // A long title is cut short rather than widen the inspector.
        (cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        setContentCompressionResistancePriority(Theme.textGivesWay, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows a section's icon and title, folded or not, and a count or a summary after the
    /// title if there is one.
    func show(
        title: String, count: Int?, isCollapsed: Bool, icon: Icon? = nil, summary: String? = nil
    ) {
        sectionTitle = title
        self.icon = icon
        let text = NSMutableAttributedString()
        if let icon {
            text.append(Self.attachment(icon))
        }
        text.append(NSAttributedString(
            string: title,
            attributes: [.font: Self.titleFont, .foregroundColor: NSColor.labelColor]))
        if let count {
            text.append(NSAttributedString(
                string: "  \(count)",
                attributes: [
                    .font: Theme.Font.captionDigits, .foregroundColor: NSColor.tertiaryLabelColor,
                ]))
        }
        if let summary, !summary.isEmpty {
            text.append(NSAttributedString(
                string: "  " + summary,
                attributes: [.font: Theme.Font.caption, .foregroundColor: NSColor.tertiaryLabelColor]))
        }
        attributedTitle = text
        image = Theme.symbol(isCollapsed ? "chevron.right" : "chevron.down", size: 9, weight: .bold)
        setAccessibilityLabel(title)
        setAccessibilityValue(
            isCollapsed ? localized("disclosure.collapsed") : localized("disclosure.expanded"))
    }

    /// The icon as the start of the title, centred on the title's capitals, then a blank
    /// `iconSpacing` wide: a button's title leaves out the kerning after an attachment.
    private static func attachment(_ icon: Icon) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = switch icon {
        case .layer(let icon): LayerIconImage.image(icon, side: iconSide)
        case .constraints: ConstraintIconImage.section(side: iconSide)
        case .symbol(let name): symbolImage(name)
        }
        attachment.bounds = NSRect(
            x: 0, y: ((titleFont.capHeight - iconSide) / 2).rounded(), width: iconSide, height: iconSide)
        let space = NSTextAttachment()
        space.image = NSImage(size: NSSize(width: iconSpacing, height: 1))
        space.bounds = NSRect(x: 0, y: 0, width: iconSpacing, height: 1)
        let text = NSMutableAttributedString(attachment: attachment)
        text.append(NSAttributedString(attachment: space))
        return text
    }

    /// A system symbol the size of the other icons, in the secondary colour.
    private static func symbolImage(_ name: String) -> NSImage? {
        guard let symbol = Theme.symbol(name, size: 11, weight: .medium) else { return nil }
        let configured = symbol.withSymbolConfiguration(
            NSImage.SymbolConfiguration(hierarchicalColor: .secondaryLabelColor)) ?? symbol
        return NSImage(size: NSSize(width: iconSide, height: iconSide), flipped: false) { rect in
            let size = configured.size
            configured.draw(in: NSRect(
                x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                width: size.width, height: size.height))
            return true
        }
    }

    /// Whether the click that is being handled held Option: it folds every section.
    static var clickFoldsAll: Bool {
        NSApp.currentEvent?.modifierFlags.contains(.option) ?? false
    }
}
