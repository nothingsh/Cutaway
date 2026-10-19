import AppKit
import CutawayModel
import CutawayRender
import CutawayTransport
import CutawayUI
import CutawayWire
import Metal

/// Assembly only: starts discovery, connects it to the store and hands both to the windows.
/// No logic lives in the app target.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The app list's store. Read by the app's own tests.
    private(set) var store: AppListStore?
    private var discovery: Discovery?
    /// The windows. Read by the app's own tests.
    private(set) var coordinator: WindowCoordinator?
    /// Whether the app looks for apps on USB devices.
    private(set) var discoversDevices = true
    /// The local ports the app scans. Read by the app's own tests.
    private(set) var simulatorPorts: [UInt16] = []
    /// Who the app says it is in the handshake (C-DIST-01). Read by the app's own tests.
    let clientInfo = ClientInfo(name: "Cutaway", version: AppVersion.current.version)
    /// Whether Check for Updates… reaches GitHub (C-DIST-02). Read by the app's own tests.
    private(set) var checksUpdatesOnline = true
    /// Archives handed over before the windows exist: the app was started to open them.
    private var archivesToOpen: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        var configuration = DiscoveryConfiguration(client: clientInfo)
        // The test scheme sets this: a test run must not reach for real devices.
        if ProcessInfo.processInfo.environment["CUTAWAY_DISABLE_DEVICE_DISCOVERY"] == "1" {
            configuration.usbmuxdSocketPath = nil
        }
        // The test scheme also moves the local scan to ports no real server listens on, so a
        // Cutaway or a server-side app left open meets neither the app under test nor its
        // MockServer (C-CONN-09).
        if let first = ProcessInfo.processInfo.environment["CUTAWAY_SIMULATOR_PORTS_START"]
            .flatMap(UInt16.init)
        {
            configuration.simulatorPorts = DiscoveryConfiguration.ports.indices.map {
                first + UInt16($0)
            }
        }
        discoversDevices = configuration.usbmuxdSocketPath != nil
        simulatorPorts = configuration.simulatorPorts
        let discovery = Discovery(configuration: configuration)
        // Images are asked for no larger than this Mac's GPU can hold in one texture
        // (C-REND-05). Without Metal there is no preview, and no limit is asked for.
        let limit = MTLCreateSystemDefaultDevice().map { Renderer.maxTextureDimension(of: $0) }
        let store = AppListStore(maxTextureDimension: UInt32(limit ?? 0))
        store.follow(discovery.events)
        Task { await discovery.start() }
        self.discovery = discovery
        self.store = store

        let (defaults, domain) = Self.settingsDefaults()
        let coordinator = WindowCoordinator(
            store: store, discoversDevices: discoversDevices, remembersWindowFrames: true,
            settings: AppSettings(defaults: defaults),
            language: WindowCoordinator.languageSetting(defaults: defaults, domain: domain),
            projects: ProjectSources(folders: ProjectFolders(defaults: defaults)))
        // Neither window is a document's: no tabs, and no tab items in the View menu.
        NSWindow.allowsAutomaticWindowTabbing = false
        // A test run never reaches the network: its checks fail as if offline.
        if ProcessInfo.processInfo.environment["CUTAWAY_SETTINGS_SUITE"] != nil {
            checksUpdatesOnline = false
            coordinator.updateChecker = UpdateChecker { _ in throw URLError(.notConnectedToInternet) }
        }
        NSApplication.shared.mainMenu = coordinator.makeMainMenu()
        coordinator.start(opening: archivesToOpen)
        archivesToOpen = []
        self.coordinator = coordinator
    }

    /// The user's defaults and the name of the domain they write to; the test scheme names a
    /// domain of its own, emptied at launch. The language chosen in the settings is kept in
    /// the app's own domain, where macOS reads it (C-LOC-01).
    private static func settingsDefaults() -> (UserDefaults, String) {
        guard let name = ProcessInfo.processInfo.environment["CUTAWAY_SETTINGS_SUITE"],
              let defaults = UserDefaults(suiteName: name)
        else { return (.standard, Bundle.main.bundleIdentifier ?? "dev.cutaway.Cutaway") }
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    /// Archives from the Finder or the Dock (C-ARCH-04). Before launching ends they wait, so
    /// that the app starts with them instead of the app list.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let coordinator else {
            archivesToOpen += urls
            return
        }
        coordinator.openArchives(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
