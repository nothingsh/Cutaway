import AppKit
import CutawayModel
import CutawayRender
import CutawayTestSupport
import CutawayUI
import CutawayWire
import XCTest

@testable import Cutaway

/// End to end: the running app opens an archive it saved, as the Finder
/// hands it one, and shows it offline (C-ARCH-05).
final class ArchiveOpenExitTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveOpenExitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The app's coordinator with recents of its own and failures recorded, put back as they
    /// were when the test ends.
    @MainActor
    private func coordinator() throws -> (WindowCoordinator, Failures) {
        let coordinator = try AppWindows.coordinator()
        let recents = coordinator.recents
        let present = coordinator.presentOpenFailure
        let failures = Failures()
        coordinator.recents = MemoryRecentArchives()
        coordinator.presentOpenFailure = { url, error in failures.all.append((url, error)) }
        addTeardownBlock { @MainActor in
            for window in coordinator.archiveWindows { window.close() }
            coordinator.recents = recents
            coordinator.presentOpenFailure = present
        }
        return (coordinator, failures)
    }

    @MainActor
    private final class Failures {
        var all: [(URL, ArchiveOpenError)] = []
    }

    @MainActor
    private func eventually(
        within seconds: TimeInterval = 5, _ condition: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return await condition()
    }

    /// Saves an archive of the fixtures' app the way the app does (C-ARCH-02).
    @MainActor
    private func savedArchive() async throws -> URL {
        let script = MockScript(
            steps: try MockScript.fixtures("handshake").steps + [.respond(try MockResponder.demo())])
        let server = try await AppWindows.startMockServer(script)
        try await AppWindows.chooseApp(named: "Demo", server: server)
        let inspector = try XCTUnwrap(
            AppWindows.inspectorWindows().first?.windowController as? InspectorWindowController)
        let url = directory.appendingPathComponent("Demo.cutaway")
        inspector.chooseArchiveDestination = { _, _, done in done(url) }
        let loaded = await eventually {
            (AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)?
                .numberOfRows ?? 0 > 0
        }
        XCTAssertTrue(loaded)
        let save = try XCTUnwrap(
            NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items)
                .first { $0.title == "Save Archive\u{2026}" })
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(save.action), to: inspector, from: save))
        let saved = await eventually { FileManager.default.fileExists(atPath: url.path) }
        XCTAssertTrue(saved, "the archive was not saved")
        // The app goes away: what follows is offline.
        AppWindows.closeInspectors()
        await server.stop()
        _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        return url
    }

    @MainActor
    func test_C_ARCH_05_theRunningAppOpensAnArchiveOffline() async throws {
        let (coordinator, failures) = try coordinator()
        let url = try await savedArchive()

        let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        delegate.application(NSApp, open: [url])
        let opened = await eventually { coordinator.archiveWindows.count == 1 }
        XCTAssertTrue(opened, "no window for the archive; failures: \(failures.all)")
        let window = try XCTUnwrap(coordinator.archiveWindows.first)
        XCTAssertTrue(window.isArchive)
        XCTAssertEqual(window.window?.title, "Demo")

        // The layers are drawn from the archive: layer 4 is green.
        let preview = try XCTUnwrap(
            AppWindows.views(identifier: PreviewView.identifier).first as? PreviewView)
        let drawn = try await AppWindows.waitFor(
            Pixel(blue: 0, green: 255, red: 0, alpha: 255), at: 4, in: preview)
        XCTAssertTrue(drawn, "layer 4's screenshot did not appear")

        // Nothing to refresh or save, and no connection to lose.
        let refresh = try XCTUnwrap(
            NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items)
                .first { $0.title == "Refresh" })
        XCTAssertFalse(window.validateMenuItem(refresh))
        XCTAssertFalse(
            AppWindows.views(identifier: "preview.disconnected").contains { AppWindows.isShown($0) })
        XCTAssertTrue(failures.all.isEmpty)
    }
}
