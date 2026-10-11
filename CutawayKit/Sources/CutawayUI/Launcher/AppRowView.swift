import AppKit
import CutawayModel
import CutawayTransport
import CutawayWire
import DeclarativeAppKit

/// One row of the app list (C-LIST-01 to C-LIST-03): the icon, the name and version, the
/// bundle ID, the device and system, a capsule for an app that is not active or not
/// compatible, and a chevron for one that can be opened.
final class AppRowView: NSTableCellView {
    /// Accessibility identifiers of the row's parts.
    enum Identifier {
        static let icon = "app.icon"
        static let iconPlaceholder = "app.iconPlaceholder"
        static let name = "app.name"
        static let version = "app.version"
        static let badge = "app.badge"
        static let bundle = "app.bundle"
        static let device = "app.device"
        static let deviceSymbol = "app.deviceSymbol"
        static let compatibility = "app.compatibility"
        static let chevron = "app.chevron"
    }

    static let iconSize: CGFloat = 40

    private let iconView = NSImageView()
    private let placeholderView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let versionLabel = NSTextField(labelWithString: "")
    let badge = StatusCapsule()
    private let bundleLabel = NSTextField(labelWithString: "")
    private let deviceSymbol = NSImageView()
    private let deviceLabel = NSTextField(labelWithString: "")
    private let compatibilityLabel = NSTextField(labelWithString: "")
    private let chevron = NSImageView()

    init() {
        super.init(frame: .zero)
        let tile = NSView()
        tile.wantsLayer = true
        tile.layer?.cornerRadius = Theme.Radius.appIcon
        tile.layer?.cornerCurve = .continuous
        tile.layer?.masksToBounds = true
        tile.layer?.borderWidth = 0.5
        tile.addContent(placeholderView
            .image(Theme.symbol(Theme.Symbol.appPlaceholder, size: 22, weight: .light))
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
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
                bundleLabel
                    .font(Theme.Font.caption)
                    .textColor(.secondaryLabelColor)
                    .lineBreakMode(.byTruncatingMiddle)
                    .accessibilityIdentifier(Identifier.bundle)
                HStack(alignment: .center, spacing: Theme.Spacing.tight) {
                    deviceSymbol
                        .contentTintColor(.secondaryLabelColor)
                        .accessibilityIdentifier(Identifier.deviceSymbol)
                    deviceLabel
                        .font(Theme.Font.caption)
                        .textColor(.secondaryLabelColor)
                        .lineBreakMode(.byTruncatingTail)
                        .accessibilityIdentifier(Identifier.device)
                }
                compatibilityLabel
                    .font(Theme.Font.caption)
                    .textColor(.secondaryLabelColor)
                    .lineBreakMode(.byTruncatingTail)
                    .accessibilityIdentifier(Identifier.compatibility)
            }
            Spacer()
            chevron
                .image(Theme.symbol(Theme.Symbol.chevron, size: 11, weight: .semibold))
                .contentTintColor(.tertiaryLabelColor)
                .accessibilityIdentifier(Identifier.chevron)
        }
        .padding(horizontal: Theme.Spacing.small, vertical: 6)
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

    func configure(with entry: AppEntry) {
        let presentation = AppEntryPresentation(entry)
        nameLabel.stringValue = presentation.name
        show(presentation.version, in: versionLabel)
        show(presentation.bundleID, in: bundleLabel)
        show(presentation.deviceLine, in: deviceLabel)
        deviceSymbol.image = Theme.symbol(presentation.deviceSymbolName, size: 10)
        deviceSymbol.isHidden = presentation.deviceLine == nil
        iconView.image = entry.icon?.makeImage()
        placeholderView.isHidden = iconView.image != nil

        badge.show(presentation.badge)
        show(presentation.compatibility, in: compatibilityLabel)
        chevron.isHidden = presentation.isDimmed
        // Dimmed: it is listed, but it is not a choice.
        alphaValue = presentation.isDimmed ? 0.55 : 1
    }

    /// Shows `text` in `label`, or hides the label when there is nothing to show.
    private func show(_ text: String?, in label: NSTextField) {
        label.stringValue = text ?? ""
        label.isHidden = text == nil
    }
}
