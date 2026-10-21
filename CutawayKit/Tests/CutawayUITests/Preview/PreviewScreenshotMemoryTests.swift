import AppKit
import CutawayRender
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// The preview keeps textures and no pixels, decompressing takes no time on the main thread,
/// and a closed archive window lets go of everything (C-DET-08 to C-DET-10).
final class PreviewScreenshotMemoryTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    /// A model with the `hierarchy` fixture, decompressing with `tracker`.
    @MainActor
    private func model(_ tracker: PixelTracker) throws -> InspectionStore {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        model.decodeImage = tracker.decode
        model.apply(try Fixtures.hierarchy())
        return model
    }

    /// A preview controller in a window that is never shown, laid out at 480 × 900.
    @MainActor
    private func previewInWindow(
        _ model: InspectionStore, motion: PreviewMotion = .system
    ) throws -> (PreviewViewController, PreviewView, NSWindow) {
        let controller = PreviewViewController(store: model, motion: motion)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 900), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 480, height: 900))
        window.layoutIfNeeded()
        return (controller, try XCTUnwrap(controller.preview), window)
    }

    /// The keys of every image the model holds.
    @MainActor
    private static func heldKeys(_ model: InspectionStore) -> [TextureKey] {
        model.images.flatMap { id, images -> [TextureKey] in
            let names = images.textures(layerID: id)
            return [names.solo, names.group].compactMap { $0 }
        }
    }

    /// Checks that the preview holds the textures of the images drawn and no others.
    @MainActor
    private func assertKeepsWhatIsDrawn(
        _ preview: PreviewView, _ model: InspectionStore, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let drawn = model.layout.drawnTextures
        XCTAssertEqual(preview.textures.keys, drawn, file: file, line: line)
        XCTAssertTrue(
            drawn.isSubset(of: Self.heldKeys(model)), "a drawn image is not held", file: file,
            line: line)
    }

    // MARK: - C-DET-08

    @MainActor
    func test_C_DET_08_thePreviewKeepsTexturesAndNoPixels() async throws {
        let tracker = PixelTracker()
        let model = try model(tracker)
        let (_, preview, window) = try previewInWindow(model)
        defer { withExtendedLifetime(window) {} }

        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details"))

        let keys = Self.heldKeys(model)
        XCTAssertEqual(Set(keys.map(\.layerID)), [3, 4])
        XCTAssertEqual(Set(model.layout.drawnTextures.map(\.layerID)), [3, 4])
        assertKeepsWhatIsDrawn(preview, model)
        XCTAssertEqual(tracker.callCount, keys.count, "an image was decompressed more than once")
        XCTAssertEqual(tracker.liveCount, 0, "decompressed pixels outlived the upload")
    }

    @MainActor
    func test_C_DET_08_aPreviewMadeLaterDecompressesWhatItLacks() async throws {
        let tracker = PixelTracker()
        let model = try model(tracker)
        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details"))
        let keys = Self.heldKeys(model)

        let (controller, preview, window) = try previewInWindow(model)
        defer { withExtendedLifetime(window) {} }
        await controller.texturesSettled()

        assertKeepsWhatIsDrawn(preview, model)
        XCTAssertEqual(
            tracker.callCount, keys.count + model.layout.drawnTextures.count,
            "each drawn image decompressed once more")
        XCTAssertEqual(tracker.mainThreadCallCount, 0)
        XCTAssertEqual(tracker.liveCount, 0)
        // Drawn with them: layer 3 is opaque red (C-REND-01).
        let image = try preview.snapshot()
        let point = try XCTUnwrap(preview.imagePoint(ofCenterOf: 3))
        let pixel = image.pixel(x: Int(point.x), y: Int(point.y))
        XCTAssertEqual([pixel.red, pixel.green, pixel.blue, pixel.alpha], [255, 0, 0, 255])
    }

    // MARK: - C-SCALE-02

    @MainActor
    func test_C_SCALE_02_collapsingDropsTheTexturesOfLayersNoLongerDrawn() async throws {
        let tracker = PixelTracker()
        let model = try model(tracker)
        let (_, preview, window) = try previewInWindow(model)
        defer { withExtendedLifetime(window) {} }
        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details"))
        XCTAssertFalse(preview.textures.keys.isEmpty)

        // Layers 3 and 4 are inside layer 2, which has no image.
        model.setExpanded(2, false)

        XCTAssertEqual(preview.textures.keys, [])
        assertKeepsWhatIsDrawn(preview, model)
        XCTAssertEqual(Set(model.images.keys), [3, 4], "the model still holds the images")
    }

    @MainActor
    func test_C_SCALE_02_reExpandingUploadsThemAgain() async throws {
        let tracker = PixelTracker()
        let model = try model(tracker)
        let (controller, preview, window) = try previewInWindow(model)
        defer { withExtendedLifetime(window) {} }
        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details"))
        let drawn = model.layout.drawnTextures
        model.setExpanded(2, false)
        let decompressed = tracker.callCount

        model.setExpanded(2, true)
        await controller.texturesSettled()

        XCTAssertEqual(preview.textures.keys, drawn)
        assertKeepsWhatIsDrawn(preview, model)
        XCTAssertEqual(tracker.callCount, decompressed + drawn.count)
        XCTAssertEqual(tracker.mainThreadCallCount, 0)
        XCTAssertEqual(tracker.liveCount, 0)
        // Drawn with them: layer 3 is opaque red (C-REND-01).
        let image = try preview.snapshot()
        let point = try XCTUnwrap(preview.imagePoint(ofCenterOf: 3))
        let pixel = image.pixel(x: Int(point.x), y: Int(point.y))
        XCTAssertEqual([pixel.red, pixel.green, pixel.blue, pixel.alpha], [255, 0, 0, 255])
    }

    @MainActor
    func test_C_SCALE_02_aTransitionKeepsBothEndsUntilItEnds() async throws {
        let model = try model(PixelTracker())
        let clock = ManualClock()
        let (controller, preview, window) = try previewInWindow(model, motion: .paced(by: clock))
        defer { withExtendedLifetime(window) {} }
        await model.applyDetails(try Fixtures.layerDetails(scenario: "layer-details"))
        let expanded = model.layout.drawnTextures
        XCTAssertFalse(expanded.isEmpty)

        model.setExpanded(2, false)
        XCTAssertTrue(controller.isInTransition)
        clock.advance(by: PreviewMotion.duration / 2)
        XCTAssertEqual(preview.textures.keys, expanded, "the sublayers come down with images")

        clock.advance(by: PreviewMotion.duration)
        XCTAssertFalse(controller.isInTransition)
        XCTAssertEqual(preview.textures.keys, [])
        assertKeepsWhatIsDrawn(preview, model)
    }

    @MainActor
    func test_C_SCALE_02_imagesThatComeSoonAfterOthersWaitAndAreShownTogether() async throws {
        let model = try model(PixelTracker())
        let (controller, preview, window) = try previewInWindow(model)
        defer { withExtendedLifetime(window) {} }
        // Long enough that the second chunk comes within it on a busy machine too.
        try XCTUnwrap(controller.projector).imagesInterval = .milliseconds(500)
        let details = try Fixtures.layerDetails(scenario: "layer-details")
        let three = try XCTUnwrap(details.first { $0.layerID == 3 })
        let four = try XCTUnwrap(details.first { $0.layerID == 4 })
        func drawnTexture(_ id: UInt64) -> TextureKey? {
            preview.drawList.items.first { $0.layerID == id }?.texture
        }

        // The first images after a quiet spell show at once.
        await model.applyDetails([three])
        XCTAssertNotNil(drawnTexture(3))
        // The next, soon after, wait for the rest of the interval.
        await model.applyDetails([four])
        XCTAssertNil(drawnTexture(4), "shown within the interval")
        XCTAssertNotNil(model.layout.texture(of: 4))
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertNotNil(drawnTexture(4), "not shown once the interval was over")
        assertKeepsWhatIsDrawn(preview, model)

        // Anything else shown meanwhile shows them too.
        model.setExpanded(2, false)
        model.setExpanded(2, true)
        try await Task.sleep(for: .milliseconds(700))
        let again = try XCTUnwrap(
            Fixtures.layerDetails(scenario: "layer-details").first { $0.layerID == 3 })
        await model.applyDetails([again])
        await model.applyDetails([four])
        XCTAssertNotEqual(drawnTexture(4), model.layout.texture(of: 4))
        model.hover(3)
        XCTAssertEqual(drawnTexture(4), model.layout.texture(of: 4))
        assertKeepsWhatIsDrawn(preview, model)
    }

    // MARK: - C-DET-09

    /// How late blocks run on the main queue: a thread of its own queues one every 2 ms, and
    /// each records how long it waited.
    private final class MainThreadWatch: @unchecked Sendable {
        private let lock = NSLock()
        private var longest: TimeInterval = 0
        private var watching = true

        func start() {
            Thread.detachNewThread { [self] in
                while isWatching {
                    let queued = ProcessInfo.processInfo.systemUptime
                    DispatchQueue.main.async {
                        self.record(ProcessInfo.processInfo.systemUptime - queued)
                    }
                    Thread.sleep(forTimeInterval: 0.002)
                }
            }
        }

        /// Stops queueing, and returns the longest wait in seconds.
        func stop() -> TimeInterval {
            lock.withLock {
                watching = false
                return longest
            }
        }

        private var isWatching: Bool { lock.withLock { watching } }

        private func record(_ wait: TimeInterval) {
            lock.withLock {
                if watching { longest = max(longest, wait) }
            }
        }
    }

    @MainActor
    func test_C_DET_09_eightLargeImagesInOneChunkNeverHoldTheMainThreadFor50Milliseconds()
        async throws
    {
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
        let model = try model(PixelTracker())
        let (_, preview, window) = try previewInWindow(model)
        defer { withExtendedLifetime(window) {} }
        // 2048 × 2048: 16 MiB of pixels each, 128 MiB in the chunk.
        let image = await Task.detached {
            EncodedImage.gradient(pixelWidth: 2048, pixelHeight: 2048)
        }.value
        let ids = Array(model.tree.ids.prefix(8))
        XCTAssertEqual(ids.count, 8)
        let chunk = ids.map {
            LayerDetail(
                layerID: $0, status: .ok, solo: image, group: nil, attributeGroups: [])
        }

        let watch = MainThreadWatch()
        watch.start()
        // Let the watch settle in before the chunk comes.
        try await Task.sleep(for: .milliseconds(50))
        await model.applyDetails(chunk)
        // The blocks queued while the main thread was busy run now.
        try await Task.sleep(for: .milliseconds(50))
        let longest = watch.stop()

        XCTAssertEqual(Self.heldKeys(model).count, 8)
        // Layer 5 is hidden, so not drawn.
        XCTAssertEqual(model.layout.drawnTextures.count, 7)
        assertKeepsWhatIsDrawn(preview, model)
        XCTAssertLessThanOrEqual(
            longest, 0.05,
            "the main thread was held for \(Int(longest * 1000)) ms taking in the chunk")
    }

    // MARK: - C-DET-10

    @MainActor
    func test_C_DET_10_closingAnArchiveWindowReleasesEverything() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewScreenshotMemoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Demo.cutaway")
        try Fixtures.archive().write(to: url)
        let coordinator = WindowCoordinator(store: AppListStore(), discoversDevices: false)
        // What is checked is Cutaway's own references (`ClosingWindow`).
        coordinator.animatesWindows = false
        coordinator.presentOpenFailure = { _, error in XCTFail("\(error)") }
        defer { coordinator.launcher.close() }

        weak var controller: InspectorWindowController?
        weak var inspection: InspectionStore?
        weak var source: AnyObject?
        weak var previewController: PreviewViewController?
        weak var textures: TextureCache?
        weak var window: NSWindow?
        do {
            let archiveWindow = await coordinator.openArchive(url)
            let opened = try XCTUnwrap(archiveWindow)
            let loaded = await Wait.untilOnMain { opened.store.loadState == .loaded }
            XCTAssertTrue(loaded)
            // The archive keeps no interface state, so only the root is expanded.
            opened.store.expandAll()
            let shown = await Wait.untilOnMain {
                opened.store.images[3] != nil && opened.store.images[4] != nil
                    && opened.store.detailProgress.completed == opened.store.detailProgress.total
            }
            XCTAssertTrue(shown, "the archive's screenshots did not show")
            controller = opened
            inspection = opened.store
            source = opened.store.source
            previewController = opened.splitController.previewController
            textures = opened.splitController.previewController.preview?.textures
            XCTAssertNotNil(textures)
            window = opened.window
            opened.close()
        }

        let deadline = Date().addingTimeInterval(8)
        while controller != nil || inspection != nil || source != nil
            || previewController != nil || textures != nil, Date() < deadline
        {
            try await Task.sleep(for: .milliseconds(50))
        }
        let note = ClosingWindow.lingeringNote(window)
        XCTAssertTrue(coordinator.archiveWindows.isEmpty)
        XCTAssertNil(controller, "the archive window's controller outlived it\(note)")
        XCTAssertNil(inspection, "the archive's inspection outlived its window\(note)")
        XCTAssertNil(source, "the archive outlived its window\(note)")
        XCTAssertNil(previewController, "the preview's controller outlived the window\(note)")
        XCTAssertNil(textures, "the textures outlived the window\(note)")
    }
}
