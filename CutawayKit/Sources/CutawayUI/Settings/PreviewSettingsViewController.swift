import AppKit
import Combine
import CutawayModel
import CutawayScene
import DeclarativeAppKit
import DeclarativeCombine

/// The settings window's Preview page (C-PREF-01): how a new inspection starts. Every change
/// is kept at once.
@MainActor
final class PreviewSettingsViewController: NSViewController {
    static let modeIdentifier = "settings.mode"
    static let spacingSliderIdentifier = "settings.spacing.slider"
    static let spacingFieldIdentifier = "settings.spacing.field"
    static let showsHiddenIdentifier = "settings.showsHidden"
    static let showsBordersIdentifier = "settings.showsBorders"
    static let restoreIdentifier = "settings.restore"

    let settings: AppSettings
    private(set) lazy var spacingField: NSTextField = .init(string: "").configure {
        // Leaving the field commits it, as Return does.
        $0.cell?.sendsActionOnEndEditing = true
    }

    init(settings: AppSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
        title = localized("settings.tab.preview")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let grid = NSGridView(views: [
            [Self.label(localized("settings.newInspectionMode")), makeModeControl()],
            [Self.label(localized("settings.layerSpacing")), makeSpacingRow()],
            [Self.label(localized("settings.layers")), makeLayersColumn()],
            [NSGridCell.emptyContentView, Self.help(
                localized("settings.explanation"))],
        ]).configure {
            $0.rowSpacing = 14
            $0.columnSpacing = Theme.Spacing.medium
            $0.column(at: 0).xPlacement = .trailing
            $0.rowAlignment = .firstBaseline
        }
        view = NSView().configure {
            $0.addVStack(alignment: .leading, spacing: 20) {
                grid
                NSButton(title: localized("settings.restoreDefaults"), target: nil, action: nil)
                    .accessibilityIdentifier(Self.restoreIdentifier)
                    .bind(\.isEnabled, to: settings.$isShowingPreviewDefaults.map { !$0 })
                    .sink(\.clickPublisher) { [weak settings] in
                        settings?.restorePreviewDefaults()
                    }
            }
            .padding(top: 24, leading: 40, bottom: 20, trailing: 40)
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        preferredContentSize = view.fittingSize
    }

    // MARK: - Rows

    private func makeModeControl() -> NSSegmentedControl {
        NSSegmentedControl(labels: ["2D", "3D"], trackingMode: .selectOne, target: nil, action: nil)
            .configure {
                $0.setWidth(52, forSegment: 0)
                $0.setWidth(52, forSegment: 1)
            }
            .accessibilityIdentifier(Self.modeIdentifier)
            .bind(\.selectedSegment, to: settings.$newInspectionMode.map { $0 == .twoD ? 0 : 1 })
            .sink(\.selectedSegmentPublisher) { [weak settings] segment in
                settings?.newInspectionMode = segment == 0 ? .twoD : .threeD
            }
    }

    private func makeSpacingRow() -> NSView {
        HStack(alignment: .center, spacing: 10) {
            NSSlider()
                .configure {
                    $0.minValue = Camera.spacingRange.lowerBound
                    $0.maxValue = Camera.spacingRange.upperBound
                    $0.isContinuous = true
                }
                .accessibilityIdentifier(Self.spacingSliderIdentifier)
                .bind(\.doubleValue, to: settings.$layerSpacing)
                .sink(\.doubleValuePublisher) { [weak settings] value in
                    settings?.layerSpacing = value
                }
                .frame(width: 190)
            spacingField
                .alignment(.right)
                .font(.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular))
                .accessibilityIdentifier(Self.spacingFieldIdentifier)
                .bind(\.stringValue, to: settings.$layerSpacing.map(Self.spacingText))
                .sink(\.actionPublisher) { [weak self] in self?.spacingFieldDidCommit() }
                .frame(width: 48)
            NSTextField(labelWithString: "pt")
                .textColor(.secondaryLabelColor)
        }
    }

    private func makeLayersColumn() -> NSView {
        VStack(alignment: .leading, spacing: 7) {
            Self.checkbox(localized("settings.showHiddenLayers"))
                .accessibilityIdentifier(Self.showsHiddenIdentifier)
                .bind(\.state, to: settings.$showsHiddenLayers.map { $0 ? .on : .off })
                .sink(\.statePublisher) { [weak settings] state in
                    settings?.showsHiddenLayers = state == .on
                }
            Self.checkbox(localized("settings.showBorders"))
                .accessibilityIdentifier(Self.showsBordersIdentifier)
                .bind(\.state, to: settings.$showsBorders.map { $0 ? .on : .off })
                .sink(\.statePublisher) { [weak settings] state in
                    settings?.showsBorders = state == .on
                }
        }
    }

    // MARK: - The spacing field

    /// Return or leaving the field: a number is rounded and kept within range; anything else
    /// puts the field back to the value it had.
    private func spacingFieldDidCommit() {
        let text = spacingField.stringValue.trimmingCharacters(in: .whitespaces)
        if let value = Double(text), value.isFinite {
            settings.layerSpacing = value
        }
        // The setting may not have changed (out of range again, or not a number): the field
        // shows the setting either way.
        spacingField.stringValue = Self.spacingText(settings.layerSpacing)
    }

    nonisolated static func spacingText(_ spacing: Double) -> String {
        String(Int(spacing.rounded()))
    }

    // MARK: - Pieces

    private static func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
            .alignment(.right)
    }

    private static func help(_ text: String) -> NSTextField {
        NSTextField(wrappingLabelWithString: text)
            .font(.systemFont(ofSize: NSFont.smallSystemFontSize))
            .textColor(.secondaryLabelColor)
            .frame(width: 330)
    }

    private static func checkbox(_ title: String) -> NSButton {
        NSButton(checkboxWithTitle: title, target: nil, action: nil)
    }
}
