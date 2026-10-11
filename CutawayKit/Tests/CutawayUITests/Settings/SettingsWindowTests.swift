import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// The settings window (C-PREF-01) and where its values reach (C-PREF-02).
@MainActor
final class SettingsWindowTests: XCTestCase {
    private static let demo = AppInfo(
        name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.1.0")
    private static let simulator = AppLocation.simulator(port: 48160)

    private var suiteName = ""
    private var defaults = UserDefaults()
    private var directory: URL!

    override func setUp() async throws {
        suiteName = "SettingsWindowTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsWindowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    private func session() -> Session {
        Session(channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0"))
    }

    /// A coordinator listing Demo, with settings of the test's own. Its windows are closed
    /// when the test ends.
    private func coordinator() -> (WindowCoordinator, AppListStore) {
        let model = AppListStore()
        model.apply(.found(Self.simulator, Self.demo, session()))
        let coordinator = WindowCoordinator(
            store: model, discoversDevices: false, settings: AppSettings(defaults: defaults))
        addTeardownBlock { @MainActor in
            coordinator.settingsWindow?.close()
            coordinator.inspector?.close()
            for window in coordinator.archiveWindows { window.close() }
            coordinator.launcher.close()
        }
        return (coordinator, model)
    }

    private func page(_ coordinator: WindowCoordinator) throws -> PreviewSettingsViewController {
        coordinator.showSettings(nil)
        let window = try XCTUnwrap(coordinator.settingsWindow)
        window.tabs.selectedTabViewItemIndex = 1
        let page = window.previewPage
        page.view.layoutSubtreeIfNeeded()
        return page
    }

    private func control<T: NSView>(
        _ identifier: String, in page: PreviewSettingsViewController, as _: T.Type = T.self
    ) throws -> T {
        try XCTUnwrap(Self.descendant(of: page.view, identifier: identifier) as? T, identifier)
    }

    private static func descendant(of view: NSView, identifier: String) -> NSView? {
        if view.accessibilityIdentifier() == identifier { return view }
        for subview in view.subviews {
            if let match = descendant(of: subview, identifier: identifier) { return match }
        }
        return nil
    }

    /// What a click or an edit does: the control sends its action.
    private func send(_ control: NSControl) {
        control.sendAction(control.action, to: control.target)
    }

    // MARK: - C-PREF-01: the window

    func test_C_PREF_01_settingsOpensOneWindowAndBringsItToTheFront() throws {
        let (coordinator, _) = coordinator()
        coordinator.showSettings(nil)
        let first = try XCTUnwrap(coordinator.settingsWindow?.window)
        XCTAssertTrue(first.isVisible)
        XCTAssertEqual(first.styleMask, [.titled, .closable])
        XCTAssertFalse(first.styleMask.contains(.resizable))
        XCTAssertFalse(first.styleMask.contains(.miniaturizable))

        first.close()
        XCTAssertFalse(first.isVisible)
        coordinator.showSettings(nil)
        XCTAssertTrue(coordinator.settingsWindow?.window === first)
        XCTAssertTrue(first.isVisible)
        XCTAssertEqual(
            NSApp.windows.filter { $0.contentViewController is NSTabViewController && $0.isVisible }
                .count, 1)
    }

    func test_C_PREF_01_thePagesAreTabsTitlingTheWindowAndTheLastOneShowsAgain() throws {
        let (coordinator, _) = coordinator()
        coordinator.showSettings(nil)
        let controller = try XCTUnwrap(coordinator.settingsWindow)
        let window = try XCTUnwrap(controller.window)
        XCTAssertEqual(controller.tabs.tabStyle, .toolbar)
        XCTAssertEqual(controller.tabs.tabViewItems.map(\.label), ["General", "Preview"])
        XCTAssertEqual(controller.tabs.selectedTabViewItemIndex, 0)
        XCTAssertEqual(window.title, "General")

        controller.tabs.selectedTabViewItemIndex = 1
        XCTAssertEqual(window.title, "Preview")
        XCTAssertEqual(coordinator.settings.page, 1)
        // The next launch's window opens on it.
        let next = SettingsWindowController(
            settings: AppSettings(defaults: defaults), language: coordinator.language, restart: {})
        XCTAssertEqual(next.tabs.selectedTabViewItemIndex, 1)
        next.close()
    }

    func test_C_PREF_01_theControlsShowAndChangeTheSettings() throws {
        let (coordinator, _) = coordinator()
        let settings = coordinator.settings
        let page = try page(coordinator)
        let mode: NSSegmentedControl = try control(PreviewSettingsViewController.modeIdentifier, in: page)
        let slider: NSSlider = try control(PreviewSettingsViewController.spacingSliderIdentifier, in: page)
        let field: NSTextField = try control(PreviewSettingsViewController.spacingFieldIdentifier, in: page)
        let hidden: NSButton = try control(PreviewSettingsViewController.showsHiddenIdentifier, in: page)
        let borders: NSButton = try control(PreviewSettingsViewController.showsBordersIdentifier, in: page)

        XCTAssertEqual(mode.selectedSegment, 0)
        XCTAssertEqual(slider.doubleValue, 50)
        XCTAssertEqual(slider.minValue, 0)
        XCTAssertEqual(slider.maxValue, 200)
        XCTAssertEqual(field.stringValue, "50")
        XCTAssertEqual(hidden.state, .off)
        XCTAssertEqual(borders.state, .on)

        mode.selectedSegment = 1
        send(mode)
        slider.doubleValue = 120.4
        send(slider)
        hidden.state = .on
        send(hidden)
        borders.state = .off
        send(borders)

        XCTAssertEqual(settings.newInspectionMode, .threeD)
        XCTAssertEqual(settings.layerSpacing, 120)
        XCTAssertEqual(field.stringValue, "120")
        XCTAssertTrue(settings.showsHiddenLayers)
        XCTAssertFalse(settings.showsBorders)
        // Kept at once.
        XCTAssertEqual(AppSettings(defaults: defaults).inspectionStart, settings.inspectionStart)
    }

    func test_C_PREF_01_theSpacingFieldRoundsClampsAndRejects() throws {
        let (coordinator, _) = coordinator()
        let settings = coordinator.settings
        let page = try page(coordinator)
        let field: NSTextField = try control(PreviewSettingsViewController.spacingFieldIdentifier, in: page)
        let slider: NSSlider = try control(PreviewSettingsViewController.spacingSliderIdentifier, in: page)

        for (typed, expected) in [("80", 80.0), ("250", 200), ("12.6", 13), ("-4", 0), ("abc", 0), ("", 0)] {
            field.stringValue = typed
            send(field)
            XCTAssertEqual(settings.layerSpacing, expected, typed)
            XCTAssertEqual(field.stringValue, String(Int(expected)), typed)
            XCTAssertEqual(slider.doubleValue, expected, typed)
        }
    }

    func test_C_PREF_01_restoreDefaultsIsOffAtTheDefaults() throws {
        let (coordinator, _) = coordinator()
        let settings = coordinator.settings
        let page = try page(coordinator)
        let restore: NSButton = try control(PreviewSettingsViewController.restoreIdentifier, in: page)
        let mode: NSSegmentedControl = try control(PreviewSettingsViewController.modeIdentifier, in: page)
        let field: NSTextField = try control(PreviewSettingsViewController.spacingFieldIdentifier, in: page)
        XCTAssertFalse(restore.isEnabled)

        settings.newInspectionMode = .threeD
        settings.layerSpacing = 80
        XCTAssertTrue(restore.isEnabled)
        XCTAssertEqual(mode.selectedSegment, 1)
        XCTAssertEqual(field.stringValue, "80")

        send(restore)
        XCTAssertFalse(restore.isEnabled)
        XCTAssertEqual(settings.inspectionStart, InspectionStart())
        XCTAssertEqual(mode.selectedSegment, 0)
        XCTAssertEqual(field.stringValue, "50")
    }

    // MARK: - C-PREF-02: where the settings reach

    func test_C_PREF_02_aNewInspectionStartsAsSetAndOpenWindowsStayAsTheyAre() async throws {
        let (coordinator, model) = coordinator()
        let empty = directory.appendingPathComponent("Empty.cutaway")
        try Fixtures.archive().write(to: empty)
        let opening = await coordinator.openArchive(empty)
        let earlier = try XCTUnwrap(opening)

        coordinator.settings.newInspectionMode = .threeD
        coordinator.settings.layerSpacing = 80
        model.inspect(Self.simulator)
        let live = try XCTUnwrap(coordinator.inspector?.store)
        XCTAssertEqual(live.previewMode, .threeD)
        XCTAssertEqual(live.cameras.threeD.layerSpacing, 80)

        XCTAssertEqual(earlier.store.previewMode, .twoD)
        XCTAssertEqual(earlier.store.cameras.threeD.layerSpacing, 50)

        // An archive without a spacing takes the settings'; what it has, it keeps.
        let noSpacing = directory.appendingPathComponent("NoSpacing.cutaway")
        try Fixtures.archive(state: Data(#"{"mode": "2d"}"#.utf8)).write(to: noSpacing)
        let openingAgain = await coordinator.openArchive(noSpacing)
        let archive = try XCTUnwrap(openingAgain)
        let opened = await eventually { archive.store.loadState == .loaded }
        XCTAssertTrue(opened)
        XCTAssertEqual(archive.store.previewMode, .twoD)
        XCTAssertEqual(archive.store.cameras.threeD.layerSpacing, 80)
        XCTAssertEqual(archive.store.start.layerSpacing, 80)
    }

    // MARK: - Helpers

    private func eventually(within seconds: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
