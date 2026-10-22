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
}
