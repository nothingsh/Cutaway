import AppKit
import CutawayModel
import XCTest

@testable import CutawayUI

/// Cutaway › Check for Updates… tells what it found in an alert, and an update's alert opens
/// its release page (C-DIST-02). The network is a fake throughout.
@MainActor
final class UpdateAlertTests: XCTestCase {
    private static let page = URL(string: "https://github.com/nothingsh/Cutaway/releases/tag/v1.1.0")!

    private nonisolated static func answer(_ status: Int, _ body: String) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: Links.releasesAPI, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(body.utf8), response)
    }

    private nonisolated static let newer = """
    [{"tag_name": "v1.1.0", "html_url": "https://github.com/nothingsh/Cutaway/releases/tag/v1.1.0", "draft": false}]
    """

    /// A coordinator whose checks get `answer`, with the alerts it shows and the pages it opens.
    private func coordinator(
        version: String = "1.0.0", button: NSApplication.ModalResponse = .alertFirstButtonReturn,
        answer: @escaping UpdateChecker.Fetch
    ) -> (WindowCoordinator, () -> [NSAlert], () -> [URL]) {
        let coordinator = WindowCoordinator(store: AppListStore(), discoversDevices: false)
        coordinator.updateChecker = UpdateChecker(currentVersion: version, fetch: answer)
        var alerts: [NSAlert] = []
        var opened: [URL] = []
        coordinator.runAlert = { alert in
            alerts.append(alert)
            return button
        }
        coordinator.openURL = { opened.append($0) }
        addTeardownBlock { @MainActor in coordinator.launcher.close() }
        return (coordinator, { alerts }, { opened })
    }

    func test_C_DIST_02_aFailedCheckSaysWhy() async throws {
        let cases: [(String, UpdateChecker.Fetch, String)] = [
            ("status", { _ in Self.answer(404, "{}") }, "GitHub answered with status 404."),
            ("unreadable", { _ in Self.answer(200, "<html>") }, "GitHub\u{2019}s answer could not be read."),
            ("network", { _ in throw URLError(.notConnectedToInternet) },
             URLError(.notConnectedToInternet).localizedDescription),
        ]
        for (name, answer, text) in cases {
            let (coordinator, alerts, opened) = coordinator(answer: answer)
            await coordinator.checkForUpdatesNow().value
            let alert = try XCTUnwrap(alerts().first, name)
            XCTAssertEqual(alert.messageText, "Couldn\u{2019}t check for updates", name)
            XCTAssertEqual(alert.informativeText, text, name)
            XCTAssertEqual(alert.alertStyle, .warning, name)
            XCTAssertEqual(opened(), [], name)
        }
        let (coordinator, alerts, _) = coordinator(version: "") { _ in Self.answer(200, Self.newer) }
        await coordinator.checkForUpdatesNow().value
        XCTAssertEqual(
            alerts().first?.informativeText, "This copy of Cutaway has no version number to compare.")
    }
}
