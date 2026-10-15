import AppKit
import Combine
import CutawayModel
import CutawayTransport
import UniformTypeIdentifiers

/// The app's two windows and how one leads to the other (C-WIN-01): the launcher lists the
/// apps; choosing one opens its inspector window and puts the launcher away; closing the
/// inspector brings the launcher back. One app is inspected at a time. Archives open in
/// windows of their own, through `archives` (C-WIN-05).
@MainActor
public final class WindowCoordinator: NSObject {
    public let store: AppListStore
    /// The settings window's values (C-PREF-01): how new inspections start (C-PREF-02).
    public let settings: AppSettings
    /// The interface's language as chosen in the settings (C-LOC-01).
    public let language: LanguageSetting
    /// Quits and opens Cutaway again, after a language is chosen. Tests record it.
    public var restart: @MainActor () -> Void = { Relaunch.restart() }
    /// The settings window, once it has been asked for. Kept when closed: there is one only.
    private(set) var settingsWindow: SettingsWindowController?
    // Set in init once self exists: the launcher's callback holds self weakly.
    // swiftlint:disable:next implicitly_unwrapped_optional
    public private(set) var launcher: LauncherWindowController!
    /// The window of the app being inspected, or of the one whose connection was just lost.
    private(set) var inspector: InspectorWindowController?
    /// The archives' windows (C-ARCH-04, C-WIN-05).
    let archives: ArchiveOpener
    /// Opens a page on the web (C-MENU-04). The default browser; tests record the address.
    public var openURL: @MainActor (URL) -> Void = { url in
        NSWorkspace.shared.open(url)
    }

    /// Cutaway › Check for Updates… (C-DIST-02). The app's tests give it a network of their own.
    public var updateChecker = UpdateChecker()
    /// Shows an alert and gives the button chosen. Modal by default; tests answer it.
    public var runAlert: @MainActor (NSAlert) -> NSApplication.ModalResponse = { $0.runModal() }

    private let remembersWindowFrames: Bool
    private var cancellables = Set<AnyCancellable>()

    /// `remembersWindowFrames` keeps the windows' sizes and places between launches; tests
    /// leave it off, so that one run does not shape the next. Without `settings`, the
    /// coordinator keeps its own, starting from the defaults each time; so it does without
    /// `language`. `applyAppearance` gives the whole app the appearance chosen in the settings
    /// (C-PREF-03), nil for the system's; tests record it. Without an application, as in a
    /// package test run before any test made one, there is nothing to give it to.
    public init(
        store: AppListStore, discoversDevices: Bool, remembersWindowFrames: Bool = false,
        settings: AppSettings? = nil, language: LanguageSetting? = nil,
        applyAppearance: @escaping @MainActor (NSAppearance?) -> Void = { NSApp?.appearance = $0 }
    ) {
        self.store = store
        self.remembersWindowFrames = remembersWindowFrames
        self.settings = settings ?? Self.temporarySettings()
        self.language = language ?? Self.temporaryLanguage()
        archives = ArchiveOpener(
            settings: self.settings, maxTextureDimension: store.maxTextureDimension,
            paneWidths: remembersWindowFrames
                ? PaneWidths(key: PaneWidths.inspectorKey, defaults: .standard) : nil)
        super.init()
        let current = self.settings
        // Before any window shows, and at once on each change (C-PREF-03).
        current.$appearance
            .removeDuplicates()
            .sink { applyAppearance($0.nsAppearance) }
            .store(in: &cancellables)
        store.inspectionStart = { current.inspectionStart }
        store.inspectionText = .interface
        launcher = LauncherWindowController(
            store: store, discoversDevices: discoversDevices,
            onChoose: { [weak self] location in self?.choose(location) },
            openURL: { [weak self] url in self?.openURL(url) })
        if remembersWindowFrames { launcher.windowFrameAutosaveName = "Launcher" }
        // With no window left, the launcher shows (C-WIN-05).
        archives.didCloseWindow = { [weak self] in
            guard let self, self.inspector == nil, self.archiveWindows.isEmpty else { return }
            self.showAppList(nil)
        }

        store.$inspectedApp
            .removeDuplicates()
            .sink { [weak self] location in self?.inspectedAppDidChange(to: location) }
            .store(in: &cancellables)
    }

    /// Settings in a user defaults domain of their own, emptied first.
    private static func temporarySettings() -> AppSettings {
        let name = "dev.cutaway.WindowCoordinator.temporarySettings"
        // The name is not empty and is not the app's own domain.
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return AppSettings(defaults: defaults)
    }

    /// A language setting in a user defaults domain of its own, emptied first.
    private static func temporaryLanguage() -> LanguageSetting {
        let name = "dev.cutaway.WindowCoordinator.temporaryLanguage"
        // The name is not empty and is not the app's own domain.
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return languageSetting(defaults: defaults, domain: name)
    }

    /// The language setting kept in `domain`, the persistent domain `defaults` writes to: the
    /// app's bundle identifier for `.standard`.
    public static func languageSetting(defaults: UserDefaults, domain: String) -> LanguageSetting {
        LanguageSetting(defaults: defaults, domain: domain, languages: Localization.languages)
    }

    // MARK: - Settings

    /// Cutaway › Settings… (C-PREF-01): the one settings window, to the front.
    @objc func showSettings(_ sender: Any?) {
        let controller = settingsWindow ?? SettingsWindowController(
            settings: settings, language: language, restart: { [weak self] in self?.restart() })
        if settingsWindow == nil {
            if remembersWindowFrames { controller.windowFrameAutosaveName = "Settings" }
            settingsWindow = controller
        }
        controller.showWindow(sender)
        controller.window?.makeKeyAndOrderFront(sender)
    }

    /// Shows the launcher. The app calls this once it has started. Archives the app was
    /// started to open open instead, and the launcher shows only if none of them does
    /// (C-ARCH-04).
    public func start(opening urls: [URL] = []) {
        guard !urls.isEmpty else {
            showAppList(nil)
            return
        }
        Task {
            var opened = false
            for url in urls where await openArchive(url) != nil { opened = true }
            if !opened { showAppList(nil) }
        }
    }

    // MARK: - Archives

    /// The archives' windows, in the order they opened (C-WIN-05).
    public var archiveWindows: [InspectorWindowController] { archives.windows }

    /// What File › Open Recent lists. The system's by default; tests keep their own.
    public var recents: any RecentArchives {
        get { archives.recents }
        set { archives.recents = newValue }
    }

    /// Says why an archive could not be opened. An alert by default; tests record it.
    public var presentOpenFailure: @MainActor (URL, ArchiveOpenError) -> Void {
        get { archives.presentOpenFailure }
        set { archives.presentOpenFailure = newValue }
    }

    /// Opens an archive in a window of its own (C-ARCH-04, C-WIN-05), or brings its window
    /// to the front when it is open already. The launcher stays as it is. Returns the window,
    /// or nil after saying why the archive could not be opened.
    @discardableResult
    public func openArchive(_ url: URL) async -> InspectorWindowController? {
        await archives.open(url)
    }

    /// Opens archives one after another, without waiting for them.
    public func openArchives(_ urls: [URL]) {
        archives.open(urls)
    }

    /// Brings the launcher to the front; an inspector window stays where it is.
    @objc func showAppList(_ sender: Any?) {
        launcher.showWindow(sender)
        launcher.window?.makeKeyAndOrderFront(sender)
    }

    // MARK: - The inspector window

    /// An app chosen in the launcher. The one already inspected is only brought to the front.
    private func choose(_ location: AppLocation) {
        if let inspector, inspector.location == location, !inspector.isDisconnected,
           store.inspectedApp == location
        {
            inspector.showWindow(nil)
            launcher.window?.orderOut(nil)
            return
        }
        store.inspect(location, byChoice: true)
    }

    private func inspectedAppDidChange(to location: AppLocation?) {
        // Without an app, nothing to do: a window whose app went away follows its own
        // inspection (C-WIN-03), and one the user closed is gone already.
        guard let location else { return }
        // Another app, or the same one over a new connection: a new window. When it is the
        // app a waiting window was lost to (C-WIN-04), the new window takes the old one's
        // place, without the opening animation, and the launcher stays as it is.
        let entry = store.entries.first { $0.id == location }
        let returning = inspector.flatMap { old -> NSWindow? in
            guard old.isDisconnected, let identity = old.identity,
                  entry?.info.flatMap(AppIdentity.init) == identity
            else { return nil }
            return old.window
        }
        // A full-screen or minimized window's frame is not a place to put a new one.
        let returningFrame = returning.flatMap { window -> NSRect? in
            window.isMiniaturized || window.styleMask.contains(.fullScreen) ? nil : window.frame
        }
        let returnsMinimized = returning?.isMiniaturized == true
        let chosen = store.inspectionOpenedByChoice
        closeInspector()
        guard let inspection = store.inspection(at: location) else { return }
        let controller = InspectorWindowController(
            location: location, entry: entry, store: inspection,
            paneWidths: remembersWindowFrames
                ? PaneWidths(key: PaneWidths.inspectorKey, defaults: .standard) : nil)
        // Before the frame is set: a remembered frame must not take the old window's place.
        if remembersWindowFrames { controller.windowFrameAutosaveName = "Inspector" }
        controller.onShowApps = { [weak self] in self?.showAppList(nil) }
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.inspectorWillClose(controller)
        }
        controller.onArchiveSaved = { [weak self] url in self?.recents.note(url) }
        inspector = controller
        if returning != nil, let window = controller.window {
            window.animationBehavior = .none
            if let returningFrame { window.setFrame(returningFrame, display: false) }
            // A window that was minimized comes back minimized, straight into the Dock; but
            // chosen in the launcher, which then goes away, it must be on screen.
            if returnsMinimized, !chosen {
                window.miniaturize(nil)
            } else {
                controller.showWindow(nil)
            }
            window.animationBehavior = .default
            // Come back on its own, it leaves the launcher as it is; chosen there, it does
            // what a choice does (C-WIN-01).
            if chosen { launcher.window?.orderOut(nil) }
        } else {
            controller.showWindow(nil)
            launcher.window?.orderOut(nil)
        }
    }

    /// The inspector window is closing, by the user or by the coordinator.
    private func inspectorWillClose(_ controller: InspectorWindowController) {
        // A window the coordinator closed itself is already replaced.
        guard controller === inspector else { return }
        inspector = nil
        // A window that waits for its app ends the wait as it closes (C-WIN-04).
        if store.inspectedApp == controller.location || controller.isDisconnected {
            store.leaveInspection()
        }
        showAppList(nil)
    }

    /// Closes the inspector window without leaving the inspection: the store has moved on.
    private func closeInspector() {
        guard let old = inspector else { return }
        inspector = nil
        // The closed window lives until the stack unwinds; while it holds the autosave name,
        // AppKit would not give the name to the window that replaces it.
        old.windowFrameAutosaveName = ""
        old.close()
    }
}

extension AppSettings.Appearance {
    /// What the app is given: nil follows the system.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
