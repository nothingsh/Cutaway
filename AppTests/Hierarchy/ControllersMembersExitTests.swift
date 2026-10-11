import AppKit
import CutawayTestSupport
import XCTest

@testable import Cutaway

/// End to end: the running app shows the view controller and the member
/// names that the `hierarchy` fixture of protocol 0.2 carries (C-HIER-07).
final class ControllersMembersExitTests: XCTestCase {
    @MainActor
    private func one<View: NSView>(_ identifier: String, as type: View.Type) throws -> View {
        try XCTUnwrap(AppWindows.views(identifier: identifier).first as? View, identifier)
    }

    /// The detail after a row's title, or nil when the row has none.
    @MainActor
    private func detail(ofRow row: Int, in outline: NSOutlineView) -> String? {
        guard let view = outline.view(atColumn: 0, row: row, makeIfNecessary: true),
              let label = AppWindows.views(in: view, identifier: "hierarchy.detail").first
              as? NSTextField, !label.isHidden
        else { return nil }
        return label.stringValue
    }

    @MainActor
    func test_C_HIER_07_theRunningAppShowsViewControllersAndMembers() async throws {
        let server = try await AppWindows.startMockServer(
            try .fixtures("handshake", "app-icon", "hierarchy"))
        addTeardownBlock {
            await AppWindows.closeInspectors()
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }
        try await AppWindows.chooseApp(named: "Demo", server: server)
        let deadline = Date().addingTimeInterval(5)
        while (AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)?
            .numberOfRows != AppWindows.fixtureRowsAtFirst, Date() < deadline
        {
            try await Task.sleep(for: .milliseconds(50))
        }
        let outline = try one("hierarchy.outline", as: NSOutlineView.self)
        // The shape layer, 5, is inside the collapsed card (C-HIER-09).
        try AppWindows.expandAll()
        XCTAssertEqual(outline.numberOfRows, 9)

        // Rows, in tree order: UIWindow, UIView, UILabel, CardView, CAShapeLayer, …
        XCTAssertNil(detail(ofRow: 0, in: outline))
        XCTAssertEqual(detail(ofRow: 1, in: outline), "HomeViewController")
        XCTAssertEqual(detail(ofRow: 2, in: outline), "HomeViewController.titleLabel")
        XCTAssertEqual(detail(ofRow: 4, in: outline), "CardView.badgeLayer +1")

        // The search finds a member's name (C-HIER-04).
        let field = try one("hierarchy.search", as: NSSearchField.self)
        field.stringValue = "titleLabel"
        XCTAssertTrue(field.sendAction(field.action, to: field.target))
        // Typing reaches the list once it pauses.
        let searchDeadline = Date().addingTimeInterval(5)
        while outline.numberOfRows != 3, Date() < searchDeadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(outline.numberOfRows, 3)
        field.stringValue = ""
        XCTAssertTrue(field.sendAction(field.action, to: field.target))
        XCTAssertEqual(outline.numberOfRows, 9)

        // The attribute panel's header lists both members of the shape layer.
        outline.selectRowIndexes([4], byExtendingSelection: false)
        let references = try one("attributes.header.references", as: NSTextField.self)
        XCTAssertEqual(
            references.stringValue, "CardView.badgeLayer\nHomeViewController.cardBadge")
    }
}
