import AppKit
import CutawayModel
import DeclarativeAppKit

/// One row of the hierarchy list: an icon for what the layer is (C-HIER-11) and the layer's
/// title (C-HIER-01), then in smaller text the view controller it is the root view of or the member
/// that holds it (C-HIER-07); weaker, and marked with a crossed-out eye, for a layer that
/// cannot be seen (C-HIER-03); the icon fades with it.
final class HierarchyRowView: NSTableCellView {
    static let titleIdentifier = "hierarchy.title"
    static let symbolIdentifier = "hierarchy.symbol"
    static let hiddenIdentifier = "hierarchy.hidden"
    static let detailIdentifier = "hierarchy.detail"
    /// What a row puts beside its title at most: the icon, the hidden mark and the gaps,
    /// measured on a row that shows them all.
    static let widthBesideTitle: CGFloat = {
        let row = HierarchyRowView()
        // Measured by its constraints alone: a frame of 0 × 0 would conflict with them.
        row.translatesAutoresizingMaskIntoConstraints = false
        row.configure(HierarchyRow(title: "", isDimmed: true))
        return (row.fittingSize.width - NSTextField(labelWithString: "").intrinsicContentSize.width)
            .rounded(.up)
    }()

    private let symbolView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    /// The detail's colour on a row that is not selected.
    private var detailColor = NSColor.secondaryLabelColor
    private let hiddenMark = NSImageView()
    private(set) var isDimmed = false
    private(set) var icon: LayerIcon?

    /// The gap between the disclosure triangle and the icon.
    static let iconInset: CGFloat = 4

    init() {
        super.init(frame: .zero)
        addContent(HStack(alignment: .center, spacing: 6) {
            symbolView
                .imageScaling(.scaleNone)
                .accessibilityIdentifier(Self.symbolIdentifier)
                .frame(width: 16, height: 16)
            titleLabel
                .lineBreakMode(.byTruncatingTail)
                .accessibilityIdentifier(Self.titleIdentifier)
            detailLabel
                .font(Theme.Font.caption)
                .lineBreakMode(.byTruncatingTail)
                // Gives way first: the title is what the column is sized for.
                .compressionResistancePriority(.defaultLow, for: .horizontal)
                .accessibilityIdentifier(Self.detailIdentifier)
            hiddenMark
                .image(Theme.symbol(Theme.Symbol.hiddenLayer, size: 10, description: localized("hierarchy.row.hidden")))
                .contentTintColor(.tertiaryLabelColor)
                .accessibilityIdentifier(Self.hiddenIdentifier)
            Spacer()
        }
        .padding(top: 0, leading: Self.iconInset, bottom: 0, trailing: 0))
        imageView = symbolView
        textField = titleLabel
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The width a row needs to show this title in full, the icon and the mark included.
    /// The detail is not counted: it is cut short when there is no room (C-HIER-07).
    static func width(ofTitle title: String) -> CGFloat {
        NSTextField(labelWithString: title).intrinsicContentSize.width + widthBesideTitle
    }

    /// The title's colour. For tests.
    var titleColor: NSColor? { titleLabel.textColor }

    /// Shows a row; a reused view shows the new row in full.
    func configure(_ row: HierarchyRow) {
        titleLabel.stringValue = row.title
        // The text, not the row's alpha: the selection's background must not fade with it.
        titleLabel.textColor =
            row.isDimmed ? .tertiaryLabelColor : row.isContext ? .secondaryLabelColor : .labelColor
        detailLabel.stringValue = row.detail ?? ""
        detailLabel.isHidden = row.detail == nil
        detailColor = row.isDimmed || row.isContext ? .tertiaryLabelColor : .secondaryLabelColor
        toolTip = row.toolTip
        hiddenMark.isHidden = !row.isDimmed
        icon = row.icon
        // The text and the icon both fade; a row of the search's context too (C-HIER-04).
        symbolView.alphaValue = row.isDimmed || row.isContext ? 0.4 : 1
        isDimmed = row.isDimmed
        updateSymbolTint()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateSymbolTint() }
    }

    /// The icon in its colours, as the selected row shows it on the accent colour; the
    /// detail likewise.
    private func updateSymbolTint() {
        let isSelected = backgroundStyle == .emphasized
        symbolView.image = icon.map { LayerIconImage.image($0, isSelected: isSelected) }
        detailLabel.textColor = isSelected ? .alternateSelectedControlTextColor : detailColor
    }
}
