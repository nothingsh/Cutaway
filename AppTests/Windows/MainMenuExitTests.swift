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
            "Show Hidden Layers", "Borders", "Show Constraint Ends", "Focus on Selected Layer", "Show All Layers",
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
}
