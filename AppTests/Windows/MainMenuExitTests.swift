import AppKit
import CutawayUI
import XCTest

/// End to end in the running app: no two items of the menu bar AppKit shows, its own items
/// included, share a shortcut (C-MENU-02).
final class MainMenuExitTests: XCTestCase {
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
