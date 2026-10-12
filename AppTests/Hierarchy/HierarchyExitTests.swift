import AppKit
import CutawayTestSupport
import XCTest

/// End to end: the running app shows the layers of the `hierarchy`
/// fixture. The test looks at what the app shows, through AppKit alone.
final class HierarchyExitTests: XCTestCase {
    @MainActor
    private func hierarchyOutline() -> NSOutlineView? {
        AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView
    }

    @MainActor
    func test_C_HIER_01_theRunningAppShowsTheLayersThatMockServerReplays() async throws {
        let server = try await AppWindows.startMockServer(
            try .fixtures("handshake", "app-icon", "hierarchy"))
        addTeardownBlock {
            // Leave the app as it was for the other tests, even when this one failed.
            await AppWindows.closeInspectors()
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }

        let found = await AppWindows.waitForAppRow(named: "Demo", toExist: true, within: 5)
        XCTAssertNotNil(found, "the app did not list the replayed app")

        // MockServer answers requests in the script's order, and the icon comes first there.
        // (A real server answers whatever it is asked.) So: wait until the icon was asked for.
        var deadline = Date().addingTimeInterval(3)
        while await server.receivedFrames.count < 2, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let framesBeforeChoosing = await server.receivedFrames.count
        XCTAssertEqual(framesBeforeChoosing, 2, "Hello and GetAppIcon")

        // Choose the app, as Return on its row does. The row is looked up again, and waited
        // for: the list reloads when the icon arrives, and for a moment the row has no view.
        let again = await AppWindows.waitForAppRow(named: "Demo", toExist: true, within: 3)
        let row = try XCTUnwrap(again)
        var ancestor = row.superview
        while let candidate = ancestor, !(candidate is NSTableView) {
            ancestor = candidate.superview
        }
        let table = try XCTUnwrap(ancestor as? NSTableView)
        let index = table.row(for: row)
        XCTAssertGreaterThanOrEqual(index, 0)
        try AppWindows.open(row: index, of: table)

        // The layers appear, open down to the view controller (C-HIER-09).
        deadline = Date().addingTimeInterval(5)
        while hierarchyOutline()?.numberOfRows != AppWindows.fixtureRowsAtFirst, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let outline = try XCTUnwrap(hierarchyOutline(), "the app did not open the inspection")
        XCTAssertEqual(outline.numberOfRows, AppWindows.fixtureRowsAtFirst)
        XCTAssertEqual((0..<7).map(outline.level(forRow:)), [0, 1, 2, 2, 2, 2, 2])

        // All nine, expanded.
        try AppWindows.expandAll()
        XCTAssertEqual(outline.numberOfRows, 9)
        XCTAssertTrue(AppWindows.isShown(outline))
        XCTAssertEqual((0..<9).map(outline.level(forRow:)), [0, 1, 2, 2, 3, 2, 3, 2, 2])
        // Shown means in view: the list has the room to show all nine rows. The window may
        // not have had its first layout yet when the rows arrive, so lay it out first.
        outline.window?.layoutIfNeeded()
        for row in 0..<9 {
            XCTAssertTrue(
                outline.visibleRect.contains(outline.rect(ofRow: row)),
                "row \(row) is not in view: \(outline.rect(ofRow: row)) in \(outline.visibleRect)")
        }

        let titles = (0..<9).map { row -> NSTextField? in
            outline.view(atColumn: 0, row: row, makeIfNecessary: true).flatMap {
                AppWindows.views(in: $0, identifier: "hierarchy.title").first as? NSTextField
            }
        }
        XCTAssertEqual(titles.map { $0?.stringValue }, [
            "UIWindow", "UIView", "UILabel", "CardView", "CAShapeLayer", "UIScrollView",
            "UILabel", "CALayer", "UIView",
        ])
        // Only the hidden shape layer is dimmed (C-HIER-03).
        XCTAssertEqual(
            titles.map { $0?.textColor == .tertiaryLabelColor },
            [false, false, false, false, true, false, false, false, false])

        // The list and the inspection used one connection (C-CONN-09), as the script says.
        let connections = await server.connectionCount
        XCTAssertEqual(connections, 1)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        // When the app goes away, its window stays and says so (C-WIN-03), and the app leaves
        // the list (C-CONN-07).
        await server.stop()
        deadline = Date().addingTimeInterval(5)
        var notice: NSView? { AppWindows.views(identifier: "preview.disconnected").first }
        while !(notice.map(AppWindows.isShown) ?? false), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(notice.map(AppWindows.isShown) ?? false, "no notice of the lost app")
        XCTAssertEqual(hierarchyOutline()?.numberOfRows, 9, "the layers it last showed stay")
        // Its button closes the window, and the launcher is back.
        let showApps = try XCTUnwrap(
            AppWindows.views(identifier: "preview.showApps").first as? NSButton)
        showApps.performClick(nil)
        XCTAssertTrue(AppWindows.inspectorWindows().isEmpty)
        XCTAssertEqual(try AppWindows.coordinator().launcher.window?.isVisible, true)
        let gone = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        XCTAssertNil(gone)
    }
}
