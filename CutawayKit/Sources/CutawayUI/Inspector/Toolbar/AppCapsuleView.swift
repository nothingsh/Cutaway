import AppKit
import DeclarativeAppKit

/// The app in the toolbar (C-WIN-06): one glass capsule with the app's icon, its name and a
/// subtitle, which together are the button that shows the app list; then a divider and the
/// refresh and save buttons; and along its bottom edge a hairline for what is under way. An
/// archive's capsule has only the name and the subtitle (C-ARCH-05).
final class AppCapsuleView: NSView {
    static let identifier = "toolbar.capsule"
    static let nameIdentifier = "toolbar.capsule.name"
    static let titleIdentifier = "toolbar.capsule.title"
    static let subtitleIdentifier = "toolbar.capsule.subtitle"
    static let refreshIdentifier = "toolbar.capsule.refresh"
    static let saveIdentifier = "toolbar.capsule.save"
    static let progressIdentifier = "toolbar.capsule.progress"
    static let height: CGFloat = 40
    /// The widest the name and the subtitle get before they are cut short.
    static let textMaximumWidth: CGFloat = 220
    /// How firmly the name and the subtitle keep their width: the toolbar sizes its items
    /// with constraints of its own, and a text that gave way easily was cut to "…".
    static let textHolds = NSLayoutConstraint.Priority(rawValue: 740)

    let isArchive: Bool
    /// The name's part: the icon, the name and the subtitle. It shows the app list.
    let nameButton = CapsuleButton()
    let titleField = NSTextField(labelWithString: "")
    /// The subtitle; while it offers to show a saved archive, a click on it does that.
    let subtitleButton = SubtitleButton()
    let refreshButton = CapsuleButton()
    let saveButton = CapsuleButton()
    let progressBar = ProgressBarView()

    var onShowApps: () -> Void = {}
    var onRefresh: () -> Void = {}
    var onSave: () -> Void = {}
    var onCancelSave: () -> Void = {}
    var onReveal: (URL) -> Void = { _ in }

    /// What the capsule shows now.
    private(set) var state: AppCapsuleState?
    /// How wide the name and the subtitle are, fixed when the capsule is made (see
    /// `textWidth`).
    let textWidth: CGFloat

    /// The capsule sits in the toolbar's own glass (the item is bordered), as the 2D / 3D
    /// switch does. `subtitle` is what it says at rest: the device and system, or the
    /// archive's details.
    init(title: String, subtitle: String, icon: NSImage?, isArchive: Bool) {
        self.isArchive = isArchive
        textWidth = Self.textWidth(title: title, subtitle: subtitle, isArchive: isArchive)
        super.init(frame: .zero)

        titleField.stringValue = title
        nameButton.setAccessibilityLabel(title)
        nameButton.target = self
        nameButton.action = #selector(nameClicked)
        nameButton.isEnabled = !isArchive
        subtitleButton.target = self
        subtitleButton.action = #selector(subtitleClicked)
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked)
        saveButton.target = self
        saveButton.action = #selector(saveClicked)
        nameButton.addContent(HStack(alignment: .center, spacing: 8) {
            NSImageView()
                .configure {
                    $0.imageScaling = .scaleProportionallyUpOrDown
                    $0.wantsLayer = true
                    $0.layer?.cornerRadius = 6
                    $0.layer?.cornerCurve = .continuous
                    $0.layer?.masksToBounds = true
                }
                .image(icon ?? Theme.symbol(Theme.Symbol.appPlaceholder, size: 16))
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 4) {
                    titleField
                        .font(Self.titleFont)
                        .lineBreakMode(.byTruncatingTail)
                        .compressionResistancePriority(Self.textHolds, for: .horizontal)
                        .accessibilityIdentifier(Self.titleIdentifier)
                    NSImageView()
                        .image(Theme.symbol(Theme.Symbol.showApps, size: 8, weight: .bold))
                        .contentTintColor(.secondaryLabelColor)
                        .configure { $0.isHidden = isArchive }
                }
                subtitleButton
                    .accessibilityIdentifier(Self.subtitleIdentifier)
            }
        }
        .padding(top: 0, leading: 4, bottom: 0, trailing: 10))

        addHStack(alignment: .center, spacing: 0) {
            nameButton
                .accessibilityIdentifier(Self.nameIdentifier)
                .toolTip(isArchive ? nil : localized("toolbar.apps.tooltip"))
                .frame(height: 32)
            Spacer().frame(width: 2)
            NSBox().configure { $0.boxType = .separator; $0.isHidden = isArchive }
                .frame(width: 1, height: 18)
            Spacer().frame(width: 4)
            refreshButton
                .image(Theme.symbol(Theme.Symbol.refresh, size: 13, weight: .medium,
                                    description: localized("toolbar.refresh.label")))
                .toolTip(localized("toolbar.refresh.label"))
                .accessibilityIdentifier(Self.refreshIdentifier)
                .configure { $0.isHidden = isArchive }
                .frame(width: 30, height: 30)
            saveButton
                .accessibilityIdentifier(Self.saveIdentifier)
                .configure { $0.isHidden = isArchive }
                .frame(width: 30, height: 30)
        }
        .padding(top: 0, leading: 4, bottom: 0, trailing: isArchive ? 4 : 5)

        pinParts()
        setAccessibilityIdentifier(Self.identifier)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The capsule's height, the texts' widest, and the hairline along its bottom edge.
    private func pinParts() {
        // The toolbar measures an item once, when it is put in, and does not follow a later
        // change of its width: the texts' column has its width from the start.
        subtitleButton.widthAnchor.constraint(equalToConstant: textWidth).isActive = true
        titleField.widthAnchor.constraint(lessThanOrEqualToConstant: textWidth - Self.chevronRoom)
            .isActive = true
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.setAccessibilityIdentifier(Self.progressIdentifier)
        progressBar.isHidden = true
        addSubview(progressBar)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            progressBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            progressBar.heightAnchor.constraint(equalToConstant: 2),
        ])
    }

    /// Shows a state of the inspection.
    func show(_ state: AppCapsuleState) {
        guard state != self.state else { return }
        self.state = state
        let color: NSColor = switch state.tone {
        case .plain: .secondaryLabelColor
        case .progress: .controlAccentColor
        case .done: .systemGreen
        }
        subtitleButton.show(state.subtitle, color: color)
        if case .reveal = state.saveAction {
            subtitleButton.isEnabled = true
            subtitleButton.toolTip = localized("preview.showInFinder")
        } else {
            subtitleButton.isEnabled = false
            subtitleButton.toolTip = nil
        }
        progressBar.isHidden = state.progress == nil
        progressBar.fraction = state.progress ?? 0
        progressBar.setAccessibilityLabel(state.subtitle)

        refreshButton.isEnabled = state.canRefresh
        refreshButton.contentTintColor = state.isRefreshing ? .controlAccentColor : nil
        saveButton.isEnabled = state.canSave
        let (symbol, description): (String, String) = switch state.saveAction {
        case .save: (Theme.Symbol.saveArchive, localized("toolbar.saveArchive.tooltip"))
        case .cancel: (Theme.Symbol.cancelSave, localized("capsule.cancelSaving"))
        case .reveal: (Theme.Symbol.saved, localized("preview.showInFinder"))
        }
        saveButton.image = Theme.symbol(symbol, size: 13, weight: .medium, description: description)
        saveButton.toolTip = description
        saveButton.contentTintColor = switch state.saveAction {
        case .save: nil
        case .cancel: .controlAccentColor
        case .reveal: .systemGreen
        }
        saveButton.isLatched = state.saveAction == .cancel
    }

    /// The room the ▾ and its gap take after the name.
    static let chevronRoom: CGFloat = 12
    static let titleFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
    static let subtitleFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    /// The width of the name and subtitle column: room for the name and the ▾, the subtitle at
    /// rest, and each thing the subtitle can say while the inspection goes (four-digit counts),
    /// at most `textMaximumWidth`.
    static func textWidth(title: String, subtitle: String, isArchive: Bool) -> CGFloat {
        // Measured as the controls measure themselves, which is a little more than the text.
        let titleField = NSTextField(labelWithString: title)
        titleField.font = titleFont
        let measure = SubtitleButton()
        func width(_ text: String) -> CGFloat {
            measure.show(text, color: .secondaryLabelColor)
            return ceil(measure.intrinsicContentSize.width)
        }
        var widths = [
            ceil(titleField.intrinsicContentSize.width) + (isArchive ? 0 : chevronRoom), width(subtitle),
        ]
        if !isArchive {
            let count = PreviewPaneText.countText(8_888, of: 8_888)
            widths += [
                localized("capsule.screenshots", count), localized("capsule.saving", count),
                localized("capsule.savingStarted"), localized("capsule.saved"),
            ].map(width)
        }
        return min(widths.max() ?? 0, textMaximumWidth)
    }

    @objc private func nameClicked() {
        guard !isArchive else { return }
        onShowApps()
    }

    @objc private func subtitleClicked() {
        if case .reveal(let url) = state?.saveAction { onReveal(url) }
    }

    @objc private func refreshClicked() {
        onRefresh()
    }

    @objc private func saveClicked() {
        switch state?.saveAction {
        case .cancel: onCancelSave()
        case .reveal(let url): onReveal(url)
        case .save, nil: onSave()
        }
    }
}

/// A button of the capsule: plain until the pointer is over it, then a rounded fill; the
/// fill stays while it is latched, as the save button is while saving.
final class CapsuleButton: NSButton {
    private var isHovered = false {
        didSet { refreshFill() }
    }

    var isLatched = false {
        didSet { refreshFill() }
    }

    private var trackingArea: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        wantsLayer = true
        layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The frame is the size the layout gives it: a borderless button's own insets made a
    /// 30-point button 37 points tall, and its round fill an oval.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override var isEnabled: Bool {
        didSet { refreshFill() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshFill()
    }

    /// Whether the fill shows.
    var showsFill: Bool { isLatched || (isHovered && isEnabled) }

    private func refreshFill() {
        var color: CGColor?
        if showsFill {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                color = NSColor.labelColor.withAlphaComponent(0.09).cgColor
            }
        }
        layer?.backgroundColor = color
    }

    /// The name's part holds views of its own: a click anywhere in it is the button's, except
    /// on a subtitle that takes clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if let subtitle = hit as? SubtitleButton, subtitle.isEnabled { return subtitle }
        return self
    }
}

/// The capsule's subtitle: a line of text that is a button only while it offers to show the
/// saved archive. Otherwise clicks go through it to the name.
final class SubtitleButton: NSButton {
    init() {
        super.init(frame: .zero)
        isBordered = false
        imagePosition = .noImage
        lineBreakMode = .byTruncatingTail
        alignment = .left
        setContentCompressionResistancePriority(AppCapsuleView.textHolds, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    /// Writes `text` in `color`: a borderless button would draw its title in the control's
    /// colour, dimmed while disabled.
    func show(_ text: String, color: NSColor) {
        attributedTitle = NSAttributedString(string: text, attributes: [
            .font: AppCapsuleView.subtitleFont,
            .foregroundColor: color,
        ])
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isEnabled ? super.hitTest(point) : nil
    }
}
