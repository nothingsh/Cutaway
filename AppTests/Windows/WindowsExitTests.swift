import AppKit
import CutawayTestSupport
import CutawayUI
import XCTest

/// End to end: the running app starts with the launcher alone; choosing the
/// app that MockServer replays opens it in its own window, and closing that window brings the
/// launcher back (C-WIN-01). The test looks at the running app's windows.
final class WindowsExitTests: XCTestCase {
    @MainActor
    func test_C_WIN_01_theRunningAppOpensAnAppInItsOwnWindow() async throws {
        let coordinator = try AppWindows.coordinator()
        let launcher = try XCTUnwrap(coordinator.launcher.window)
        XCTAssertTrue(launcher.isVisible, "the app does not show the launcher")
        XCTAssertTrue(AppWindows.inspectorWindows().isEmpty)

        let server = try await AppWindows.startMockServer(
            try .fixtures("handshake", "app-icon", "hierarchy"))
        addTeardownBlock {
            // Leave the app as it was for the other tests, even when this one failed.
            await AppWindows.closeInspectors()
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }
        try await AppWindows.chooseApp(named: "Demo", server: server)

        // Its own window, titled with its name; the launcher is put away, as it was.
        let windows = AppWindows.inspectorWindows()
        XCTAssertEqual(windows.count, 1)
        let window = try XCTUnwrap(windows.first)
        XCTAssertEqual(window.title, "Demo")
        XCTAssertEqual(window.subtitle, "iPhone 16 · iOS 18.0")
        XCTAssertFalse(launcher.isVisible)
        let deadline = Date().addingTimeInterval(5)
        var outline: NSOutlineView? {
            window.contentView.flatMap {
                AppWindows.views(in: $0, identifier: "hierarchy.outline").first as? NSOutlineView
            }
        }
        while outline?.numberOfRows != AppWindows.fixtureRowsAtFirst, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(
            outline?.numberOfRows, AppWindows.fixtureRowsAtFirst,
            "the layers are not in the app's window")

        // Closing the window leaves the inspection and brings back the launcher.
        window.performClose(nil)
        XCTAssertTrue(AppWindows.inspectorWindows().isEmpty)
        XCTAssertTrue(launcher.isVisible)
        XCTAssertNil(coordinator.store.inspectedApp)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
    }
}
