import AppKit
import CutawayTestSupport
import XCTest

/// End to end: the running app lists an app that MockServer replays. The
/// test looks at what the app shows, through AppKit alone.
final class AppListExitTests: XCTestCase {
    @MainActor
    func test_C_LIST_01_theRunningAppListsAnAppThatMockServerReplays() async throws {
        // The app scans the real ports, so the server takes one of them.
        let server = try await AppWindows.startMockServer(try .fixtures("handshake", "app-icon"))
        addTeardownBlock {
            // Leave the app list as it was for the other tests, even when this one failed.
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }

        // Found within one scan round and a bit (C-CONN-01: two seconds).
        let found = await AppWindows.waitForAppRow(named: "Demo", toExist: true, within: 5)
        let row = try XCTUnwrap(found, "the app did not list the replayed app")

        func text(_ identifier: String) -> String? {
            (AppWindows.views(in: row, identifier: identifier).first as? NSTextField)?.stringValue
        }
        XCTAssertEqual(text("app.bundle"), "dev.cutaway.demo")
        XCTAssertEqual(text("app.device"), "iPhone 16 · iOS 18.0")

        // The icon was fetched over the same connection and decoded: 2 by 2 pixels.
        var icon: NSImage?
        let deadline = Date().addingTimeInterval(3)
        while icon == nil, Date() < deadline {
            if let current = AppWindows.appRow(named: "Demo") {
                icon = (AppWindows.views(in: current, identifier: "app.icon").first
                    as? NSImageView)?.image
            }
            if icon == nil { try await Task.sleep(for: .milliseconds(50)) }
        }
        XCTAssertEqual(icon?.size, NSSize(width: 2, height: 2))

        // One connection, with the Hello and the icon request on it (C-CONN-09).
        let connections = await server.connectionCount
        XCTAssertEqual(connections, 1)

        // When the app goes away, so does its row (C-CONN-07).
        await server.stop()
        let gone = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        XCTAssertNil(gone)
    }
}
