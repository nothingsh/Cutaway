import AppKit
import CutawayTestSupport
import CutawayUI
import XCTest

@testable import Cutaway

/// End to end: in the running app, the list of the `hierarchy` fixture is
/// searched, expanded to level 2 and focused on a subtree, which the preview then draws alone.
final class HierarchyToolsExitTests: XCTestCase {
    @MainActor
    private func one<View: NSView>(_ identifier: String, as type: View.Type) throws -> View {
        try XCTUnwrap(AppWindows.views(identifier: identifier).first as? View, identifier)
    }

    /// Chooses an item of the app's menu for the inspector window, as the menu does once it
    /// has checked that the item is available.
    @MainActor
    private func choose(_ title: String, for inspector: InspectorWindowController) throws {
        let item = try XCTUnwrap(
            NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items)
                .first { $0.title == title }, title)
        XCTAssertTrue(inspector.validateMenuItem(item), title)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: inspector, from: item))
    }

    @MainActor
    private func waitForRows(_ count: Int, in outline: NSOutlineView) async throws {
        let deadline = Date().addingTimeInterval(5)
        while outline.numberOfRows != count, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(outline.numberOfRows, count)
    }

    @MainActor
    private func titles(of outline: NSOutlineView) -> [String?] {
        (0..<outline.numberOfRows).map { row in
            outline.view(atColumn: 0, row: row, makeIfNecessary: true).flatMap {
                (AppWindows.views(in: $0, identifier: "hierarchy.title").first as? NSTextField)?
                    .stringValue
            }
        }
    }

    @MainActor
    func test_C_HIER_04_theRunningAppSearchesFocusesAndExpandsTheList() async throws {
        let server = try await AppWindows.startMockServer(
            try .fixtures("handshake", "app-icon", "hierarchy"))
        addTeardownBlock {
            await AppWindows.closeInspectors()
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }
        try await AppWindows.chooseApp(named: "Demo", server: server)
        var outline = try one("hierarchy.outline", as: NSOutlineView.self)
        try await waitForRows(AppWindows.fixtureRowsAtFirst, in: outline)

        // Search (C-HIER-04).
        let field = try one("hierarchy.search", as: NSSearchField.self)
        field.stringValue = "label"
        XCTAssertTrue(field.sendAction(field.action, to: field.target))
        // Typing reaches the list once it pauses.
        try await waitForRows(5, in: outline)
        XCTAssertEqual(
            titles(of: outline), ["UIWindow", "UIView", "UILabel", "UIScrollView", "UILabel"])
        field.stringValue = ""
        XCTAssertTrue(field.sendAction(field.action, to: field.target))
        XCTAssertEqual(outline.numberOfRows, AppWindows.fixtureRowsAtFirst)

        // Expand to level 2 (C-HIER-06), from everything expanded: the list starts much like
        // level 2 (C-HIER-09).
        try AppWindows.expandAll()
        XCTAssertEqual(outline.numberOfRows, 9)
        let expand = try one("hierarchy.expand", as: NSPopUpButton.self)
        expand.selectItem(withTitle: "Expand to Level 2")
        XCTAssertTrue(expand.sendAction(expand.action, to: expand.target))
        XCTAssertEqual(titles(of: outline), [
            "UIWindow", "UIView", "UILabel", "CardView", "UIScrollView", "CALayer", "UIView",
        ])
        XCTAssertEqual(
            (0..<outline.numberOfRows).filter { outline.isItemExpanded(outline.item(atRow: $0)) },
            [0, 1])

        // Focus on UIView through the View menu (C-HIER-05).
        outline.selectRowIndexes([1], byExtendingSelection: false)
        let inspector = try XCTUnwrap(
            AppWindows.inspectorWindows().first?.windowController as? InspectorWindowController)
        try choose("Focus on Selected Layer", for: inspector)
        outline = try one("hierarchy.outline", as: NSOutlineView.self)
        // UIView and its five sublayers, collapsed by the level 2 above.
        XCTAssertEqual(
            titles(of: outline),
            ["UIView", "UILabel", "CardView", "UIScrollView", "CALayer", "UIView"])
        XCTAssertEqual(outline.level(forRow: 0), 0)

        // The preview draws the subtree alone: the window's root layer is not drawn.
        let preview = try one(PreviewView.identifier, as: PreviewView.self)
        XCTAssertNil(preview.imagePoint(ofCenterOf: 1))
        XCTAssertNotNil(preview.imagePoint(ofCenterOf: 2))
        try choose("Show All Layers", for: inspector)
        XCTAssertNotNil(preview.imagePoint(ofCenterOf: 1))
    }
}
