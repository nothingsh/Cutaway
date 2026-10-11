import AppKit
import CutawayTestSupport
import CutawayUI
import CutawayWire
import XCTest

@testable import Cutaway

/// End to end: in the running app, ⌘S saves an archive of the app the
/// window inspects; while it is saved the window can still be browsed but not refreshed; an
/// archive that could not be saved leaves no file and says why (C-ARCH-02).
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

    @MainActor
    private func text(_ identifier: String) -> String? {
        (AppWindows.views(identifier: identifier).first as? NSTextField)?.stringValue
    }

    private static func archiveBatchArrived(_ server: MockServer) async -> Bool {
        await server.receivedFrames.contains {
            guard case .getLayerDetails(let request) = $0.body else { return false }
            return MockResponder.isArchiveBatch(request)
        }
    }

    /// The manifest carries the version the About panel and the handshake show (C-DIST-01).
    @MainActor
    func test_C_DIST_01_theSavedArchiveCarriesTheAppsVersion() async throws {
        let (_, inspector) = try await inspect(try MockResponder.demo())
        let save = try menuItem("Save Archive\u{2026}")
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(save.action), to: inspector, from: save))
        let written = await eventually { FileManager.default.fileExists(atPath: self.destination.path) }
        XCTAssertTrue(written, "no archive was written")
        let decoder = try ArchiveDecoder(try Data(contentsOf: destination))
        let version = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertEqual(decoder.manifest.cutawayVersion, version)
        XCTAssertEqual(decoder.manifest.cutawayVersion, AppVersion.current.version)
        let saved = await eventually { self.shown("preview.archiveSaved") }
        XCTAssertTrue(saved, "nothing said the archive was saved")
    }

    @MainActor
    func test_C_ARCH_02_theRunningAppSavesAnArchive() async throws {
        let gate = MockGate()
        var responder = try MockResponder.demo()
        responder.holdBeforeDetails = (MockResponder.isArchiveBatch, gate)
        let (server, inspector) = try await inspect(responder)

        let save = try menuItem("Save Archive\u{2026}")
        XCTAssertEqual(save.keyEquivalent, "s")
        XCTAssertTrue(inspector.validateMenuItem(save))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(save.action), to: inspector, from: save))

        let held = await eventually { await Self.archiveBatchArrived(server) }
        XCTAssertTrue(held, "the archive's first batch was not asked for")
        let progressShown = await eventually { self.shown("preview.archiveProgress") }
        XCTAssertTrue(progressShown, "no progress while saving")

        // Refreshing and saving again are off; browsing is not.
        XCTAssertFalse(inspector.validateMenuItem(try menuItem("Refresh")))
        XCTAssertFalse(inspector.validateMenuItem(save))
        // Each item is asked itself: in a window as narrow as a 1024-point screen allows, the
        // items are in the toolbar's overflow menu, which validateVisibleItems() passes over.
        let refreshItem = try XCTUnwrap(
            inspector.window?.toolbar?.items.first { $0.itemIdentifier.rawValue == "inspector.refresh" })
        refreshItem.validate()
        XCTAssertFalse(refreshItem.isEnabled)
        let saveItem = try XCTUnwrap(
            inspector.window?.toolbar?.items.first {
                $0.itemIdentifier.rawValue == "inspector.saveArchive"
            })
        saveItem.validate()
        XCTAssertFalse(saveItem.isEnabled)
        let outline = try XCTUnwrap(
            AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)
        outline.selectRowIndexes([3], byExtendingSelection: false)
        let selected = await eventually { self.text("preview.readout.title") == "CardView" }
        XCTAssertTrue(selected, "selecting stopped while saving")

        await gate.open()
        let written = await eventually { FileManager.default.fileExists(atPath: self.destination.path) }
        XCTAssertTrue(written, "no archive was written")
        let decoder = try ArchiveDecoder(try Data(contentsOf: destination))
        XCTAssertEqual(decoder.hierarchy.nodes.count, 9)
        let layers = try (0..<decoder.chunkCount).flatMap { try decoder.chunk(at: $0).details }
        XCTAssertEqual(layers.map(\.layerID), [1, 2, 3, 4, 5, 6, 7, 8, 9])

        let saved = await eventually { self.shown("preview.archiveSaved") }
        XCTAssertTrue(saved, "nothing said the archive was saved")
        XCTAssertEqual(text("preview.archiveSaved.text"), "Saved \u{201C}Demo\u{201D}")
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
        XCTAssertEqual(
            text("preview.archiveFailed.text"),
            "The archive wasn\u{2019}t saved: Demo went to the background.")
        // The panel is as wide as its text (as the notice's, C-DET-04).
        let panel = try XCTUnwrap(AppWindows.views(identifier: "preview.archiveFailed").first)
        let label = try XCTUnwrap(
            AppWindows.views(identifier: "preview.archiveFailed.text").first as? NSTextField)
        panel.window?.layoutIfNeeded()
        XCTAssertFalse(panel.hasAmbiguousLayout)
        XCTAssertGreaterThanOrEqual(label.frame.width + 0.5, label.intrinsicContentSize.width)
        XCTAssertTrue(panel.bounds.insetBy(dx: -0.5, dy: -0.5).contains(
            label.convert(label.bounds, to: panel)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])

        let ok = try XCTUnwrap(
            AppWindows.views(identifier: "preview.archiveFailed.ok").first as? NSButton)
        ok.performClick(nil)
        let dismissed = await eventually { !self.shown("preview.archiveFailed") }
        XCTAssertTrue(dismissed)
    }

    @MainActor
    func test_C_ARCH_02_saveIsOffWhileDisconnected() async throws {
        let (server, inspector) = try await inspect(try MockResponder.demo())
        let save = try menuItem("Save Archive\u{2026}")
        XCTAssertTrue(inspector.validateMenuItem(save))

        await server.stop()
        let lost = await eventually { inspector.isDisconnected }
        XCTAssertTrue(lost)
        XCTAssertFalse(inspector.validateMenuItem(save))
        // Asked itself, as above: it may be in the toolbar's overflow menu.
        let saveItem = try XCTUnwrap(
            inspector.window?.toolbar?.items.first {
                $0.itemIdentifier.rawValue == "inspector.saveArchive"
            })
        saveItem.validate()
        XCTAssertFalse(saveItem.isEnabled)
    }
}
