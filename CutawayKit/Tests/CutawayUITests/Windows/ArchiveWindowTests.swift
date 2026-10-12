import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// Archives in windows of their own (C-ARCH-04, C-ARCH-05, C-WIN-05).
final class ArchiveWindowTests: XCTestCase {
    private static let demo = AppInfo(
        name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.1.0")

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveWindowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ data: Data, as name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func archive(_ name: String = "Demo.cutaway") throws -> URL {
        try write(try Fixtures.archive(), as: name)
    }

    /// A coordinator that lists Demo, with recents of its own and failures recorded. Not
    /// started; its windows are closed when the test ends.
    @MainActor
    private func coordinator() -> (WindowCoordinator, MemoryRecentArchives, Failures) {
        let model = AppListStore()
        model.apply(.found(
            .simulator(port: 48160), Self.demo,
            Session(channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0"))))
        let coordinator = WindowCoordinator(store: model, discoversDevices: false)
        let recents = MemoryRecentArchives()
        coordinator.recents = recents
        let failures = Failures()
        coordinator.presentOpenFailure = { url, error in failures.all.append((url, error)) }
        addTeardownBlock { @MainActor in
            coordinator.inspector?.close()
            for window in coordinator.archiveWindows { window.close() }
            coordinator.launcher.close()
        }
        return (coordinator, recents, failures)
    }

    @MainActor
    private static func labels(in view: NSView) -> [NSTextField] {
        ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap(labels(in:))
    }

    @MainActor
    private final class Failures {
        var all: [(URL, ArchiveOpenError)] = []
    }

    @MainActor
    private func eventually(within seconds: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: - C-ARCH-05

    @MainActor
    func test_C_ARCH_05_theArchiveWindowSaysWhatItShows() async throws {
        let (coordinator, _, _) = coordinator()
        coordinator.start()
        let url = try archive()
        let opened = await coordinator.openArchive(url)
        let controller = try XCTUnwrap(opened)
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.title, "Demo")
        XCTAssertEqual(window.representedURL, url)
        XCTAssertTrue(window.subtitle.hasPrefix("Demo \u{00B7} iPhone 16 \u{00B7} iOS 18.0 \u{00B7} Saved "),
                      window.subtitle)
        XCTAssertTrue(controller.isArchive)

        let identifiers = try XCTUnwrap(window.toolbar).items.map(\.itemIdentifier.rawValue)
        XCTAssertTrue(identifiers.contains("inspector.archiveTag"))
        XCTAssertTrue(identifiers.contains("inspector.mode"))
        for live in ["inspector.refresh", "inspector.saveArchive", "inspector.apps"] {
            XCTAssertFalse(identifiers.contains(live), "\(live) is in an archive's toolbar")
        }
        let tag = try XCTUnwrap(window.toolbar?.items.first {
            $0.itemIdentifier.rawValue == "inspector.archiveTag"
        }?.view)
        tag.layoutSubtreeIfNeeded()
        let label = try XCTUnwrap(Self.labels(in: tag).first)
        XCTAssertEqual(label.stringValue, "Archive")
        // The word in the middle of its border, the label no taller than its text.
        let frame = label.convert(label.bounds, to: tag)
        XCTAssertEqual(frame.midY, tag.bounds.midY, accuracy: 0.5)
        XCTAssertEqual(frame.midX, tag.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(frame.height, label.intrinsicContentSize.height, accuracy: 0.5)
        XCTAssertEqual(tag.bounds.height, 18)

        let menu = NSMenu()
        for (selector, enabled) in [
            (#selector(InspectorWindowController.refresh(_:)), false),
            (#selector(InspectorWindowController.refreshSelectedSubtree(_:)), false),
            (#selector(InspectorWindowController.saveArchive(_:)), false),
            (#selector(InspectorWindowController.showThreeD(_:)), true),
            (#selector(InspectorWindowController.toggleBorders(_:)), true),
        ] {
            let item = menu.addItem(withTitle: "\(selector)", action: selector, keyEquivalent: "")
            XCTAssertEqual(controller.validateMenuItem(item), enabled, "\(selector)")
        }

        // The archive is inspected: its tree is in, and nothing can be changed.
        let loaded = await eventually { controller.store.loadState == .loaded }
        XCTAssertTrue(loaded)
        XCTAssertEqual(controller.store.tree.count, 9)
        XCTAssertFalse(controller.store.attributes.canEdit)
        XCTAssertFalse(controller.isDisconnected)
    }

    // MARK: - C-WIN-05

    @MainActor
    func test_C_WIN_05_archivesOpenBesideEachOtherAndTheLiveInspector() async throws {
        let (coordinator, _, _) = coordinator()
        coordinator.start()
        let list = coordinator.launcher.listController
        list.choose(row: try XCTUnwrap(list.tableRow(ofApp: 0)))
        let live = try XCTUnwrap(coordinator.inspector)
        XCTAssertFalse(try XCTUnwrap(coordinator.launcher.window).isVisible)

        let first = try archive("First.cutaway")
        let second = try archive("Second.cutaway")
        let a = await coordinator.openArchive(first)
        let b = await coordinator.openArchive(second)
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertEqual(coordinator.archiveWindows.count, 2)
        XCTAssertTrue(try XCTUnwrap(live.window).isVisible, "the live inspector closed")
        XCTAssertFalse(try XCTUnwrap(coordinator.launcher.window).isVisible)

        // The same archive again: its window, brought forward.
        let again = await coordinator.openArchive(first)
        XCTAssertTrue(again === a)
        XCTAssertEqual(coordinator.archiveWindows.count, 2)

        // Closing an archive leaves the launcher alone while other windows are open...
        a?.close()
        XCTAssertEqual(coordinator.archiveWindows.count, 1)
        XCTAssertFalse(try XCTUnwrap(coordinator.launcher.window).isVisible)
        live.close()
        XCTAssertTrue(try XCTUnwrap(coordinator.launcher.window).isVisible)

        // ...and with none left, the launcher shows.
        coordinator.launcher.window?.orderOut(nil)
        b?.close()
        XCTAssertTrue(coordinator.archiveWindows.isEmpty)
        XCTAssertTrue(try XCTUnwrap(coordinator.launcher.window).isVisible)
    }

    @MainActor
    func test_C_WIN_05_openingAnArchiveLeavesTheLauncherAsItIs() async throws {
        let (coordinator, _, _) = coordinator()
        coordinator.start()
        let launcher = try XCTUnwrap(coordinator.launcher.window)
        XCTAssertTrue(launcher.isVisible)
        _ = await coordinator.openArchive(try archive())
        XCTAssertTrue(launcher.isVisible)
    }

    // MARK: - C-ARCH-04

    @MainActor
    func test_C_ARCH_04_aFileThatCannotBeOpenedSaysWhy() async throws {
        let (coordinator, recents, failures) = coordinator()
        coordinator.start()
        let bad = try write(Data("hello".utf8), as: "Text.cutaway")
        let opened = await coordinator.openArchive(bad)
        XCTAssertNil(opened)
        XCTAssertTrue(coordinator.archiveWindows.isEmpty)
        XCTAssertEqual(failures.all.map(\.0), [bad])
        XCTAssertEqual(failures.all.map(\.1), [.notAnArchive])
        XCTAssertEqual(recents.urls, [])

        XCTAssertEqual(
            ArchiveOpenError.openFailureTitle(bad), "\u{201C}Text.cutaway\u{201D} can\u{2019}t be opened.")
        XCTAssertEqual(
            ArchiveOpenError.notAnArchive.openFailureText, "It isn\u{2019}t a Cutaway archive.")
        XCTAssertEqual(
            ArchiveOpenError.incomplete.openFailureText,
            "The file is incomplete. It may not have finished copying or downloading.")
        XCTAssertEqual(ArchiveOpenError.damaged.openFailureText, "The file is damaged.")
        XCTAssertEqual(
            ArchiveOpenError.newer.openFailureText,
            "It was saved by a newer version of Cutaway. Update Cutaway to open it.")
        XCTAssertEqual(
            ArchiveOpenError.otherMajor.openFailureText,
            "It was saved by a version of Cutaway that this one can\u{2019}t read.")
        XCTAssertEqual(ArchiveOpenError.unreadable("No such file.").openFailureText, "No such file.")
    }

    @MainActor
    func test_C_ARCH_04_openingAtLaunchShowsOnlyTheArchive() async throws {
        let (coordinator, _, _) = coordinator()
        coordinator.start(opening: [try archive()])
        let opened = await eventually { coordinator.archiveWindows.count == 1 }
        XCTAssertTrue(opened)
        XCTAssertFalse(try XCTUnwrap(coordinator.launcher.window).isVisible)

        let (other, _, failures) = self.coordinator()
        other.start(opening: [try write(Data("hello".utf8), as: "Bad.cutaway")])
        let shown = await eventually { other.launcher.window?.isVisible == true }
        XCTAssertTrue(shown, "with nothing opened, the launcher did not show")
        XCTAssertEqual(failures.all.count, 1)
    }

    @MainActor
    func test_C_ARCH_04_openedArchivesAreRecent() async throws {
        let (coordinator, recents, _) = coordinator()
        coordinator.start()
        let url = try archive()
        _ = await coordinator.openArchive(url)
        XCTAssertEqual(recents.urls, [url])

        let menu = NSMenu(title: "Open Recent")
        coordinator.menuNeedsUpdate(menu)
        XCTAssertEqual(menu.items.first?.title, "Demo.cutaway")
        XCTAssertEqual(menu.items.last?.title, "Clear Menu")
        coordinator.clearRecentArchives(nil)
        XCTAssertEqual(recents.urls, [])
    }
}
