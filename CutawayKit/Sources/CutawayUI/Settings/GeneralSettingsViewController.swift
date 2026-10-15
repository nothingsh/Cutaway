import AppKit
import Combine
import CutawayModel
import DeclarativeAppKit
import DeclarativeCombine

/// The settings window's General page: the interface's language (C-LOC-01) and Cutaway's
/// appearance (C-PREF-03). A language is kept at once and takes effect when Cutaway next
/// starts; a choice that changes the language offers to restart now. The appearance applies at
/// once.
@MainActor
final class GeneralSettingsViewController: NSViewController {
    static let languageIdentifier = "settings.language"
    static let appearanceIdentifier = "settings.appearance"
    static let restoreIdentifier = "settings.general.restore"

    /// Each language in itself, so that anyone can find their own.
    static let languageNames = [
        "en": "English", "zh-Hans": "简体中文", "zh-Hant": "繁體中文", "ja": "日本語", "ko": "한국어",
    ]

    let settings: AppSettings
    let language: LanguageSetting
    /// The language the interface is in now.
    let shownLanguage: String
    /// The system's preferred languages, read when a choice is made.
    let systemPreferences: () -> [String]
    /// Quits and opens Cutaway again.
    let restart: () -> Void
    /// The restart sheet while it is up.
    private(set) var restartAlert: NSAlert?

    private(set) lazy var languageButton: NSPopUpButton = .init(frame: .zero, pullsDown: false)
        .configure { button in
            button.addItem(withTitle: localized("settings.language.system"))
            button.menu?.addItem(.separator())
            for code in language.languages {
                button.addItem(withTitle: Self.languageNames[code] ?? code)
                button.lastItem?.representedObject = code
            }
        }

    /// The appearances in the pop-up's order; the system's first, then a separator.
    static let appearances: [AppSettings.Appearance] = [.system, .light, .dark]

    private(set) lazy var appearanceButton: NSPopUpButton = .init(frame: .zero, pullsDown: false)
        .configure { button in
            for appearance in Self.appearances {
                button.addItem(withTitle: Self.title(of: appearance))
                button.lastItem?.representedObject = appearance.rawValue
                if appearance == .system { button.menu?.addItem(.separator()) }
            }
        }

    private static func title(of appearance: AppSettings.Appearance) -> String {
        switch appearance {
        case .system: localized("settings.appearance.system")
        case .light: localized("settings.appearance.light")
        case .dark: localized("settings.appearance.dark")
        }
    }

    init(
        settings: AppSettings, language: LanguageSetting, shownLanguage: String,
        systemPreferences: @escaping () -> [String], restart: @escaping () -> Void
    ) {
        self.settings = settings
        self.language = language
        self.shownLanguage = shownLanguage
        self.systemPreferences = systemPreferences
        self.restart = restart
        super.init(nibName: nil, bundle: nil)
        title = localized("settings.tab.general")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let grid = NSGridView(views: [
            [
                NSTextField(labelWithString: localized("settings.language")).alignment(.right),
                languageButton
                    .accessibilityIdentifier(Self.languageIdentifier)
                    .sink(\.indexOfSelectedItemPublisher) { [weak self] _ in self?.languageButtonDidChange() }
                    .frame(width: 200),
            ],
            [
                NSGridCell.emptyContentView,
                NSTextField(wrappingLabelWithString: localized("settings.language.explanation"))
                    .font(.systemFont(ofSize: NSFont.smallSystemFontSize))
                    .textColor(.secondaryLabelColor)
                    .frame(width: 330),
            ],
            [
                NSTextField(labelWithString: localized("settings.appearance")).alignment(.right),
                appearanceButton
                    .accessibilityIdentifier(Self.appearanceIdentifier)
                    .sink(\.indexOfSelectedItemPublisher) { [weak self] _ in self?.appearanceButtonDidChange() }
                    .frame(width: 200),
            ],
            [
                NSGridCell.emptyContentView,
                NSTextField(wrappingLabelWithString: localized("settings.appearance.explanation"))
                    .font(.systemFont(ofSize: NSFont.smallSystemFontSize))
                    .textColor(.secondaryLabelColor)
                    .frame(width: 330),
            ],
        ]).configure {
            $0.rowSpacing = 8
            $0.columnSpacing = Theme.Spacing.medium
            $0.column(at: 0).width = 190
            $0.column(at: 0).xPlacement = .trailing
            $0.rowAlignment = .firstBaseline
            // Apart from the language's explanation, as the two settings are apart.
            $0.row(at: 2).topPadding = 12
        }
        view = NSView().configure {
            $0.addVStack(alignment: .leading, spacing: 20) {
                grid
                NSButton(title: localized("settings.restoreDefaults"), target: nil, action: nil)
                    .accessibilityIdentifier(Self.restoreIdentifier)
                    .bind(\.isEnabled, to: language.$choice.combineLatest(settings.$appearance)
                        .map { $0 != nil || $1 != .system })
                    .sink(\.clickPublisher) { [weak self] in self?.restoreDefaults() }
            }
            .padding(top: 24, leading: 40, bottom: 20, trailing: 40)
        }
        showChoice()
        showAppearance()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        preferredContentSize = view.fittingSize
    }

    // MARK: - Choosing

    private func languageButtonDidChange() {
        choose(languageButton.selectedItem?.representedObject as? String)
    }

    /// Keeps the choice, then offers to restart when Cutaway would start in another language.
    func choose(_ choice: String?) {
        language.choose(choice)
        showChoice()
        let next = language.resolved(systemPreferences: systemPreferences())
        if next != shownLanguage {
            askToRestart(into: next)
        }
    }

    /// Both back to the system's: the appearance at once, the language as a choice of it is.
    func restoreDefaults() {
        settings.appearance = .system
        showAppearance()
        if language.choice != nil { choose(nil) }
    }

    private func appearanceButtonDidChange() {
        let raw = appearanceButton.selectedItem?.representedObject as? String
        settings.appearance = raw.flatMap(AppSettings.Appearance.init(rawValue:)) ?? .system
    }

    private func showAppearance() {
        appearanceButton.selectItem(at: appearanceButton.indexOfItem(
            withRepresentedObject: settings.appearance.rawValue))
    }

    private func showChoice() {
        let index = language.choice.flatMap { languageButton.indexOfItem(withRepresentedObject: $0) }
        languageButton.selectItem(at: index ?? 0)
    }

    /// A sheet on the settings window; the pop-up cannot be used again while it is up.
    private func askToRestart(into next: String) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = localized("settings.restart.title", Self.languageNames[next] ?? next)
        alert.informativeText = localized("settings.restart.message")
        alert.addButton(withTitle: localized("settings.restart.now"))
        alert.addButton(withTitle: localized("settings.restart.later"))
        restartAlert = alert
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.restartAlert = nil
            if response == .alertFirstButtonReturn { self?.restart() }
        }
    }
}
