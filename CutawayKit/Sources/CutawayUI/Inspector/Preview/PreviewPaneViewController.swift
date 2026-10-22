import AppKit
import Combine
import CutawayModel
import CutawayRender
import CutawayScene
import DeclarativeAppKit
import DeclarativeCombine

/// The preview and the panels that float over it: a notice at the top (C-DET-04),
/// "Loading layers…" in the middle while
/// there is no tree yet, the notice of a lost connection (C-WIN-03), and at the bottom right
/// the controls of what the preview shows (C-PREV-07 to C-PREV-09, C-PREV-17). Under them all is the canvas, which runs
/// up under the toolbar in
/// the preview's colour.
final class PreviewPaneViewController: NSViewController {
    static let noticeIdentifier = "preview.notice"
    static let loadingIdentifier = "preview.loading"
    static let disconnectedIdentifier = "preview.disconnected"
    static let showAppsIdentifier = "preview.showApps"
    static let disconnectedTextIdentifier = "preview.disconnected.text"
    static let shieldIdentifier = "preview.shield"
    static let controlsIdentifier = "preview.controls"
    static let showHiddenIdentifier = "preview.showHidden"
    static let bordersIdentifier = "preview.borders"
    static let spacingIdentifier = "preview.spacing"
    static let resetIdentifier = "preview.reset"
    static let canvasIdentifier = "preview.canvas"
    static let archiveFailedIdentifier = "preview.archiveFailed"
    static let archiveFailedTextIdentifier = "preview.archiveFailed.text"
    static let archiveFailedOKIdentifier = "preview.archiveFailed.ok"
    static let screenshotFailedIdentifier = "preview.screenshotFailed"
    static let screenshotFailedTextIdentifier = "preview.screenshotFailed.text"
    static let screenshotFailedOKIdentifier = "preview.screenshotFailed.ok"
    /// How far the panels keep from the preview's edges.
    static let inset: CGFloat = 12
    /// The widest the notice gets before its text wraps.
    private static let noticeMaximumWidth: CGFloat = 560
    /// What the notice's panel adds around its text: the padding, the symbol and the gap.
    private static let noticeChrome: CGFloat = 2 * Theme.Spacing.medium + 16 + Theme.Spacing.small

    let previewController: PreviewViewController
    private let store: InspectionStore
    let viewModel: PreviewPaneViewModel
    /// Called by the button of the lost connection's notice.
    var onShowApps: () -> Void = {}
    /// The notice's text. A wrapping label has no width of its own in a window, so it is given
    /// the width to wrap at.
    private let noticeLabel = NSTextField(wrappingLabelWithString: "")
    /// The failed save's text, which wraps like the notice's.
    private let archiveFailedLabel = NSTextField(wrappingLabelWithString: "")
    /// The failed export's text, likewise.
    private let screenshotFailedLabel = NSTextField(wrappingLabelWithString: "")
    /// The borders' pull-down among the controls (C-PREV-17).
    let bordersButton = BordersButton.make()
    private var cancellables = Set<AnyCancellable>()
    /// The controls at the bottom: the layers keep clear of them at zoom 1.
    private weak var controlsPanel: NSView?
    /// Follows the toolbar's height.
    private var layoutRectObservation: NSKeyValueObservation?

    init(store: InspectionStore, appName: String) {
        self.store = store
        self.viewModel = PreviewPaneViewModel(store: store, appName: appName)
        self.previewController = PreviewViewController(store: store)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let root = NSView()
        // The whole pane, under the toolbar too: with the preview's colour the strip under
        // the toolbar and the preview are one surface.
        root.addContent(CanvasView().accessibilityIdentifier(Self.canvasIdentifier))
        addChild(previewController)
        // Under the toolbar too: the toolbar's capsules float over the layers (C-WIN-06). The
        // panels keep below the toolbar.
        root.addContent(previewController.view)

        let noticePanel = makeNoticePanel()
        let loadingPanel = makeLoadingPanel()
        let controlsPanel = makeControlsPanel()
        self.controlsPanel = controlsPanel

        // Over everything else: once the connection is lost the preview takes no more clicks.
        let shield = ClickShieldView()
            .accessibilityIdentifier(Self.shieldIdentifier)
            .bind(\.isHidden, to: viewModel.isDisconnected.map { !$0 })

        let disconnectedPanel = makeDisconnectedPanel()

        // Why an archive was not saved, at the top (C-ARCH-02); its progress and "Saved" are
        // the toolbar's (C-WIN-06).
        let archiveFailedPanel = makeArchiveFailedPanel()
        let screenshotFailedPanel = makeScreenshotFailedPanel()

        // At the top, under the notice or the lost connection: what was not saved or exported.
        let failures = PassThroughStackView(views: [archiveFailedPanel, screenshotFailedPanel])
        failures.orientation = .vertical
        failures.alignment = .centerX
        failures.spacing = Theme.Spacing.small
        failures.detachesHiddenViews = true

        for panel in [
            noticePanel, controlsPanel, loadingPanel, shield,
            disconnectedPanel, failures,
        ] as [NSView] {
            panel.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(panel)
        }
        let safe = root.safeAreaLayoutGuide
        let inset = Self.inset
        NSLayoutConstraint.activate([
            noticePanel.topAnchor.constraint(equalTo: safe.topAnchor, constant: inset),
            noticePanel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            noticePanel.widthAnchor.constraint(lessThanOrEqualToConstant: Self.noticeMaximumWidth),
            noticePanel.leadingAnchor.constraint(
                greaterThanOrEqualTo: root.leadingAnchor, constant: inset),

            failures.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            archiveFailedPanel.widthAnchor.constraint(
                lessThanOrEqualToConstant: Self.noticeMaximumWidth),
            screenshotFailedPanel.widthAnchor.constraint(
                lessThanOrEqualToConstant: Self.noticeMaximumWidth),
            failures.leadingAnchor.constraint(
                greaterThanOrEqualTo: root.leadingAnchor, constant: inset),

            controlsPanel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -inset),
            controlsPanel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -inset),

            loadingPanel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            loadingPanel.centerYAnchor.constraint(equalTo: root.centerYAnchor),

            shield.topAnchor.constraint(equalTo: root.topAnchor),
            shield.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            shield.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            shield.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            disconnectedPanel.topAnchor.constraint(equalTo: safe.topAnchor, constant: inset),
            disconnectedPanel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            disconnectedPanel.leadingAnchor.constraint(
                greaterThanOrEqualTo: root.leadingAnchor, constant: inset),
        ])
        placeFailures(failures, under: noticePanel, or: disconnectedPanel, in: root)
        view = root
        // The tags name the selected and the hovered layer on the preview (C-PREV-16).
        viewModel.tags
            .sink { [weak self] tags in self?.previewController.preview?.tags = tags }
            .store(in: &cancellables)
    }

    /// The failures go under whichever of the notice and the lost connection shows.
    private func placeFailures(
        _ failures: NSView, under noticePanel: NSView, or disconnectedPanel: NSView, in root: NSView
    ) {
        let safe = root.safeAreaLayoutGuide
        let inset = Self.inset
        let gap = Theme.Spacing.small
        let alone = failures.topAnchor.constraint(equalTo: safe.topAnchor, constant: inset)
        let underNotice = failures.topAnchor.constraint(
            equalTo: noticePanel.bottomAnchor, constant: gap)
        let underDisconnected = failures.topAnchor.constraint(
            equalTo: disconnectedPanel.bottomAnchor, constant: gap)
        Publishers.CombineLatest(viewModel.notice.map { $0 != nil }, viewModel.isDisconnected)
            .sink { notices, disconnected in
                NSLayoutConstraint.deactivate([alone, underNotice, underDisconnected])
                (disconnected ? underDisconnected : notices ? underNotice : alone).isActive = true
            }
            .store(in: &cancellables)
    }

    // MARK: - The panels

    /// At the top: why loading stopped (C-DET-04).
    private func makeNoticePanel() -> HUDView {
        let notice = viewModel.notice
        return HUDView(content: HStack(alignment: .top, spacing: Theme.Spacing.small) {
            NSImageView()
                .bind(\.image, to: viewModel.noticeSymbol.map { symbol -> NSImage? in
                    switch symbol {
                    case .notActive: return Self.tinted(symbol.name, .systemOrange)
                    case .failed: return Self.tinted(symbol.name, .systemYellow)
                    }
                })
                .frame(width: 16, height: 16)
            noticeLabel
                .font(.systemFont(ofSize: 12))
                // A wrapping label gives way as easily as the stack holds its content (250),
                // and the layout then squeezed it to a few points, out of the panel. It wraps
                // at its preferred width; the panel's own width is what keeps it narrow.
                .compressionResistancePriority(.defaultHigh, for: .horizontal)
                .accessibilityIdentifier(Self.noticeIdentifier)
                .bind(\.stringValue, to: notice.map { $0 ?? "" })
        }
        .padding(horizontal: Theme.Spacing.medium, vertical: Theme.Spacing.small))
            .bind(\.isHidden, to: notice.map { $0 == nil })
    }

    /// In the middle while there is no tree yet.
    private func makeLoadingPanel() -> HUDView {
        let isLoading = viewModel.isLoading
        return HUDView(content: HStack(alignment: .center, spacing: Theme.Spacing.small) {
            NSProgressIndicator()
                .configure {
                    $0.style = .spinning
                    $0.controlSize = .small
                    $0.isIndeterminate = true
                }
                .onReceive(isLoading) { spinner, loading in
                    loading ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
                }
            NSTextField(labelWithString: localized("preview.loadingLayers"))
                .font(.systemFont(ofSize: 12))
        }
        .padding(horizontal: Theme.Spacing.medium, vertical: Theme.Spacing.small))
            .accessibilityIdentifier(Self.loadingIdentifier)
            .bind(\.isHidden, to: isLoading.map { !$0 })
    }

    /// At the bottom right: what the preview shows (C-PREV-07 to C-PREV-09).
    private func makeControlsPanel() -> HUDView {
        let isConnected = viewModel.isConnected
        let spacingIsEnabled = viewModel.spacingIsEnabled
        let controls = HStack(alignment: .center, spacing: Theme.Spacing.small) {
            NSButton()
                .configure { $0.isBordered = false }
                .buttonType(.toggle)
                .image(Theme.symbol(
                    Theme.Symbol.hideHidden, size: 13,
                    description: localized("preview.showHiddenLayers")))
                .alternateImage(Theme.symbol(
                    Theme.Symbol.showHidden, size: 13,
                    description: localized("preview.showHiddenLayers")))
                .toolTip(localized("preview.showHiddenLayers"))
                .accessibilityIdentifier(Self.showHiddenIdentifier)
                .bind(\.state, to: store.$showsHiddenLayers.map { $0 ? .on : .off })
                .bind(\.isEnabled, to: isConnected)
                .sink(\.statePublisher) { [weak store] state in
                    store?.setShowsHiddenLayers(state == .on)
                }
            bordersButton
                .accessibilityIdentifier(Self.bordersIdentifier)
                .onReceive(store.$borders.combineLatest(store.$showsAllConstraintEnds)) {
                    button, shown in
                    BordersButton.show(shown.0, showsConstraintEnds: shown.1, on: button)
                }
                .bind(\.isEnabled, to: isConnected)
                .sink(\.indexOfSelectedItemPublisher) { [weak self] index in
                    guard let self else { return }
                    BordersButton.choose(index, of: self.bordersButton, in: self.store)
                }
            NSBox().configure { $0.boxType = .separator }
                .frame(width: 1, height: 16)
            NSImageView()
                .image(Theme.symbol(Theme.Symbol.threeD, size: 12))
                .contentTintColor(.secondaryLabelColor)
                .bind(\.alphaValue, to: spacingIsEnabled.map { $0 ? 1 : 0.4 })
            NSSlider()
                .configure {
                    $0.minValue = Camera.spacingRange.lowerBound
                    $0.maxValue = Camera.spacingRange.upperBound
                    $0.isContinuous = true
                }
                .controlSize(.small)
                .toolTip(localized("preview.layerSpacing"))
                .accessibilityIdentifier(Self.spacingIdentifier)
                .bind(\.doubleValue, to: store.$cameras.map(\.threeD.layerSpacing))
                .bind(\.isEnabled, to: spacingIsEnabled)
                .sink(\.doubleValuePublisher) { [weak store] value in
                    store?.setLayerSpacing(value)
                }
                .frame(width: 100)
            NSBox().configure { $0.boxType = .separator }
                .frame(width: 1, height: 16)
            // A word, not an arrow: the toolbar's refresh is one.
            NSButton()
                .configure { $0.isBordered = false }
                .title(localized("preview.reset"))
                .font(.systemFont(ofSize: 12, weight: .medium))
                .toolTip(localized("preview.reset.tooltip"))
                .accessibilityIdentifier(Self.resetIdentifier)
                .bind(\.isEnabled, to: isConnected)
                .sink(\.clickPublisher) { [weak store] in store?.resetCamera() }
        }
        return HUDView(content: controls.padding(
            top: 6, leading: Theme.Spacing.medium, bottom: 6, trailing: Theme.Spacing.medium))
            .configure { $0.takesPointer = true }
            .accessibilityIdentifier(Self.controlsIdentifier)
    }

    /// A panel of the shape most of them have: a tinted symbol, a line or two of text, and a
    /// button, which the panel takes the pointer for.
    private static func makeTextPanel(
        symbol: NSImage?, text: NSTextField, button: NSButton, identifier: String,
        spacing: CGFloat = Theme.Spacing.small, edgePadding: CGFloat = 5
    ) -> HUDView {
        HUDView(content: HStack(alignment: .center, spacing: spacing) {
            NSImageView()
                .image(symbol)
                .frame(width: 16, height: 16)
            text
            button
                .bezelStyle(.rounded)
                .controlSize(.small)
        }
        .padding(top: edgePadding, leading: Theme.Spacing.medium, bottom: edgePadding, trailing: edgePadding))
            .configure { $0.takesPointer = true }
            .accessibilityIdentifier(identifier)
    }

    /// At the top, in place of the notice: the connection is gone (C-WIN-03, C-WIN-04).
    private func makeDisconnectedPanel() -> HUDView {
        Self.makeTextPanel(
            symbol: Self.tinted(Theme.Symbol.disconnected, .systemRed),
            text: NSTextField(labelWithString: "")
                .font(.systemFont(ofSize: 12))
                .lineBreakMode(.byTruncatingTail)
                .compressionResistancePriority(.defaultLow, for: .horizontal)
                .accessibilityIdentifier(Self.disconnectedTextIdentifier)
                .bind(\.stringValue, to: viewModel.disconnectedText),
            button: NSButton()
                .title(localized("preview.showApps"))
                .accessibilityIdentifier(Self.showAppsIdentifier)
                .sink(\.clickPublisher) { [weak self] in self?.onShowApps() },
            identifier: Self.disconnectedIdentifier, spacing: 10, edgePadding: 6)
            .bind(\.isHidden, to: viewModel.isDisconnected.map { !$0 })
    }

    /// At the top: why the archive was not saved (C-ARCH-02).
    private func makeArchiveFailedPanel() -> HUDView {
        let failure = viewModel.failure
        return makeFailurePanel(
            archiveFailedLabel.bind(\.stringValue, to: failure.map { $0 ?? "" }),
            textIdentifier: Self.archiveFailedTextIdentifier, okIdentifier: Self.archiveFailedOKIdentifier,
            identifier: Self.archiveFailedIdentifier, dismiss: { [weak store] in store?.dismissArchiveSave() })
            .bind(\.isHidden, to: failure.map { $0 == nil })
    }

    /// At the top: why the screenshot was not exported (C-ARCH-06).
    private func makeScreenshotFailedPanel() -> HUDView {
        let screenshotFailure = viewModel.screenshotFailure
        return makeFailurePanel(
            screenshotFailedLabel.bind(\.stringValue, to: screenshotFailure.map { $0 ?? "" }),
            textIdentifier: Self.screenshotFailedTextIdentifier,
            okIdentifier: Self.screenshotFailedOKIdentifier, identifier: Self.screenshotFailedIdentifier,
            dismiss: { [weak store] in store?.dismissScreenshotExport() })
            .bind(\.isHidden, to: screenshotFailure.map { $0 == nil })
    }

    /// Why something was not done, with an OK button that forgets it.
    private func makeFailurePanel(
        _ label: NSTextField, textIdentifier: String, okIdentifier: String, identifier: String,
        dismiss: @escaping () -> Void
    ) -> HUDView {
        Self.makeTextPanel(
            symbol: Self.tinted(Theme.Symbol.archiveFailed, .systemOrange),
            text: label
                .font(.systemFont(ofSize: 12))
                // As the notice's.
                .compressionResistancePriority(.defaultHigh, for: .horizontal)
                .accessibilityIdentifier(textIdentifier),
            button: NSButton()
                .title(localized("preview.ok"))
                .accessibilityIdentifier(okIdentifier)
                .sink(\.clickPublisher) { dismiss() },
            identifier: identifier)
    }

    /// Wraps the notices at the room they have, and keeps the layers clear of the controls.
    override func viewDidLayout() {
        super.viewDidLayout()
        keepLayersClearOfControls()
        // The notice wraps at the room it has: at most its widest, within the insets.
        let room = min(Self.noticeMaximumWidth, view.bounds.width - 2 * Self.inset)
        let wrapWidth = max(room - Self.noticeChrome, 0)
        if noticeLabel.preferredMaxLayoutWidth != wrapWidth {
            noticeLabel.preferredMaxLayoutWidth = wrapWidth
        }
        // The failed save's panel has its OK button besides the symbol.
        let failedWrap = max(wrapWidth - 60, 0)
        for label in [archiveFailedLabel, screenshotFailedLabel]
            where label.preferredMaxLayoutWidth != failedWrap
        {
            label.preferredMaxLayoutWidth = failedWrap
        }
    }

    /// The toolbar's capsules float over the top of the preview and the controls over its
    /// bottom: at zoom 1 the layers fit between them (C-WIN-06). The toolbar is what the
    /// window's content layout rect leaves out; it changes without a layout of the pane, as
    /// the toolbar hides in full screen.
    private func keepLayersClearOfControls() {
        guard let controlsPanel, let preview = previewController.preview else { return }
        var top = 0.0
        if let window = preview.window {
            let visible = preview.convert(window.contentLayoutRect, from: nil)
            top = max(preview.bounds.maxY - visible.maxY, 0)
        }
        let bottom = controlsPanel.isHidden ? 0 : controlsPanel.frame.height + Self.inset
        preview.overlayInsets = Viewport.Insets(top: top, bottom: bottom)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        layoutRectObservation = view.window?.observe(\.contentLayoutRect) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.keepLayersClearOfControls() }
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        layoutRectObservation = nil
    }

    private static func tinted(_ name: String, _ color: NSColor) -> NSImage? {
        Theme.symbol(name, size: 13, weight: .medium)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
    }
}

/// A stack of panels that, like the panels, lets the pointer through where none takes it.
final class PassThroughStackView: NSStackView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

/// The surface under the preview and its panels, in the preview's background colour for the
/// view's appearance.
final class CanvasView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor = RenderStyle.preview(dark: dark).background.cgColor
    }

    // The pointer goes to the preview and the panels above.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
