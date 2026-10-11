import AppKit
import CutawayTestSupport
import CutawayUI
import CutawayWire
import ImageIO
import XCTest

@testable import Cutaway

/// End to end: the running app exports a layer's screenshot as a PNG,
/// from an app and from an archive (C-ARCH-06).
final class ScreenshotExportExitTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotExportExitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
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
    private func menuItem(_ title: String) throws -> NSMenuItem {
        try XCTUnwrap(
            NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items)
                .first { $0.title == title },
            "no menu item \(title)")
    }

    /// The PNG's size and its first pixel, drawn into premultiplied BGRA.
    private func read(_ url: URL) throws -> (width: Int, height: Int, pixel: [UInt8]) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixel = [UInt8](repeating: 0, count: 4)
        let info = CGBitmapInfo.byteOrder32Little.rawValue
            | CGImageAlphaInfo.premultipliedFirst.rawValue
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        pixel.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: space, bitmapInfo: info)
            // The image's top-left pixel lands on the one-pixel context.
            context?.draw(
                image, in: CGRect(x: 0, y: 1 - image.height, width: image.width, height: image.height))
        }
        return (image.width, image.height, pixel)
    }

    @MainActor
    func test_C_ARCH_06_theRunningAppExportsALayerOnlineAndOffline() async throws {
        let coordinator = try AppWindows.coordinator()
        let recents = coordinator.recents
        coordinator.recents = MemoryRecentArchives()
        addTeardownBlock { @MainActor in
            for window in coordinator.archiveWindows { window.close() }
            coordinator.recents = recents
        }

        // Online: CardView's own screenshot, from the File menu with CardView selected.
        let script = MockScript(
            steps: try MockScript.fixtures("handshake").steps + [.respond(try MockResponder.demo())])
        let server = try await AppWindows.startMockServer(script)
        addTeardownBlock {
            await AppWindows.closeInspectors()
            await server.stop()
            _ = await AppWindows.waitForAppRow(named: "Demo", toExist: false, within: 5)
        }
        try await AppWindows.chooseApp(named: "Demo", server: server)
        let inspector = try XCTUnwrap(
            AppWindows.inspectorWindows().first?.windowController as? InspectorWindowController)
        let outline = try XCTUnwrap(
            AppWindows.views(identifier: "hierarchy.outline").first as? NSOutlineView)
        let loaded = await eventually { outline.numberOfRows > 3 }
        XCTAssertTrue(loaded)
        outline.selectRowIndexes([3], byExtendingSelection: false)  // CardView, layer 4

        let online = directory.appendingPathComponent("CardView.png")
        inspector.chooseScreenshotDestination = { _, name, done in
            XCTAssertEqual(name, "CardView 4")
            done(online)
        }
        let export = try menuItem("Export Layer Screenshot\u{2026}")
        let enabled = await eventually { inspector.validateMenuItem(export) }
        XCTAssertTrue(enabled)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(export.action), to: inspector, from: export))
        let exported = await eventually { FileManager.default.fileExists(atPath: online.path) }
        XCTAssertTrue(exported, "no PNG from the app")
        let green = try read(online)
        XCTAssertEqual(green.width, 300)
        XCTAssertEqual(green.height, 180)
        XCTAssertEqual(green.pixel, [0x00, 0xFF, 0x00, 0xFF])

        // Offline: layer 8 with its sublayers, from an archive's row menu.
        let archive = directory.appendingPathComponent("Demo.cutaway")
        try Fixtures.archive().write(to: archive)
        let opened = await coordinator.openArchive(archive)
        let window = try XCTUnwrap(opened)
        let archiveOutline = try XCTUnwrap(
            AppWindows.views(in: try XCTUnwrap(window.window?.contentView), identifier: "hierarchy.outline")
                .first as? NSOutlineView)
        let archived = await eventually { archiveOutline.numberOfRows > 0 }
        XCTAssertTrue(archived)
        let offline = directory.appendingPathComponent("Divider.png")
        window.chooseScreenshotDestination = { _, _, done in done(offline) }
        // As the row menu has it: the File menu's command, for that row's layer.
        let item = NSMenuItem(
            title: "", action: try menuItem("Export Screenshot with Sublayers\u{2026}").action,
            keyEquivalent: "")
        item.representedObject = UInt64(8)
        XCTAssertTrue(window.validateMenuItem(item))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: window, from: item))
        let written = await eventually { FileManager.default.fileExists(atPath: offline.path) }
        XCTAssertTrue(written, "no PNG from the archive")
        let orange = try read(offline)
        XCTAssertEqual(orange.width, 60)
        XCTAssertEqual(orange.height, 30)
        XCTAssertEqual(orange.pixel, [0x00, 0x80, 0xFF, 0xFF])
    }
}
