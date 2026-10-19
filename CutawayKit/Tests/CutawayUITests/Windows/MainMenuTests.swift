import AppKit
import CutawayModel
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// The menu bar as the requirements lay it out: its items (C-MENU-01), their shortcuts and
/// when each can be used (C-MENU-02), About (C-MENU-03) and Help (C-MENU-04).
final class MainMenuTests: XCTestCase {
    private static let demo = AppInfo(
        name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.1.0")
    private static let simulator = AppLocation.simulator(port: 48160)

    // MARK: - The table

    /// When an item can be used (C-MENU-02).
    private enum Rule {
        case always
        /// A window is in front.
        case window
        /// An inspector window in front, connected or an archive's.
        case inspector
        /// An inspector window in front, even a disconnected one: how the window is laid out.
        case layout
        /// An app's inspector window, connected, saving no archive.
        case online
        /// As `online`, with a layer selected and a source that sends subtrees.
        case subtree
        /// As `inspector`, with a layer selected (C-ARCH-06).
        case selection
        /// As `inspector`, with a selected layer that is not the focus.
        case unfocusedSelection
        /// As `inspector`, while focused on a layer.
        case focusing
        /// As `selection`, with a class of the layer declared in the app's project folder
        /// (C-SRC-03): never here, where no folder is linked.
        case declared
        /// Left to AppKit: the responder chain, the undo manager, or the app's own rules (the
        /// hide items depend on the app being active and on the other apps).
        case appKit
    }

    private enum Target {
        /// None: the responder chain.
        case chain
        case coordinator
    }

    private struct Expected {
        let title: String
        let key: String
        let modifiers: NSEvent.ModifierFlags
        let action: Selector?
        let target: Target
        let rule: Rule

        init(
            _ title: String, _ action: Selector?, _ key: String = "",
            _ modifiers: NSEvent.ModifierFlags = .command, target: Target = .chain,
            rule: Rule
        ) {
            self.title = title
            self.key = key
            self.modifiers = modifiers
            self.action = action
            self.target = target
            self.rule = rule
        }
    }

    private static func arrow(_ key: Int) -> String {
        String(Character(UnicodeScalar(UInt32(key)) ?? " "))
    }

    private typealias Window = InspectorWindowController

    /// View › Borders (C-PREV-17).
    private static let borders: [Expected] = [
        Expected("Show Borders", #selector(Window.toggleBorders(_:)), "b", [.command, .shift], rule: .inspector),
        Expected("Plain", #selector(Window.showPlainBorders(_:)), rule: .inspector),
        Expected("By Kind", #selector(Window.showBordersByKind(_:)), rule: .inspector),
        Expected("Only the App\u{2019}s Own Classes", #selector(Window.toggleOnlyAppClasses(_:)), rule: .inspector),
    ]

    /// Every item of a menu and of its submenus, depth first.
    static func allItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in [item] + (item.submenu.map(allItems) ?? []) }
    }

    /// The menu bar, item by item.
    private static let table: [(menu: String, items: [Expected])] = [
        ("Cutaway", [
            Expected("About Cutaway", #selector(WindowCoordinator.showAbout(_:)), target: .coordinator, rule: .always),
            Expected(
                "Check for Updates\u{2026}", #selector(WindowCoordinator.checkForUpdates(_:)), target: .coordinator,
                rule: .always),
            Expected(
                "Settings\u{2026}", #selector(WindowCoordinator.showSettings(_:)), ",", target: .coordinator,
                rule: .always),
            Expected("Services", nil, rule: .appKit),
            Expected("Hide Cutaway", #selector(NSApplication.hide(_:)), "h", rule: .appKit),
            Expected(
                "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option],
                rule: .appKit),
            Expected("Show All", #selector(NSApplication.unhideAllApplications(_:)), rule: .appKit),
            Expected("Quit Cutaway", #selector(NSApplication.terminate(_:)), "q", rule: .always),
        ]),
        ("File", [
            Expected(
                "Open\u{2026}", #selector(WindowCoordinator.openArchivePanel(_:)), "o", target: .coordinator,
                rule: .always),
            Expected("Open Recent", nil, rule: .appKit),
            Expected(
                "Link Project Folder\u{2026}", #selector(Window.linkProjectFolder(_:)), rule: .layout),
            Expected("Open in Xcode", #selector(Window.openInXcode(_:)), "o", [.command, .option], rule: .declared),
            Expected("Save Archive\u{2026}", #selector(Window.saveArchive(_:)), "s", rule: .online),
            Expected(
                "Export Layer Screenshot\u{2026}", #selector(Window.exportLayerScreenshot(_:)), "e",
                [.command, .shift], rule: .selection),
            Expected(
                "Export Screenshot with Sublayers\u{2026}", #selector(Window.exportScreenshotWithSublayers(_:)),
                "e", [.command, .shift, .option], rule: .selection),
            Expected("Close Window", #selector(NSWindow.performClose(_:)), "w", rule: .window),
        ]),
        ("Edit", [
            Expected("Undo", Selector(("undo:")), "z", rule: .appKit),
            Expected("Redo", Selector(("redo:")), "z", [.command, .shift], rule: .appKit),
            Expected("Cut", #selector(NSText.cut(_:)), "x", rule: .appKit),
            Expected("Copy", #selector(NSText.copy(_:)), "c", rule: .appKit),
            Expected("Paste", #selector(NSText.paste(_:)), "v", rule: .appKit),
            Expected("Delete", #selector(NSText.delete(_:)), rule: .appKit),
            Expected("Select All", #selector(NSText.selectAll(_:)), "a", rule: .appKit),
            Expected("Find\u{2026}", #selector(Window.findLayer(_:)), "f", rule: .inspector),
        ]),
        ("View", [
            Expected("Refresh", #selector(Window.refresh(_:)), "r", rule: .online),
            Expected(
                "Refresh Selected Subtree", #selector(Window.refreshSelectedSubtree(_:)), "r",
                [.command, .shift], rule: .subtree),
            Expected("2D", #selector(Window.showTwoD(_:)), "1", rule: .inspector),
            Expected("3D", #selector(Window.showThreeD(_:)), "2", rule: .inspector),
            Expected("Zoom In", #selector(Window.zoomIn(_:)), "=", rule: .inspector),
            Expected("Zoom Out", #selector(Window.zoomOut(_:)), "-", rule: .inspector),
            Expected("Reset View", #selector(Window.resetView(_:)), "0", rule: .inspector),
            Expected(
                "Show Hidden Layers", #selector(Window.toggleHiddenLayers(_:)), "h", [.command, .shift],
                rule: .inspector),
            Expected("Borders", nil, rule: .appKit),
            Expected(
                "Show Constraint Ends", #selector(Window.toggleConstraintEnds(_:)), "k",
                [.command, .shift], rule: .inspector),
            Expected(
                "Select Parent Layer", #selector(Window.selectParentLayer(_:)),
                arrow(NSUpArrowFunctionKey), .command, rule: .selection),
            Expected(
                "Select First Child Layer", #selector(Window.selectFirstChildLayer(_:)),
                arrow(NSDownArrowFunctionKey), .command, rule: .selection),
            Expected(
                "Focus on Selected Layer", #selector(Window.focusOnSelectedLayer(_:)),
                arrow(NSDownArrowFunctionKey), [.command, .option], rule: .unfocusedSelection),
            Expected(
                "Show All Layers", #selector(Window.showAllLayers(_:)), arrow(NSUpArrowFunctionKey),
                [.command, .option], rule: .focusing),
            Expected(
                "Expand All", #selector(Window.expandAllLayers(_:)), arrow(NSRightArrowFunctionKey),
                [.command, .option], rule: .inspector),
            Expected(
                "Collapse All", #selector(Window.collapseAllLayers(_:)), arrow(NSLeftArrowFunctionKey),
                [.command, .option], rule: .inspector),
            Expected(
                "Show Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s",
                [.command, .control], rule: .layout),
            Expected(
                "Show Inspector", #selector(NSSplitViewController.toggleInspector(_:)), "i",
                [.command, .option], rule: .layout),
            Expected(
                "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control],
                rule: .layout),
        ]),
        ("Window", [
            Expected("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", rule: .window),
            Expected("Zoom", #selector(NSWindow.performZoom(_:)), rule: .window),
            Expected(
                "Show App List", #selector(WindowCoordinator.showAppList(_:)), "0", [.command, .shift],
                target: .coordinator, rule: .always),
            Expected("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), rule: .always),
        ]),
        ("Help", [
            Expected("Cutaway Help", #selector(WindowCoordinator.openHelp(_:)), target: .coordinator, rule: .always),
            Expected(
                "Integrating CutawayServer", #selector(WindowCoordinator.openIntegrationGuide(_:)),
                target: .coordinator, rule: .always),
        ]),
    ]

    // MARK: - Helpers

    private func session() -> Session {
        Session(channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0"))
    }

    /// A started coordinator that lists Demo. Its windows are closed when the test ends.
    @MainActor
    private func started() -> (WindowCoordinator, AppListStore) {
        let store = AppListStore()
        store.apply(.found(Self.simulator, Self.demo, session()))
        let coordinator = WindowCoordinator(store: store, discoversDevices: false)
        coordinator.start()
        addTeardownBlock { @MainActor in
            coordinator.inspector?.close()
            for window in coordinator.archiveWindows { window.close() }
            coordinator.launcher.close()
        }
        return (coordinator, store)
    }

    /// Demo's inspector window with the fixtures' layers, layer 4 selected inside the focus on
    /// layer 2, and a server that refreshes subtrees.
    @MainActor
    private func inspecting() throws -> (WindowCoordinator, InspectorWindowController, InspectionStore) {
        let (coordinator, store) = started()
        let list = coordinator.launcher.listController
        list.choose(row: try XCTUnwrap(list.tableRow(ofApp: 0)))
        let inspector = try XCTUnwrap(coordinator.inspector)
        let inspection = try XCTUnwrap(store.inspection(at: Self.simulator))
        inspection.apply(try Fixtures.hierarchy())
        inspection.canRefreshSubtrees = true
        inspection.focus(on: 2)
        inspection.select(4)
        XCTAssertEqual(inspection.selectedLayerID, 4)
        XCTAssertEqual(inspection.focusedLayerID, 2)
        let window = try XCTUnwrap(inspector.window)
        window.makeFirstResponder(inspector.splitController.hierarchyController.outlineView)
        return (coordinator, inspector, inspection)
    }

    /// The fixtures' archive in a window of its own, layer 4 selected inside the focus on 2.
    @MainActor
    private func inArchive() async throws -> (WindowCoordinator, InspectorWindowController) {
        let (coordinator, _) = started()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MainMenuTests-\(UUID().uuidString).cutaway")
        try Fixtures.archive().write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        coordinator.recents = MemoryRecentArchives()
        let opened = await coordinator.openArchive(url)
        let window = try XCTUnwrap(opened)
        let deadline = Date().addingTimeInterval(5)
        while window.store.loadState != .loaded, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(window.store.loadState, .loaded)
        // The fixtures' archive keeps no expansion, and a collapsed layer cannot be selected.
        window.store.expandAll()
        window.store.focus(on: 2)
        window.store.select(4)
        XCTAssertEqual(window.store.selectedLayerID, 4)
        try XCTUnwrap(window.window)
            .makeFirstResponder(window.splitController.hierarchyController.outlineView)
        return (coordinator, window)
    }

    /// The object AppKit would send the item's action to with `window` in front: the item's
    /// target, or the first along the responder chain from the window's first responder, then
    /// the window's delegate, the app and its delegate.
    @MainActor
    private func handler(of item: NSMenuItem, in window: NSWindow) -> AnyObject? {
        guard let action = item.action else { return nil }
        if let target = item.target { return target.responds(to: action) ? target : nil }
        var responder: NSResponder? = window.firstResponder ?? window
        while let current = responder {
            if current.responds(to: action) { return current }
            responder = current.nextResponder
        }
        let rest: [AnyObject?] = [window.delegate, NSApp, NSApp.delegate]
        return rest.compactMap { $0 }.first { $0.responds(to: action) }
    }

    /// Whether AppKit would enable the item with `window` in front.
    @MainActor
    private func isEnabled(_ item: NSMenuItem, in window: NSWindow) -> Bool {
        guard let handler = handler(of: item, in: window) else { return false }
        if let validation = handler as? NSMenuItemValidation {
            return validation.validateMenuItem(item)
        }
        if let validation = handler as? NSUserInterfaceValidations {
            return validation.validateUserInterfaceItem(item)
        }
        return true
    }

    private struct Situation {
        let inspector: Bool
        let online: Bool
        let disconnected: Bool
    }

    private func expectation(_ rule: Rule, in situation: Situation) -> Bool? {
        let live = situation.inspector && !situation.disconnected
        switch rule {
        case .always, .window: return true
        case .inspector, .selection, .unfocusedSelection, .focusing: return live
        case .layout: return situation.inspector
        case .declared: return false
        case .online, .subtree: return live && situation.online
        case .appKit: return nil
        }
    }

    /// Every item of the menu bar against the table's column, with `window` in front.
    @MainActor
    private func assertAvailability(
        of menu: NSMenu, in window: NSWindow, _ situation: Situation,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let view = menu.items.first { $0.title == "View" }?.submenu
        let borders = view?.items.first { $0.title == "Borders" }?.submenu
        for (title, items) in Self.table + [("Borders", Self.borders)] {
            guard let submenu = title == "Borders"
                ? borders : menu.items.first(where: { $0.title == title })?.submenu
            else {
                XCTFail("no \(title) menu", file: file, line: line)
                continue
            }
            for expected in items {
                guard let wanted = expectation(expected.rule, in: situation),
                      let item = submenu.items.first(where: { $0.title == expected.title })
                else { continue }
                XCTAssertEqual(
                    isEnabled(item, in: window), wanted,
                    "\(title) › \(expected.title), sent to \(String(describing: handler(of: item, in: window)))",
                    file: file, line: line)
            }
        }
    }

    // MARK: - C-MENU-02

    @MainActor
    func test_C_MENU_02_noTwoItemsShareAShortcut() {
        let (coordinator, _) = started()
        var seen: [String: String] = [:]
        for item in Self.allItems(coordinator.makeMainMenu())
            where !item.keyEquivalent.isEmpty
        {
            let shortcut = Self.shortcut(of: item)
            XCTAssertNil(seen[shortcut], "\(item.title) and \(seen[shortcut] ?? "") share a shortcut")
            seen[shortcut] = item.title
        }
        XCTAssertEqual(seen.count, 38)
    }

    /// The key and modifiers an item answers to: an upper-case key implies Shift.
    static func shortcut(of item: NSMenuItem) -> String {
        var modifiers = item.keyEquivalentModifierMask.intersection([.command, .shift, .option, .control])
        let key = item.keyEquivalent.lowercased()
        if key != item.keyEquivalent { modifiers.insert(.shift) }
        return "\(modifiers.rawValue)-\(key)"
    }

    @MainActor
    func test_C_MENU_02_whatIsAvailableOnceDisconnected() throws {
        let (coordinator, inspector, _) = try inspecting()
        inspector.store.connectionLost()
        assertAvailability(
            of: coordinator.makeMainMenu(), in: try XCTUnwrap(inspector.window),
            Situation(inspector: true, online: true, disconnected: true))
    }

    @MainActor
    func test_C_MENU_02_whatIsAvailableInAnArchive() async throws {
        let (coordinator, window) = try await inArchive()
        assertAvailability(
            of: coordinator.makeMainMenu(), in: try XCTUnwrap(window.window),
            Situation(inspector: true, online: false, disconnected: false))
    }

    @MainActor
    func test_C_MENU_02_theRulesFollowTheInspection() throws {
        // What the four situations above leave out: no selection, no focus.
        let (coordinator, inspector, inspection) = try inspecting()
        let menu = coordinator.makeMainMenu()
        let window = try XCTUnwrap(inspector.window)
        func enabled(_ title: String) throws -> Bool {
            let item = try XCTUnwrap(
                Self.allItems(menu).first { $0.title == title }, title)
            return isEnabled(item, in: window)
        }
        XCTAssertTrue(try enabled("Focus on Selected Layer"))
        inspection.focus(on: 4)
        XCTAssertFalse(try enabled("Focus on Selected Layer"), "not with the focus on it")
        inspection.focus(on: nil)
        XCTAssertFalse(try enabled("Show All Layers"), "no focus")
        // ⌘↑ and ⌘↓ need a parent and a child (C-ATTR-16).
        inspection.select(1)
        XCTAssertFalse(try enabled("Select Parent Layer"), "a window's root layer")
        XCTAssertTrue(try enabled("Select First Child Layer"))
        inspection.select(3)
        XCTAssertTrue(try enabled("Select Parent Layer"))
        XCTAssertFalse(try enabled("Select First Child Layer"), "a layer without sublayers")
        inspection.select(nil)
        for title in [
            "Select Parent Layer", "Select First Child Layer", "Focus on Selected Layer", "Refresh Selected Subtree",
            "Export Layer Screenshot\u{2026}",
            "Export Screenshot with Sublayers\u{2026}",
        ] {
            XCTAssertFalse(try enabled(title), "\(title) with nothing selected")
        }
        // The table has no item that only 3D has: the spacing is not in the menu.
        XCTAssertTrue(try enabled("2D"))
        XCTAssertTrue(try enabled("3D"))
    }

    @MainActor
    func test_C_MENU_02_zoomInAndOutScaleAboutTheCentre() throws {
        let (_, inspector, inspection) = try inspecting()
        let window = try XCTUnwrap(inspector.window)
        window.contentView?.layoutSubtreeIfNeeded()
        let projector = try XCTUnwrap(inspector.splitController.previewController.projector)
        let viewport = projector.viewport
        XCTAssertGreaterThan(viewport.width, 0)
        inspection.pan(by: 30, -20)
        let before = inspection.camera

        inspector.zoomIn(nil)
        XCTAssertEqual(inspection.camera.zoom, before.zoom * 1.25, accuracy: 1e-9)
        // What was at the centre stays there: the pan grows with the zoom.
        XCTAssertEqual(inspection.camera.pan.x, before.pan.x * 1.25, accuracy: 1e-9)
        XCTAssertEqual(inspection.camera.pan.y, before.pan.y * 1.25, accuracy: 1e-9)
        inspector.zoomOut(nil)
        XCTAssertEqual(inspection.camera.zoom, before.zoom, accuracy: 1e-9)
        XCTAssertEqual(inspection.camera.pan.x, before.pan.x, accuracy: 1e-9)

        for _ in 0..<40 { inspector.zoomIn(nil) }
        XCTAssertEqual(inspection.camera.zoom, Camera.zoomRange.upperBound)
        for _ in 0..<80 { inspector.zoomOut(nil) }
        XCTAssertEqual(inspection.camera.zoom, Camera.zoomRange.lowerBound)

        inspector.store.connectionLost()
        let zoom = inspection.camera.zoom
        inspector.zoomIn(nil)
        XCTAssertEqual(inspection.camera.zoom, zoom, "not once disconnected")
    }

    /// A key-down event for a shortcut, with the flags AppKit gives an arrow key.
    @MainActor
    private func event(_ key: String, _ modifiers: NSEvent.ModifierFlags, in window: NSWindow) throws -> NSEvent {
        var flags = modifiers
        if let scalar = key.unicodeScalars.first, (0xF700...0xF8FF).contains(scalar.value) {
            flags.formUnion([.function, .numericPad])
        }
        return try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: key,
            charactersIgnoringModifiers: key, isARepeat: false, keyCode: 0))
    }

    @MainActor
    func test_C_MENU_02_theArrowShortcutsAreNotTakenByTheListOrTheSearchField() throws {
        // A shortcut goes to the window's views first (performKeyEquivalent) and to the menu
        // after; a view that took ⌥⌘ and an arrow would keep it from the menu.
        let (_, inspector, _) = try inspecting()
        let window = try XCTUnwrap(inspector.window)
        let hierarchy = inspector.splitController.hierarchyController
        let arrows = [NSDownArrowFunctionKey, NSUpArrowFunctionKey, NSRightArrowFunctionKey, NSLeftArrowFunctionKey]
        for responder in [hierarchy.outlineView, hierarchy.searchField] as [NSView] {
            window.makeFirstResponder(responder)
            for arrow in arrows {
                let event = try event(Self.arrow(arrow), [.command, .option], in: window)
                XCTAssertFalse(window.contentView?.performKeyEquivalent(with: event) ?? true, "\(responder)")
            }
        }
    }

    @MainActor
    func test_C_ATTR_16_whileTextIsEditedCommandArrowsStayWithTheText() throws {
        let (coordinator, inspector, inspection) = try inspecting()
        let window = try XCTUnwrap(inspector.window)
        let items = Self.allItems(coordinator.makeMainMenu())
        let parent = try XCTUnwrap(items.first { $0.title == "Select Parent Layer" })
        let child = try XCTUnwrap(items.first { $0.title == "Select First Child Layer" })
        XCTAssertEqual(inspection.selectedLayerID, 4)
        window.makeFirstResponder(inspector.splitController.hierarchyController.outlineView)
        XCTAssertTrue(isEnabled(parent, in: window))
        XCTAssertTrue(isEnabled(child, in: window))

        // In the list's search field: the field editor has the keyboard.
        let field = inspector.splitController.hierarchyController.searchField
        XCTAssertTrue(window.makeFirstResponder(field))
        XCTAssertTrue(inspector.isEditingText)
        XCTAssertFalse(isEnabled(parent, in: window))
        XCTAssertFalse(isEnabled(child, in: window))
        // A disabled item leaves the key to the text, which goes to its start.
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.string = "label"
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        let up = try event(Self.arrow(NSUpArrowFunctionKey), .command, in: window)
        window.sendEvent(up)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertEqual(inspection.selectedLayerID, 4)
    }

    // MARK: - C-MENU-03

    /// The repository's root, found from this file.
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    @MainActor
    func test_C_MENU_03_theAcknowledgementsMatchTheDependencies() throws {
        // CutawayKit's packages, as resolved.
        struct Resolved: Decodable {
            struct Pin: Decodable {
                struct State: Decodable { let version: String? }
                let identity: String
                let state: State
            }

            let pins: [Pin]
        }
        let data = try Data(contentsOf: Self.root.appendingPathComponent("CutawayKit/Package.resolved"))
        var dependencies: [String: String] = [:]
        for pin in try JSONDecoder().decode(Resolved.self, from: data).pins {
            dependencies[pin.identity] = try XCTUnwrap(pin.state.version, pin.identity)
        }
        // The project's own remote packages (project.yml), with the version it asks for.
        let project = try String(contentsOf: Self.root.appendingPathComponent("project.yml"), encoding: .utf8)
        let projectPackages = Self.remotePackages(inProjectSpec: project)
        for (identity, version) in projectPackages { dependencies[identity] = version }
        XCTAssertEqual(dependencies.count, 3 + projectPackages.count)

        let acknowledgements = AboutPanel.acknowledgements()
        XCTAssertEqual(acknowledgements.count, dependencies.count, "one each")
        XCTAssertEqual(Set(acknowledgements.map(\.0.identity)), Set(dependencies.keys))
        for (library, text) in acknowledgements {
            XCTAssertEqual(library.version, dependencies[library.identity], library.name)
            XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, library.name)
            XCTAssertNotNil(URL(string: library.url), library.name)
        }
    }

    /// The `packages` of an XcodeGen spec that come from a URL: identity (the URL's last
    /// component, lower case, without `.git`) and the exact version asked for.
    static func remotePackages(inProjectSpec spec: String) -> [String: String] {
        var packages: [String: String] = [:]
        var inPackages = false
        var identity: String?
        for line in spec.components(separatedBy: "\n") {
            if !line.hasPrefix(" "), !line.isEmpty { inPackages = line == "packages:" }
            guard inPackages else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("url:") {
                let url = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
                identity = url.split(separator: "/").last.map {
                    String($0).lowercased().replacingOccurrences(of: ".git", with: "")
                }
            } else if trimmed.hasPrefix("exactVersion:") || trimmed.hasPrefix("from:"),
                      let identity
            {
                let version = trimmed.split(separator: ":", maxSplits: 1).last ?? ""
                packages[identity] = version.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            }
        }
        return packages
    }
}
