import AppKit
import CutawayTestSupport
import CutawayUI
import CutawayWire
import XCTest

@testable import Cutaway

/// End to end: in the running app, ⌘S saves an archive of the app the
/// window inspects; while it is saved the window can still be browsed but not refreshed; an
/// archive that could not be saved leaves no file and says why (C-ARCH-02). The saved
/// archive's manifest carries the app's version (C-DIST-01).
final class ArchiveSaveExitTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveSaveExitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var destination: URL { directory.appendingPathComponent("Demo.cutaway") }

    @MainActor
    private func inspect(_ responder: MockResponder) async throws -> (MockServer, InspectorWindowController) {
        let script = MockScript(
            steps: try MockScript.fixtures("handshake").steps + [.respond(responder)])
        let server = try await AppWindows.startMockServer(script)
        addTeardownBlock {
            await AppWindows.closeInspectors()
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }
        try await AppWindows.chooseApp(named: "Demo", server: server)
        let inspector = try XCTUnwrap(
            AppWindows.inspectorWindows().first?.windowController as? InspectorWindowController)
        let loaded = await eventually {
            !AppWindows.views(identifier: "hierarchy.outline").isEmpty
                && (AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)?
                .numberOfRows ?? 0 > 0
        }
        XCTAssertTrue(loaded, "the layers did not load")
        let target = destination
        inspector.chooseArchiveDestination = { _, name, done in
            XCTAssertTrue(name.hasPrefix("Demo "), "the suggested name is \(name)")
            done(target)
        }
        return (server, inspector)
    }

    @MainActor
    private func menuItem(_ title: String) throws -> NSMenuItem {
        try XCTUnwrap(
            NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items)
                .first { $0.title == title },
            "no menu item \(title)")
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

    @MainActor
    private func shown(_ identifier: String) -> Bool {
        AppWindows.views(identifier: identifier).contains { AppWindows.isShown($0) }
    }

    /// A button of the toolbar's app capsule (C-WIN-06).
    @MainActor
    private func capsuleButton(_ identifier: String) throws -> NSButton {
        try XCTUnwrap(AppWindows.views(identifier: identifier).first as? NSButton, identifier)
    }

    /// What the toolbar's app capsule says under the app's name.
    @MainActor
    private func subtitle() -> String? {
        (AppWindows.views(identifier: "toolbar.capsule.subtitle").first as? NSButton)?.title
    }

    private static func archiveBatchArrived(_ server: MockServer) async -> Bool {
        await server.receivedFrames.contains {
            guard case .getLayerDetails(let request) = $0.body else { return false }
            return MockResponder.isArchiveBatch(request)
        }
    }

    @MainActor
    func test_C_ARCH_02_theRunningAppSavesAnArchive() async throws {
        let gate = MockGate()
        var responder = try MockResponder.demo()
        responder.holdBeforeDetails = (MockResponder.isArchiveBatch, gate)
        let (server, inspector) = try await inspect(responder)

        let save = try menuItem("Save Archive\u{2026}")
        XCTAssertTrue(inspector.validateMenuItem(save))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(save.action), to: inspector, from: save))

        let held = await eventually { await Self.archiveBatchArrived(server) }
        XCTAssertTrue(held, "the archive's first batch was not asked for")
        // The toolbar's capsule says so (C-WIN-06).
        let progressShown = await eventually {
            self.shown("toolbar.capsule.progress")
                && self.subtitle()?.hasPrefix("Saving") == true
        }
        XCTAssertTrue(progressShown, "no progress while saving: \(self.subtitle() ?? "-")")

        // Refreshing and saving again are off; browsing is not.
        XCTAssertFalse(inspector.validateMenuItem(try menuItem("Refresh")))
        XCTAssertFalse(inspector.validateMenuItem(save))
        // The capsule's refresh is off; its save button, which now cancels, is not.
        XCTAssertFalse(try capsuleButton("toolbar.capsule.refresh").isEnabled)
        let saveButton = try capsuleButton("toolbar.capsule.save")
        XCTAssertTrue(saveButton.isEnabled)
        let outline = try XCTUnwrap(
            AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)
        outline.selectRowIndexes([3], byExtendingSelection: false)
        let selected = await eventually {
            AppWindows.views(identifier: "preview.tag.selected").contains {
                AppWindows.isShown($0) && $0.accessibilityLabel()?.hasPrefix("CardView") == true
            }
        }
        XCTAssertTrue(selected, "selecting stopped while saving")

        await gate.open()
        let written = await eventually { FileManager.default.fileExists(atPath: self.destination.path) }
        XCTAssertTrue(written, "no archive was written")
        let decoder = try ArchiveDecoder(try Data(contentsOf: destination))
        XCTAssertEqual(decoder.hierarchy.nodes.count, 14)
        let layers = try (0..<decoder.chunkCount).flatMap { try decoder.chunk(at: $0).details }
        XCTAssertEqual(layers.map(\.layerID), [1, 2, 3, 4, 10, 11, 12, 5, 6, 7, 8, 9, 13, 14])
        // The manifest carries the version the About panel and the handshake show (C-DIST-01).
        XCTAssertEqual(
            decoder.manifest.cutawayVersion,
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertEqual(decoder.manifest.cutawayVersion, AppVersion.current.version)

        let refreshable = await eventually { inspector.validateMenuItem(try! self.menuItem("Refresh")) }
        XCTAssertTrue(refreshable)
    }

    @MainActor
    func test_C_ARCH_02_theRunningAppReportsAnUnsavedArchive() async throws {
        var responder = try MockResponder.demo()
        responder.failDetails = (MockResponder.isArchiveBatch, .appNotActive)
        let (_, inspector) = try await inspect(responder)

        let save = try menuItem("Save Archive\u{2026}")
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(save.action), to: inspector, from: save))

        let failed = await eventually { self.shown("preview.archiveFailed") }
        XCTAssertTrue(failed, "nothing said the archive was not saved")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])

        let ok = try XCTUnwrap(
            AppWindows.views(identifier: "preview.archiveFailed.ok").first as? NSButton)
        ok.performClick(nil)
        let dismissed = await eventually { !self.shown("preview.archiveFailed") }
        XCTAssertTrue(dismissed)
    }
}
