import AppKit
import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import ImageIO
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// C-ARCH-06: where a layer's screenshot is exported from, and what a failure says.
final class ExportMenuTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportMenuTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A live inspector whose session never connected, with the fixtures' tree.
    @MainActor
    private func liveInspector() throws -> InspectorWindowController {
        let session = Session(
            channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0"))
        let model = InspectionStore(session: session)
        model.apply(try Fixtures.hierarchy())
        let inspector = InspectorWindowController(
            location: .simulator(port: 48160), entry: nil, store: model)
        addTeardownBlock { @MainActor in inspector.close() }
        return inspector
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

    @MainActor
    func test_C_ARCH_06_anArchivesLayerIsExportedAsAPNG() async throws {
        let url = directory.appendingPathComponent("Demo.cutaway")
        try Fixtures.archive().write(to: url)
        let coordinator = WindowCoordinator(store: AppListStore(), discoversDevices: false)
        coordinator.recents = MemoryRecentArchives()
        let opened = await coordinator.openArchive(url)
        let inspector = try XCTUnwrap(opened)
        addTeardownBlock { @MainActor in inspector.close() }
        let loaded = await eventually { inspector.store.loadState == .loaded }
        XCTAssertTrue(loaded)

        var suggested: String?
        let png = directory.appendingPathComponent("Layer.png")
        inspector.fileActions.chooseScreenshotDestination = { _, name, done in
            suggested = name
            done(png)
        }
        let item = NSMenuItem(
            title: "", action: #selector(InspectorWindowController.exportScreenshotWithSublayers(_:)),
            keyEquivalent: "")
        item.representedObject = UInt64(8)
        XCTAssertTrue(inspector.validateMenuItem(item))
        inspector.exportScreenshotWithSublayers(item)
        XCTAssertEqual(suggested, "CALayer 8 with Sublayers")

        let written = await eventually { FileManager.default.fileExists(atPath: png.path) }
        XCTAssertTrue(written)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(png as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 60)
        XCTAssertEqual(image.height, 30)

        // Layer 1 has no image in the archive: not offered.
        item.representedObject = UInt64(1)
        XCTAssertFalse(inspector.validateMenuItem(item))
    }

    @MainActor
    func test_C_ARCH_06_aFailedExportSaysWhy() async throws {
        let inspector = try liveInspector()
        inspector.showWindow(nil)
        inspector.fileActions.chooseScreenshotDestination = { [directory] _, _, done in
            done(directory!.appendingPathComponent("Layer.png"))
        }
        inspector.store.select(4)
        inspector.exportLayerScreenshot(nil)

        let container = inspector.splitController.containerController
        let panel = try XCTUnwrap(
            ExportMenuViews.views(in: container.view, identifier: "preview.screenshotFailed").first)
        let shown = await eventually { !panel.isHidden }
        XCTAssertTrue(shown, "nothing said the screenshot was not exported")
        let text = try XCTUnwrap(
            ExportMenuViews.views(in: container.view, identifier: "preview.screenshotFailed.text").first
                as? NSTextField)
        XCTAssertEqual(
            text.stringValue,
            "The screenshot wasn\u{2019}t exported: the connection to Unnamed app was lost.")
        // The panel is as wide as its text (as the notice's, C-DET-04).
        container.view.window?.layoutIfNeeded()
        XCTAssertFalse(panel.hasAmbiguousLayout)
        XCTAssertGreaterThanOrEqual(text.frame.width + 0.5, text.intrinsicContentSize.width)
        XCTAssertTrue(panel.bounds.insetBy(dx: -0.5, dy: -0.5).contains(
            text.convert(text.bounds, to: panel)))
        let ok = try XCTUnwrap(
            ExportMenuViews.views(in: container.view, identifier: "preview.screenshotFailed.ok").first
                as? NSButton)
        ok.performClick(nil)
        let dismissed = await eventually { panel.isHidden }
        XCTAssertTrue(dismissed)

        XCTAssertEqual(
            PreviewPaneText.screenshotFailureText(.layerGone, appName: "Demo"),
            "The screenshot wasn\u{2019}t exported: the layer is no longer in Demo.")
        XCTAssertEqual(
            PreviewPaneText.screenshotFailureText(.notCaptured, appName: "Demo"),
            "The screenshot wasn\u{2019}t exported: Demo couldn\u{2019}t capture this layer.")
        XCTAssertEqual(
            PreviewPaneText.screenshotFailureText(.appNotActive, appName: "Demo"),
            "The screenshot wasn\u{2019}t exported: Demo went to the background.")
        XCTAssertEqual(
            PreviewPaneText.screenshotFailureText(.other, appName: "Demo"),
            "The screenshot wasn\u{2019}t exported: Demo didn\u{2019}t send it.")
        XCTAssertEqual(
            PreviewPaneText.screenshotFailureText(.writeFailed("Disk full."), appName: "Demo"),
            "The screenshot wasn\u{2019}t exported: the file couldn\u{2019}t be written. Disk full.")
    }
}

/// Views by accessibility identifier.
@MainActor
enum ExportMenuViews {
    static func views(in view: NSView, identifier: String) -> [NSView] {
        var matches = view.accessibilityIdentifier() == identifier ? [view] : []
        for subview in view.subviews {
            matches += views(in: subview, identifier: identifier)
        }
        return matches
    }
}
