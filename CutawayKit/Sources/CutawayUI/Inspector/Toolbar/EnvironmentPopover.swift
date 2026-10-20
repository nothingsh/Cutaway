import AppKit
import Combine
import CutawayModel
import CutawayWire
import DeclarativeAppKit
import DeclarativeCombine

/// What the toolbar's Environment button shows (C-ENV-01): a row for each kind of trait the
/// app can override, each with the value the app shows now under it, Reset, and why the last
/// change failed (C-ENV-02).
@MainActor
final class EnvironmentPopoverController: NSViewController {
    static let resetIdentifier = "environment.reset"
    static let failureIdentifier = "environment.failure"
    static let sendingIdentifier = "environment.sending"

    /// One kind's controls.
    struct Row {
        let kind: TraitKind
        /// The choice among App's Own and the values; nil for the text size.
        var segments: NSSegmentedControl?
        /// The text size's: whether it is overridden, and which of the twelve sizes.
        var override: NSButton?
        var slider: NSSlider?
        var size: NSTextField?
        let now: NSTextField
    }

    let store: InspectionStore
    /// The rows, in the order shown.
    private(set) var rows: [Row] = []
    private let rowsStack = VStack(alignment: .leading, spacing: 12) {}
    private var cancellables = Set<AnyCancellable>()

    private(set) lazy var resetButton: NSButton = .init(
        title: localized("environment.reset"), target: nil, action: nil
    ).configure {
        $0.bezelStyle = .push
    }

    private(set) lazy var spinner: NSProgressIndicator = .init().configure {
        $0.style = .spinning
        $0.controlSize = .small
        $0.isDisplayedWhenStopped = false
    }

    private(set) lazy var failureLabel: NSTextField = .init(wrappingLabelWithString: "")

    init(store: InspectionStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = NSView().configure {
            $0.addVStack(alignment: .leading, spacing: 12) {
                rowsStack
                NSBox().configure { $0.boxType = .separator }
                VStack(alignment: .leading, spacing: 8) {
                    failureLabel
                        .font(.systemFont(ofSize: NSFont.smallSystemFontSize))
                        .textColor(.systemRed)
                        .accessibilityIdentifier(Self.failureIdentifier)
                        .frame(width: 330)
                    HStack(alignment: .center, spacing: 8) {
                        resetButton
                            .controlSize(.small)
                            .accessibilityIdentifier(Self.resetIdentifier)
                            .sink(\.clickPublisher) { [weak store] in store?.resetEnvironment() }
                        spinner
                            .accessibilityIdentifier(Self.sendingIdentifier)
                            .accessibilityLabel(localized("environment.sending"))
                    }
                }
            }
            .padding(top: 14, leading: 14, bottom: 12, trailing: 14)
        }
        Publishers.CombineLatest(store.$environment, store.$archiveSave)
            .sink { [weak self] state, _ in self?.apply(state) }
            .store(in: &cancellables)
    }

    // MARK: - Following the store

    private func apply(_ state: EnvironmentState) {
        let controls = state.controls
        let kinds = controls?.overridable ?? rows.map(\.kind)
        if kinds != rows.map(\.kind) { build(kinds) }
        // Once disconnected the app has its own traits back (C-ENV-03).
        let shown = controls?.shown ?? .unspecified
        let canChange = store.canChangeEnvironment
        for row in rows {
            update(row, shown: shown, controls: controls, canChange: canChange)
        }
        resetButton.isEnabled = canChange && controls?.isOverriding == true
        if controls?.isSending == true {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
        failureLabel.stringValue = controls?.failure.map(EnvironmentNames.failure) ?? ""
        failureLabel.isHidden = controls?.failure == nil
    }

    private func update(
        _ row: Row, shown: Traits, controls: EnvironmentControls?, canChange: Bool
    ) {
        let current = controls?.environment.current ?? .unspecified
        row.now.stringValue = EnvironmentNames.now(row.kind, in: current)
        let overridden = controls?.environment.overrides.isSpecified(row.kind) == true
        row.now.textColor = overridden ? .controlAccentColor : .secondaryLabelColor
        if let segments = row.segments {
            let choices = EnvironmentNames.choices(of: row.kind)
            segments.selectedSegment = choices.firstIndex(of: shown[row.kind]) ?? 0
            segments.isEnabled = canChange
        }
        if let override = row.override, let slider = row.slider, let size = row.size {
            let isOverridden = shown.isSpecified(.contentSizeCategory)
            override.state = isOverridden ? .on : .off
            override.isEnabled = canChange
            // Not overridden: the slider rests on the app's own size.
            let resting = isOverridden ? shown.contentSizeCategory : current.contentSizeCategory
            let index = EnvironmentNames.textSizes.firstIndex(of: resting)
                ?? EnvironmentNames.textSizes.firstIndex(of: .large) ?? 0
            slider.integerValue = index
            slider.isEnabled = canChange && isOverridden
            size.stringValue = EnvironmentNames.shortName(of: EnvironmentNames.textSizes[index])
        }
    }

    // MARK: - The rows

    private func build(_ kinds: [TraitKind]) {
        for view in rowsStack.arrangedSubviews { view.removeFromSuperview() }
        rows = kinds.map(makeRow)
        for row in rows {
            let control: NSView = if let segments = row.segments {
                segments
            } else if let override = row.override, let slider = row.slider, let size = row.size {
                VStack(alignment: .leading, spacing: 5) {
                    override
                    HStack(alignment: .center, spacing: 8) {
                        slider.frame(width: 190)
                        size
                            .font(.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold))
                            .frame(width: 40)
                    }
                }
            } else {
                NSView()
            }
            rowsStack.addArrangedSubview(HStack(alignment: .top, spacing: 12) {
                NSTextField(labelWithString: EnvironmentNames.title(of: row.kind))
                    .frame(width: 104)
                VStack(alignment: .leading, spacing: 3) {
                    control
                    row.now
                        .font(.systemFont(ofSize: NSFont.smallSystemFontSize - 0.5))
                        .textColor(.secondaryLabelColor)
                }
            })
        }
    }

    private func makeRow(_ kind: TraitKind) -> Row {
        let now = NSTextField(labelWithString: "")
        guard kind == .contentSizeCategory else {
            let choices = EnvironmentNames.choices(of: kind)
            let segments = NSSegmentedControl(
                labels: choices.map(EnvironmentNames.name(of:)), trackingMode: .selectOne,
                target: nil, action: nil)
                .controlSize(.small)
                .accessibilityIdentifier("environment.\(kind)")
                .sink(\.selectedSegmentPublisher) { [weak store] segment in
                    guard choices.indices.contains(segment) else { return }
                    store?.setEnvironment(kind, to: choices[segment])
                }
            return Row(kind: kind, segments: segments, now: now)
        }
        let override = NSButton(
            checkboxWithTitle: localized("environment.override"), target: nil, action: nil)
            .accessibilityIdentifier("environment.textSize.override")
        let slider = NSSlider().configure {
            $0.numberOfTickMarks = EnvironmentNames.textSizes.count
            $0.allowsTickMarkValuesOnly = true
            $0.isContinuous = true
        }
        .minValue(0)
        .maxValue(Double(EnvironmentNames.textSizes.count - 1))
        .accessibilityIdentifier("environment.textSize.slider")
        let size = NSTextField(labelWithString: "")
        override.sink(\.statePublisher) { [weak self, weak slider] state in
            guard let self, let slider else { return }
            self.overrideTextSize(state == .on, at: slider.integerValue)
        }
        slider.sink(\.doubleValuePublisher) { [weak self] value in
            // The name follows a drag; the size is sent when the slider is let go.
            self?.sliderMoved(to: Int(value.rounded()), isFinal: Self.endsAMove(NSApp.currentEvent?.type))
        }
        return Row(kind: kind, override: override, slider: slider, size: size, now: now)
    }

    /// Ticking Override keeps the size the slider is at; unticking gives the app its own.
    func overrideTextSize(_ isOn: Bool, at index: Int) {
        let sizes = EnvironmentNames.textSizes
        let size = isOn ? sizes[min(max(index, 0), sizes.count - 1)] : .unspecified
        store.setEnvironment(.contentSizeCategory, to: .contentSizeCategory(size))
    }

    /// The slider moved to a size: named at once, sent when `isFinal`.
    func sliderMoved(to index: Int, isFinal: Bool) {
        let sizes = EnvironmentNames.textSizes
        let size = sizes[min(max(index, 0), sizes.count - 1)]
        rows.first { $0.kind == .contentSizeCategory }?.size?.stringValue = EnvironmentNames.shortName(of: size)
        guard isFinal else { return }
        store.setEnvironment(.contentSizeCategory, to: .contentSizeCategory(size))
    }

    /// Whether a slider's action, sent during this kind of event, ends the move: not while
    /// the mouse is down on it.
    nonisolated static func endsAMove(_ event: NSEvent.EventType?) -> Bool {
        event != .leftMouseDown && event != .leftMouseDragged
    }
}
