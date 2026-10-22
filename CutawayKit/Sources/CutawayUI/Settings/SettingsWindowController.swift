import AppKit
import CutawayModel
import CutawayProjects

/// The settings window (C-PREF-01): one only, fixed in size, closed but never minimized or
/// zoomed. Its pages are tabs in the toolbar, General (C-LOC-01, C-PREF-03), Preview and
/// Projects (C-SRC-01); the window is titled with the page shown and opens on the page last
/// shown.
@MainActor
final class SettingsWindowController: NSWindowController {
    let generalPage: GeneralSettingsViewController
    let previewPage: PreviewSettingsViewController
    let projectsPage: ProjectsSettingsViewController
    let tabs: NSTabViewController

    /// `shownLanguage` and `systemPreferences` are for tests: the language the interface is in
    /// and the system's languages, which decide whether a choice offers to restart.
    init(
        settings: AppSettings, language: LanguageSetting, projects: ProjectSources,
        shownLanguage: String = Localization.language,
        systemPreferences: @escaping () -> [String] = { LanguageSetting.systemPreferences },
        restart: @escaping () -> Void
    ) {
        generalPage = GeneralSettingsViewController(
            settings: settings, language: language, shownLanguage: shownLanguage,
            systemPreferences: systemPreferences, restart: restart)
        previewPage = PreviewSettingsViewController(settings: settings)
        projectsPage = ProjectsSettingsViewController(projects: projects)
        tabs = SettingsTabViewController(settings: settings)
        tabs.tabStyle = .toolbar
        for (page, symbol) in [
            (generalPage as NSViewController, Theme.Symbol.generalSettings),
            (previewPage, Theme.Symbol.previewSettings),
            (projectsPage, Theme.Symbol.projectsSettings),
        ] {
            let item = NSTabViewItem(viewController: page)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: page.title)
            tabs.addTabViewItem(item)
        }
        tabs.selectedTabViewItemIndex = min(settings.page, tabs.tabViewItems.count - 1)
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenNone)
        window.toolbarStyle = .preference
        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// Keeps the page shown, so that the window opens on it next time.
private final class SettingsTabViewController: NSTabViewController {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        settings.page = selectedTabViewItemIndex
    }
}
