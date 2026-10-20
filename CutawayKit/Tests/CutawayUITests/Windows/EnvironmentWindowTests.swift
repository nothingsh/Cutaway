import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// C-ENV-01, C-ENV-02, C-ENV-04, C-MENU-05: the Environment button, its popover and View ›
/// Environment, on an inspection that is given its environment as `GetEnvironment` would
/// answer. What they look like is checked in the app.
@MainActor
final class EnvironmentWindowTests: XCTestCase {
    private typealias Window = InspectorWindowController

    private static let darkAX3 = Traits(
        userInterfaceStyle: .dark, contentSizeCategory: .accessibilityExtraLarge)

    /// An open inspection with no server: a change goes nowhere, and fails.
    private func inspector() throws -> InspectorWindowController {
        let session = Session(channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "1.2.0"))
        let model = InspectionStore(session: session)
        model.enter()
        model.apply(try Fixtures.hierarchy())
        let inspector = InspectorWindowController(location: .simulator(port: 48160), entry: nil, store: model)
        addTeardownBlock { @MainActor in inspector.close() }
        return inspector
    }

    private static func environment(
        _ overridable: [TraitKind] = TraitKind.allCases, overrides: Traits = .unspecified
    ) -> Environment {
        var environment = MockEnvironment.iPhone(overridable: overridable)
        environment.overrides = overrides
        return environment.answer
    }

    private func toolbarItems(_ inspector: InspectorWindowController) -> [NSToolbarItem.Identifier] {
        inspector.window?.toolbar?.items.map(\.itemIdentifier) ?? []
    }

    private func popover(_ inspector: InspectorWindowController) -> EnvironmentPopoverController {
        let popover = EnvironmentPopoverController(store: inspector.store)
        popover.loadView()
        return popover
    }

    private func environmentMenu() throws -> NSMenu {
        let view = MainMenuBuilder(coordinator: WindowCoordinator(store: AppListStore(), discoversDevices: false))
            .makeMainMenu().items.first { $0.title == "View" }?.submenu
        return try XCTUnwrap(view?.items.first { $0.title == "Environment" }?.submenu)
    }

    // MARK: - C-ENV-01

    func test_C_ENV_01_theButtonJoinsLeftOfTheModeOnceTheEnvironmentIsKnown() throws {
        let inspector = try inspector()
        XCTAssertFalse(toolbarItems(inspector).contains(Window.environmentItem), "not before the answer")

        inspector.store.takeEnvironment(Self.environment())
        let items = toolbarItems(inspector)
        let button = try XCTUnwrap(items.firstIndex(of: Window.environmentItem))
        let mode = try XCTUnwrap(items.firstIndex(of: Window.modeItem))
        XCTAssertEqual(button + 1, mode)
        XCTAssertEqual(inspector.environmentButton?.isEnabled, true)
        XCTAssertNil(inspector.environmentButton?.contentTintColor, "nothing overridden")
    }

    func test_C_ENV_01_anotherWindowDoesNotTakeTheButton() throws {
        let first = try inspector()
        let second = try inspector()
        first.store.takeEnvironment(Self.environment())
        XCTAssertTrue(toolbarItems(first).contains(Window.environmentItem))
        XCTAssertFalse(
            toolbarItems(second).contains(Window.environmentItem),
            "toolbars that share an identifier take each other's insertions")
    }

    func test_C_ENV_01_allFiveKindsGiveFiveRowsWithWhatTheAppShows() throws {
        let inspector = try inspector()
        inspector.store.takeEnvironment(Self.environment())
        let popover = popover(inspector)

        XCTAssertEqual(popover.rows.map(\.kind), TraitKind.allCases)
        XCTAssertEqual(popover.rows.map(\.now.stringValue), [
            "Now: Light", "Now: L", "Now: Left to Right", "Now: Compact", "Now: Regular",
        ])
        let appearance = try XCTUnwrap(popover.rows.first?.segments)
        XCTAssertEqual((0..<appearance.segmentCount).map { appearance.label(forSegment: $0) }, [
            "App\u{2019}s Own", "Light", "Dark",
        ])
        XCTAssertEqual(appearance.selectedSegment, 0)
        let size = try XCTUnwrap(popover.rows.first { $0.kind == .contentSizeCategory })
        XCTAssertEqual(size.override?.state, .off)
        XCTAssertEqual(size.slider?.isEnabled, false, "resting on the app's own size")
        XCTAssertEqual(size.size?.stringValue, "L")
        XCTAssertFalse(popover.resetButton.isEnabled)
    }

    func test_C_ENV_01_onlyTheAppearanceGivesOneRow() throws {
        let inspector = try inspector()
        inspector.store.takeEnvironment(Self.environment([.userInterfaceStyle]))
        XCTAssertEqual(popover(inspector).rows.map(\.kind), [.userInterfaceStyle])
    }

    func test_C_ENV_01_noEnvironmentNoButton() throws {
        let inspector = try inspector()
        inspector.store.takeEnvironment(Self.environment([]))
        XCTAssertFalse(toolbarItems(inspector).contains(Window.environmentItem), "nothing overridable")
        XCTAssertNil(inspector.environmentButton)
    }

    func test_C_ENV_01_theButtonIsDisabledOnceDisconnected() throws {
        let inspector = try inspector()
        inspector.store.takeEnvironment(Self.environment(overrides: Self.darkAX3))
        let popover = popover(inspector)
        XCTAssertEqual(popover.rows.first?.segments?.selectedSegment, 2)

        inspector.store.connectionLost()
        XCTAssertEqual(inspector.environmentButton?.isEnabled, false)
        XCTAssertTrue(toolbarItems(inspector).contains(Window.environmentItem), "it stays")
        XCTAssertNil(inspector.environmentButton?.contentTintColor)
        // The app has its own traits back (C-ENV-03).
        XCTAssertEqual(popover.rows.first?.segments?.selectedSegment, 0)
        XCTAssertEqual(popover.rows.first?.segments?.isEnabled, false)
    }

    func test_C_ENV_01_theButtonIsTintedWhileAnythingIsOverridden() throws {
        let inspector = try inspector()
        inspector.store.takeEnvironment(Self.environment(overrides: Self.darkAX3))
        XCTAssertNotNil(inspector.environmentButton?.contentTintColor)
        XCTAssertEqual(inspector.environmentButton?.toolTip, "Environment: Dark, AX3")
        let popover = popover(inspector)
        XCTAssertTrue(popover.resetButton.isEnabled)
        let size = try XCTUnwrap(popover.rows.first { $0.kind == .contentSizeCategory })
        XCTAssertEqual(size.override?.state, .on)
        XCTAssertEqual(size.slider?.integerValue, 9)
        XCTAssertEqual(size.size?.stringValue, "AX3")
    }

    func test_C_ENV_01_anArchiveWindowHasNoButton() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EnvironmentWindowTests-\(UUID().uuidString).cutaway")
        try Fixtures.archive().write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let archive = try await ArchiveFile.open(url)
        let store = InspectionStore(source: archive.source)
        let window = InspectorWindowController(archive: archive, store: store)
        addTeardownBlock { @MainActor in window.close() }
        store.enter()
        _ = await Wait.until { await MainActor.run { store.loadState == .loaded } }

        XCTAssertEqual(store.environment, .unavailable)
        XCTAssertFalse(toolbarItems(window).contains(Window.environmentItem))
        XCTAssertFalse(window.toolbarAllowedItemIdentifiers(try XCTUnwrap(window.window?.toolbar))
            .contains(Window.environmentItem))
    }

    // MARK: - C-ENV-02

    func test_C_ENV_02_theTextSizeIsSentOnRelease() throws {
        let inspector = try inspector()
        inspector.store.takeEnvironment(Self.environment(overrides: Traits(contentSizeCategory: .large)))
        let popover = popover(inspector)
        let size = try XCTUnwrap(popover.rows.first { $0.kind == .contentSizeCategory })

        popover.sliderMoved(to: 5, isFinal: false)
        popover.sliderMoved(to: 9, isFinal: false)
        XCTAssertEqual(size.size?.stringValue, "AX3", "the name follows the drag")
        XCTAssertEqual(inspector.store.environment.controls?.shown.contentSizeCategory, .large, "nothing sent")
        popover.sliderMoved(to: 8, isFinal: true)
        XCTAssertEqual(inspector.store.environment.controls?.shown.contentSizeCategory, .accessibilityLarge)

        XCTAssertFalse(EnvironmentPopoverController.endsAMove(.leftMouseDown))
        XCTAssertFalse(EnvironmentPopoverController.endsAMove(.leftMouseDragged))
        XCTAssertTrue(EnvironmentPopoverController.endsAMove(.leftMouseUp))
        XCTAssertTrue(EnvironmentPopoverController.endsAMove(.keyDown), "the arrow keys")
        XCTAssertTrue(EnvironmentPopoverController.endsAMove(nil))
    }

    func test_C_ENV_02_tickingOverrideKeepsTheSizeTheAppShows() throws {
        let inspector = try inspector()
        inspector.store.takeEnvironment(Self.environment())
        let popover = popover(inspector)
        let size = try XCTUnwrap(popover.rows.first { $0.kind == .contentSizeCategory })

        popover.overrideTextSize(true, at: try XCTUnwrap(size.slider?.integerValue))
        XCTAssertEqual(inspector.store.environment.controls?.shown.contentSizeCategory, .large)
    }

    func test_C_ENV_02_aFailedChangeSaysWhyAndPutsTheControlsBack() async throws {
        let inspector = try inspector()
        inspector.store.takeEnvironment(Self.environment())
        let popover = popover(inspector)

        // Nothing answers this inspection: the change fails as the connection's would.
        inspector.chooseEnvironmentValue(try XCTUnwrap(
            try environmentMenu().items.first { $0.title == "Appearance" }?.submenu?.items.last))
        let failed = await Wait.until {
            await MainActor.run { inspector.store.environment.controls?.failure != nil }
        }
        XCTAssertTrue(failed)
        XCTAssertEqual(popover.failureLabel.stringValue, "The app didn\u{2019}t answer.")
        XCTAssertFalse(popover.failureLabel.isHidden)
        XCTAssertEqual(popover.rows.first?.segments?.selectedSegment, 0, "back to the app's own")
        XCTAssertNotNil(inspector.environmentPopover, "the popover opens to say so")

        inspector.store.dismissEnvironmentFailure()
        XCTAssertTrue(popover.failureLabel.isHidden)
    }

    // MARK: - C-MENU-05

    func test_C_MENU_05_viewEnvironmentHasEveryKindAndValue() throws {
        let menu = try environmentMenu()
        XCTAssertEqual(menu.items.map(\.title), [
            "Appearance", "Text Size", "Layout Direction", "Size Classes", "", "Toggle Light and Dark", "Reset",
        ])
        let toggle = try XCTUnwrap(menu.items.first { $0.title == "Toggle Light and Dark" })
        XCTAssertEqual(toggle.keyEquivalent, "a")
        XCTAssertEqual(toggle.keyEquivalentModifierMask, [.command, .shift])
        let sizes = try XCTUnwrap(menu.items[1].submenu).items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(sizes,
                       ["App\u{2019}s Own", "XS", "S", "M", "L", "XL", "XXL", "XXXL", "AX1", "AX2", "AX3", "AX4",
                        "AX5"])
        let classes = try XCTUnwrap(menu.items[3].submenu).items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(classes, [
            "Width", "App\u{2019}s Own", "Compact", "Regular", "Height", "App\u{2019}s Own", "Compact", "Regular",
        ])
        // Every value's item names what it chooses.
        for item in MainMenuTests.allItems(menu) where item.action == #selector(Window.chooseEnvironmentValue(_:)) {
            let (kind, value) = try XCTUnwrap(Window.environmentChoice(of: item.tag))
            XCTAssertEqual(Window.environmentTag(kind, value), item.tag)
        }
    }

    func test_C_MENU_05_theEnvironmentItemsFollowTheConnection() throws {
        let inspector = try inspector()
        let items = MainMenuTests.allItems(try environmentMenu())
        func enabled(_ title: String, in submenu: String? = nil) throws -> Bool {
            let menu = try environmentMenu()
            let holder = submenu.flatMap { name in menu.items.first { $0.title == name }?.submenu } ?? menu
            let item = try XCTUnwrap(holder.items.first { $0.title == title }, title)
            return inspector.validateMenuItem(item)
        }
        let actions = items.filter { $0.action != nil && $0.submenu == nil }
        XCTAssertEqual(
            actions.filter { inspector.validateMenuItem($0) }.map(\.title), [], "nothing before the environment")

        inspector.store.takeEnvironment(Self.environment([.userInterfaceStyle]))
        XCTAssertTrue(try enabled("Dark", in: "Appearance"))
        XCTAssertFalse(try enabled("AX3", in: "Text Size"), "a kind the app cannot override")
        XCTAssertTrue(try enabled("Toggle Light and Dark"))
        XCTAssertFalse(try enabled("Reset"), "nothing overridden")
        let own = try XCTUnwrap(try environmentMenu().items.first?.submenu?.items.first)
        _ = inspector.validateMenuItem(own)
        XCTAssertEqual(own.state, .on, "App's Own is ticked")

        inspector.store.connectionLost()
        XCTAssertFalse(try enabled("Dark", in: "Appearance"))
        XCTAssertFalse(try enabled("Toggle Light and Dark"))
    }

    // MARK: - C-ENV-04

    func test_C_ENV_04_anArchiveSavedInDarkAX3SaysSo() async throws {
        let decoder = try ArchiveDecoder(try Fixtures.archive())
        var encoder = ArchiveEncoder()
        var data = encoder.header(manifest: decoder.manifest, state: decoder.state)
        var payloads = decoder.payloads
        payloads.insert(
            FrameCodec.encode(Frame(requestID: 4, body: .environment(Self.environment(overrides: Self.darkAX3)))),
            at: 3)
        for payload in payloads { data += try encoder.frame(payload) }
        data += encoder.trailer()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EnvironmentWindowTests-\(UUID().uuidString).cutaway")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let archive = try await ArchiveFile.open(url)
        let window = InspectorWindowController(archive: archive, store: InspectionStore(source: archive.source))
        addTeardownBlock { @MainActor in window.close() }
        let subtitle = try XCTUnwrap(window.window?.subtitle)
        XCTAssertTrue(subtitle.hasSuffix(" \u{00B7} Dark \u{00B7} AX3"), subtitle)
    }

    func test_C_ENV_04_noOverridesWriteNothingInTheSubtitle() {
        let app = AppInfo(
            name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
            deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
            screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "1.2.0")
        let url = URL(fileURLWithPath: "/tmp/Demo.cutaway")
        let plain = InspectorWindowTitle(archive: url, app: app, savedAt: Date(timeIntervalSince1970: 0))
        let none = InspectorWindowTitle(
            archive: url, app: app, savedAt: Date(timeIntervalSince1970: 0), overrides: .unspecified)
        XCTAssertEqual(plain, none)
        let sized = InspectorWindowTitle(
            archive: url, app: app, savedAt: Date(timeIntervalSince1970: 0),
            overrides: Traits(layoutDirection: .rightToLeft, horizontalSizeClass: .regular))
        XCTAssertEqual(sized.subtitle, plain.subtitle + " \u{00B7} Right to Left \u{00B7} Regular Width")
    }
}
