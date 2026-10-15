import AppKit
import CutawayModel
import CutawayTransport
import CutawayWire
import DeclarativeAppKit

/// One row of the app list (C-LIST-01 to C-LIST-04): the icon, the name and version, a capsule
/// for an app that is not active or not compatible, and the second line. The selected row says
/// that Return inspects it.
final class AppRowView: NSTableCellView {
    /// Accessibility identifiers of the row's parts.
    enum Identifier {
        static let icon = "app.icon"
        static let iconPlaceholder = "app.iconPlaceholder"
        static let name = "app.name"
        static let version = "app.version"
        static let badge = "app.badge"
        static let subtitle = "app.subtitle"
        static let returnHint = "app.returnHint"
    }

    static let iconSize: CGFloat = 36

    private let iconView = NSImageView()
    private let placeholderView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let versionLabel = NSTextField(labelWithString: "")
    let badge = StatusCapsule()
    private let subtitleLabel = NSTextField(labelWithString: "")
    let returnHint = KeyHintView(text: localized("appList.returnHint"))

    init() {
        super.init(frame: .zero)
        let tile = NSView()
        tile.wantsLayer = true
        tile.layer?.cornerRadius = Theme.Radius.appIcon
        tile.layer?.cornerCurve = .continuous
        tile.layer?.masksToBounds = true
        tile.layer?.borderWidth = 0.5
        tile.addContent(placeholderView
            .image(Theme.symbol(Theme.Symbol.appPlaceholder, size: 20, weight: .light))
            .contentTintColor(.tertiaryLabelColor)
            .imageScaling(.scaleNone)
            .accessibilityIdentifier(Identifier.iconPlaceholder))
        tile.addContent(iconView
            .imageScaling(.scaleProportionallyUpOrDown)
            .accessibilityIdentifier(Identifier.icon))
        iconTile = tile

        addHStack(alignment: .center, spacing: Theme.Spacing.medium) {
            tile.frame(width: Self.iconSize, height: Self.iconSize)
            VStack(alignment: .leading, spacing: 1) {
                // Centred, not on the baseline: the capsule has none, and the name and version
                // are the same size.
                HStack(alignment: .center, spacing: 6) {
                    nameLabel
                        .font(Theme.Font.bodyEmphasized)
                        .lineBreakMode(.byTruncatingTail)
                        .compressionResistancePriority(
                            NSLayoutConstraint.Priority(rawValue: 260), for: .horizontal)
                        .accessibilityIdentifier(Identifier.name)
                    versionLabel
                        .textColor(.secondaryLabelColor)
                        .lineBreakMode(.byTruncatingTail)
                        .compressionResistancePriority(.defaultLow, for: .horizontal)
                        .accessibilityIdentifier(Identifier.version)
                    badge
                }
                subtitleLabel
                    .font(Theme.Font.caption)
                    .textColor(.secondaryLabelColor)
                    .lineBreakMode(.byTruncatingMiddle)
                    .compressionResistancePriority(.defaultLow, for: .horizontal)
                    .accessibilityIdentifier(Identifier.subtitle)
            }
            Spacer()
            returnHint
                .accessibilityIdentifier(Identifier.returnHint)
        }
        .padding(horizontal: 10, vertical: 7)
        returnHint.isHidden = true
        updateColors()
    }

    private var iconTile: NSView?

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    /// Layer colours do not follow the appearance by themselves.
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            iconTile?.layer?.borderColor = NSColor.separatorColor.cgColor
            iconTile?.layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
        }
    }

    /// The selected row, on the accent colour, shows the hint.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { returnHint.isHidden = backgroundStyle != .emphasized }
    }

    func configure(with entry: AppEntry) {
        let presentation = AppEntryPresentation(entry)
        nameLabel.stringValue = presentation.name
        show(presentation.version, in: versionLabel)
        show(presentation.subtitle, in: subtitleLabel)
        iconView.image = entry.icon?.makeImage()
        placeholderView.isHidden = iconView.image != nil

        badge.show(presentation.badge)
        // Dimmed: it is listed, but it is not a choice.
        alphaValue = presentation.isDimmed ? 0.55 : 1
    }

    /// Shows `text` in `label`, or hides the label when there is nothing to show.
    private func show(_ text: String?, in label: NSTextField) {
        label.stringValue = text ?? ""
        label.isHidden = text == nil
    }
}

/// A key and what it does, outlined, as the selected row of the app list shows it: "⏎ Inspect".
/// Drawn in white, for the accent colour under it.
final class KeyHintView: NSView {
    let text: String
    private let attributed: NSAttributedString
    private static let inset = NSSize(width: 6, height: 1)

    init(text: String) {
        self.text = text
        attributed = NSAttributedString(string: text, attributes: [
            .font: Theme.Font.caption,
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ])
        super.init(frame: .zero)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityValue(text)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var intrinsicContentSize: NSSize {
        let size = attributed.size()
        return NSSize(
            width: ceil(size.width) + Self.inset.width * 2, height: ceil(size.height) + Self.inset.height * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        outline.lineWidth = 1
        NSColor.white.withAlphaComponent(0.5).setStroke()
        outline.stroke()
        let size = attributed.size()
        attributed.draw(at: NSPoint(x: Self.inset.width, y: (bounds.height - size.height) / 2))
    }
}
