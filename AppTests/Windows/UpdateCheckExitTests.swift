import AppKit
import CutawayUI
import XCTest

@testable import Cutaway

/// End to end: the running app's Cutaway menu checks for updates through its coordinator, and
/// a test run never reaches the network (C-DIST-02).
final class UpdateCheckExitTests: XCTestCase {
    @MainActor
    func test_C_DIST_02_checkForUpdatesIsWiredInTheRunningApp() async throws {
        let delegate = try XCTUnwrap(NSApplication.shared.delegate as? AppDelegate)
        XCTAssertFalse(delegate.checksUpdatesOnline, "the test scheme keeps the check off the network")
        let coordinator = try AppWindows.coordinator()
        XCTAssertEqual(coordinator.updateChecker.currentVersion, AppVersion.current.version)

        let menu = try XCTUnwrap(NSApp.mainMenu?.items.first?.submenu)
        let item = try XCTUnwrap(menu.items.first { $0.title == "Check for Updates\u{2026}" })
        XCTAssertTrue(item.target === coordinator)
        XCTAssertTrue(item.isEnabled)

        var alerts: [NSAlert] = []
        let runAlert = coordinator.runAlert
        coordinator.runAlert = { alert in
            alerts.append(alert)
            return .alertFirstButtonReturn
        }
        defer { coordinator.runAlert = runAlert }
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
        let deadline = Date().addingTimeInterval(5)
        while alerts.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(
            alerts.first?.informativeText, URLError(.notConnectedToInternet).localizedDescription)
    }
}
