import AppKit
import CutawayUI
import XCTest

/// End to end in the running app: the menu bar AppKit shows has the items of `titles` in order
/// and no shortcut twice (C-MENU-01, C-MENU-02), and About has the
/// copyright line and the acknowledgements the app ships (C-MENU-03).
final class MainMenuExitTests: XCTestCase {
    /// The menu bar's titles, menu by menu.
    private static let titles: [String: [String]] = [
        "Cutaway": [
            "About Cutaway", "Check for Updates\u{2026}", "Settings\u{2026}", "Services", "Hide Cutaway", "Hide Others",
            "Show All", "Quit Cutaway",
        ],
        "File": [
            "Open\u{2026}", "Open Recent", "Save Archive\u{2026}", "Export Layer Screenshot\u{2026}",
            "Export Screenshot with Sublayers\u{2026}", "Close Window",
        ],
        "Edit": ["Undo", "Redo", "Cut", "Copy", "Paste", "Delete", "Select All", "Find\u{2026}"],
        "View": [
            "Refresh", "Refresh Selected Subtree", "2D", "3D", "Zoom In", "Zoom Out", "Reset View",
            "Show Hidden Layers", "Show Borders", "Focus on Selected Layer", "Show All Layers",
            "Expand All", "Collapse All", "Show Sidebar", "Show Inspector", "Enter Full Screen",
        ],
        "Window": ["Minimize", "Zoom", "Show App List", "Bring All to Front"],
        "Help": ["Cutaway Help", "Integrating CutawayServer"],
    ]

    @MainActor
    private func mainMenu() throws -> NSMenu {
        let menu = try XCTUnwrap(NSApp.mainMenu)
        // AppKit adds its items when a menu is about to be shown; ask it to now.
        for item in menu.items { item.submenu?.update() }
        return menu
    }

    @MainActor
    func test_C_MENU_01_theRunningMenuBarHasEveryItemInOrder() throws {
        let menu = try mainMenu()
        XCTAssertEqual(
            menu.items.map(\.title), ["Cutaway", "File", "Edit", "View", "Window", "Help"])
        for item in menu.items {
            let submenu = try XCTUnwrap(item.submenu, item.title)
            let expected = try XCTUnwrap(Self.titles[item.title], item.title)
            // AppKit adds items of its own, and which ones and with what actions changes from
            // one macOS to the next (Window › Fill, Move & Resize, Full Screen Tile); the
            // app's are picked out by their titles. That the app adds nothing else is the
            // package's test of the menu it builds (test_C_MENU_01_theMenuBarMatchesTheTable).
            // Alternates show only while Option is held (File › Close All). Hidden items: View ›
            // Enter Full Screen with ⌃⌘F, which AppKit hides for its own with the system's
            // shortcut (the next test).
            let ours = submenu.items.filter { entry in
                !entry.isAlternate && !entry.isHidden && expected.contains(entry.title)
            }
            let shown = submenu.items.map { "\($0.title) \($0.action.map(NSStringFromSelector) ?? "-")" }
            XCTAssertEqual(ours.map(\.title), expected, "\(item.title): \(shown)")
        }
        XCTAssertNil(
            menu.items.compactMap(\.submenu).flatMap(\.items)
                .first { NSStringFromSelector($0.action ?? Selector(("none:"))) == "toggleTabBar:" },
            "windows have no tabs")
    }

    @MainActor
    func test_C_MENU_02_enterFullScreenAnswersControlCommandF() throws {
        // AppKit shows its own Enter Full Screen with the system's shortcut and hides the
        // View menu's; a hidden item still answers its shortcut.
        let items = try mainMenu().items.first { $0.title == "View" }?.submenu?.items ?? []
        let fullScreen = items.filter { $0.action == #selector(NSWindow.toggleFullScreen(_:)) }
        XCTAssertEqual(fullScreen.filter { !$0.isHidden }.count, 1, "one shown")
        let ours = try XCTUnwrap(fullScreen.first { $0.keyEquivalentModifierMask == [.command, .control] })
        XCTAssertEqual(ours.keyEquivalent, "f")

        final class Recorder: NSObject {
            var count = 0
            @objc func record(_ sender: Any?) { count += 1 }
        }
        let recorder = Recorder()
        let menu = NSMenu()
        let hidden = menu.addItem(withTitle: "Hidden", action: #selector(Recorder.record(_:)), keyEquivalent: "f")
        hidden.keyEquivalentModifierMask = [.command, .control]
        hidden.target = recorder
        hidden.isHidden = true
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .control], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{06}", charactersIgnoringModifiers: "f",
            isARepeat: false, keyCode: 3))
        XCTAssertTrue(menu.performKeyEquivalent(with: event))
        XCTAssertEqual(recorder.count, 1)
    }

    @MainActor
    func test_C_MENU_02_noTwoItemsInTheRunningMenuBarShareAShortcut() throws {
        var seen: [String: String] = [:]
        func visit(_ menu: NSMenu) {
            for item in menu.items {
                if let submenu = item.submenu { visit(submenu) }
                guard !item.keyEquivalent.isEmpty, !item.isHidden else { continue }
                var modifiers = item.keyEquivalentModifierMask
                    .intersection([.command, .shift, .option, .control])
                let key = item.keyEquivalent.lowercased()
                if key != item.keyEquivalent { modifiers.insert(.shift) }
                let shortcut = "\(modifiers.rawValue)-\(key)"
                XCTAssertNil(seen[shortcut], "\(item.title) and \(seen[shortcut] ?? "") share a shortcut")
                seen[shortcut] = item.title
            }
        }
        visit(try mainMenu())
        XCTAssertGreaterThanOrEqual(seen.count, 34)
    }

    @MainActor
    func test_C_MENU_03_theRunningAppsAboutPanelHasItsFields() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertEqual(info["NSHumanReadableCopyright"] as? String, "Copyright © 2026 Wynn Zhang.")
        let options = AboutPanel.options(info: info, icon: NSApp.applicationIconImage)
        XCTAssertEqual(options[.applicationName] as? String, "Cutaway")
        XCTAssertNotNil(options[.applicationVersion] as? String)
        XCTAssertNotNil(options[.version] as? String)
        XCTAssertNotNil(options[.applicationIcon] as? NSImage)
        // The acknowledgements are a resource of the package, which the app must carry.
        let credits = try XCTUnwrap(options[.credits] as? NSAttributedString).string
        for library in ["FlatBuffers", "DeclarativeAppKit", "DeclarativeCombine"] {
            XCTAssertTrue(credits.contains(library), library)
        }
        XCTAssertTrue(credits.contains("Apache License"))
        XCTAssertTrue(credits.contains("Permission is hereby granted"), "the MIT licence's text")
    }
}
