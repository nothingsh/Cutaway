import AppKit
import DeclarativeAppKit

/// One row of the hierarchy list: a symbol for what the layer is and the layer's title
/// (C-HIER-01), then in smaller text the view controller it is the root view of or the member
/// that holds it (C-HIER-07); weaker, and marked with a crossed-out eye, for a layer that
/// cannot be seen (C-HIER-03).
final class HierarchyRowView: NSTableCellView {
    static let titleIdentifier = "hierarchy.title"
    static let symbolIdentifier = "hierarchy.symbol"
    static let hiddenIdentifier = "hierarchy.hidden"
    static let detailIdentifier = "hierarchy.detail"
    /// What a row puts beside its title at most: the symbol, the hidden mark and the gaps,
    /// measured on a row that shows them all.
    static let widthBesideTitle: CGFloat = {
        let row = HierarchyRowView()
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
    private(set) var symbolName: String?

    init() {
        super.init(frame: .zero)
        addHStack(alignment: .center, spacing: 6) {
            symbolView
                .imageScaling(.scaleProportionallyDown)
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
                .image(Theme.symbol("eye.slash", size: 10, description: localized("hierarchy.row.hidden")))
                .contentTintColor(.tertiaryLabelColor)
                .accessibilityIdentifier(Self.hiddenIdentifier)
            Spacer()
        }
        imageView = symbolView
        textField = titleLabel
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The width a row needs to show this title in full, the symbol and the mark included.
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
        if row.symbolName != symbolName {
            symbolView.image = Theme.symbol(row.symbolName, size: 12)
            symbolName = row.symbolName
        }
        isDimmed = row.isDimmed
        updateSymbolTint()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateSymbolTint() }
    }

    /// The accent colour, except on the selected row, whose background is the accent colour;
    /// the detail likewise.
    private func updateSymbolTint() {
        if backgroundStyle == .emphasized {
            symbolView.contentTintColor = .alternateSelectedControlTextColor
            detailLabel.textColor = .alternateSelectedControlTextColor
        } else {
            symbolView.contentTintColor = isDimmed ? .tertiaryLabelColor : .controlAccentColor
            detailLabel.textColor = detailColor
        }
    }
}
