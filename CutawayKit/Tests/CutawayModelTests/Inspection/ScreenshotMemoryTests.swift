import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import Foundation
import XCTest

@testable import CutawayModel

/// What the inspection keeps of its screenshots: only the compressed data, decompressed away
/// from the main thread, and nothing once the inspection is left (C-DET-08 to C-DET-10).
final class ScreenshotMemoryTests: XCTestCase {
    /// The fixtures' app without a connection (`MockResponder.demo()`): each batch is
    /// answered at once in one chunk. Its hierarchy can be made to fail.
    private actor DemoSource: InspectionSource {
        nonisolated var isLive: Bool { true }
        var negotiatedVersion: Version? { ProtocolVersion.current }
        private let responder: MockResponder
        private var hierarchyFailure: RequestError?
        private var detailsFailure: RequestError?

        init() throws {
            responder = try MockResponder.demo()
        }

        func failHierarchy(with failure: RequestError?) {
            hierarchyFailure = failure
        }

        func failDetails(with failure: RequestError?) {
            detailsFailure = failure
        }

        func hierarchy() async throws -> Hierarchy {
            if let hierarchyFailure { throw hierarchyFailure }
            return responder.hierarchy
        }

        func subtree(of rootID: UInt64) async throws -> Hierarchy {
            throw RequestError.unsupported
        }

        func layerDetails(_ request: GetLayerDetails) async -> LayerDetailsStream {
            let (chunks, continuation) = AsyncThrowingStream.makeStream(of: [LayerDetail].self)
            if let detailsFailure {
                continuation.finish(throwing: detailsFailure)
            } else {
                continuation.yield(responder.answer(request))
                continuation.finish()
            }
            return LayerDetailsStream(chunks: chunks, cancelAction: {})
        }

        func setAttribute(_ request: SetAttribute) async throws -> SetAttributeResult {
            throw RequestError.unsupported
        }
    }

    /// The fixture's images: layer 3's group and layer 4's solo (`layer-details`).
    private static func fixtureImages() throws -> (three: EncodedImage, four: EncodedImage) {
        let details = try Fixtures.layerDetails(scenario: "layer-details")
        let three = try XCTUnwrap(details.first { $0.layerID == 3 }?.group)
        let four = try XCTUnwrap(details.first { $0.layerID == 4 }?.solo)
        return (three, four)
    }

    /// An inspection of the demo source, decompressing with `tracker`, entered and with every
    /// screenshot of the fully expanded tree settled.
    @MainActor
    private func loadedModel(
        _ source: DemoSource, tracker: PixelTracker
    ) async throws -> InspectionStore {
        let model = InspectionStore(source: source, newLayers: .expanded)
        model.decodeImage = tracker.decode
        model.enter()
        let settled = await Self.screenshotsSettle(model)
        XCTAssertTrue(settled)
        return model
    }

    @MainActor
    private static func screenshotsSettle(_ model: InspectionStore) async -> Bool {
        await Wait.until {
            await MainActor.run {
                model.detailProgress.total > 0
                    && model.detailProgress.completed == model.detailProgress.total
                    && model.images[3] != nil && model.images[4] != nil
            }
        }
    }

    // MARK: - C-DET-08

    @MainActor
    func test_C_DET_08_theModelHoldsOnlyTheCompressedData() async throws {
        let tracker = PixelTracker()
        let model = try await loadedModel(try DemoSource(), tracker: tracker)
        let fixture = try Self.fixtureImages()

        XCTAssertEqual(model.images[3]?.group?.image, fixture.three)
        XCTAssertEqual(model.images[4]?.solo?.image, fixture.four)
        // Layer 3's group, 4's solo and 8's group (`layer-details-edge`).
        XCTAssertEqual(tracker.callCount, 3, "each image is decompressed once on arrival")
        XCTAssertEqual(tracker.liveCount, 0, "decompressed pixels outlived the arrival")
        model.leave()
    }

    @MainActor
    func test_C_DET_08_anExportedHeldImageIsDecompressedAgain() async throws {
        let tracker = PixelTracker()
        let model = try await loadedModel(try DemoSource(), tracker: tracker)
        let calls = tracker.callCount

        do {
            let exported = try await model.exportImage(of: 4, kind: .solo)
            XCTAssertEqual(exported, try Self.fixtureImages().four.decoded())
        }
        XCTAssertEqual(tracker.callCount, calls + 1)
        XCTAssertEqual(tracker.liveCount, 0)
        model.leave()
    }

    @MainActor
    func test_C_DET_08_pixelsAreGivenOnlyForImagesHeldUnderThatRevision() async throws {
        let tracker = PixelTracker()
        let model = try await loadedModel(try DemoSource(), tracker: tracker)
        let keys = try XCTUnwrap(model.images[4]).textures(layerID: 4)
        let held = try XCTUnwrap(keys.solo)
        let stale = TextureKey(layerID: 4, kind: .solo, revision: held.revision + 100)
        let missing = TextureKey(layerID: 4, kind: .group, revision: held.revision)

        let pixels = await model.pixels(for: [held, stale, missing])
        XCTAssertEqual(Set(pixels.keys), [held])
        XCTAssertEqual(pixels[held], try Self.fixtureImages().four.decoded())
        model.leave()
    }

    // MARK: - C-DET-09

    @MainActor
    func test_C_DET_09_everyDecompressionIsOffTheMainThread() async throws {
        let tracker = PixelTracker()
        let model = try await loadedModel(try DemoSource(), tracker: tracker)

        _ = try await model.exportImage(of: 4, kind: .solo)  // held
        _ = try await model.exportImage(of: 3, kind: .solo)  // asked for
        let keys = try XCTUnwrap(model.images[3]).textures(layerID: 3)
        _ = await model.pixels(for: [try XCTUnwrap(keys.group)])

        XCTAssertEqual(tracker.callCount, 6)  // three on arrival
        XCTAssertEqual(tracker.mainThreadCallCount, 0, "an image was decompressed on the main thread")
        model.leave()
    }

    /// Lets a decompression through once the test opens it.
    private final class DecodeGate: Sendable {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)

        /// Whether a decompression started within three seconds.
        func waitUntilEntered() -> Bool {
            entered.wait(timeout: .now() + 3) == .success
        }
    }

    @MainActor
    func test_C_DET_09_aBatchLeftWhileItsChunkIsDecompressedTakesNothingIn() async throws {
        let model = InspectionStore(source: try DemoSource(), newLayers: .expanded)
        let gate = DecodeGate()
        model.decodeImage = { image in
            gate.entered.signal()
            gate.release.wait()
            return try image.decoded()
        }
        model.enter()
        let entered = await Task.detached { gate.waitUntilEntered() }.value
        XCTAssertTrue(entered)

        model.leave()
        for _ in 0..<4 { gate.release.signal() }
        let taken = await Wait.until(within: .milliseconds(500)) {
            await MainActor.run { !model.images.isEmpty }
        }
        XCTAssertFalse(taken, "a chunk of a batch that was left was taken in")
    }

    // MARK: - C-DET-10

    @MainActor
    func test_C_DET_10_leavingReleasesTheScreenshotsAndEnteringTakesThemAgain() async throws {
        let tracker = PixelTracker()
        let model = try await loadedModel(try DemoSource(), tracker: tracker)
        model.setExpanded(6, false)
        model.select(4)
        let settled = await Self.screenshotsSettle(model)
        XCTAssertTrue(settled)

        model.leave()
        XCTAssertTrue(model.images.isEmpty)
        XCTAssertNil(model.layout.texture(of: 3))
        XCTAssertNil(model.layout.texture(of: 4))
        XCTAssertEqual(tracker.liveCount, 0)

        let calls = tracker.callCount
        model.enter()
        let again = await Self.screenshotsSettle(model)
        XCTAssertTrue(again, "the screenshots did not come again")
        XCTAssertGreaterThan(tracker.callCount, calls)
        XCTAssertFalse(model.isExpanded(6))
        XCTAssertTrue(model.isExpanded(1))
        XCTAssertEqual(model.selectedLayerID, 4)
        model.leave()
    }

    @MainActor
    func test_C_DET_10_aFailedReloadAfterComingBackStillTakesTheScreenshots() async throws {
        let source = try DemoSource()
        let model = try await loadedModel(source, tracker: PixelTracker())
        model.leave()

        await source.failHierarchy(with: .timedOut)
        model.enter()
        let failed = await Wait.until { await MainActor.run { model.notice == .layersFailed } }
        XCTAssertTrue(failed)
        let again = await Self.screenshotsSettle(model)
        XCTAssertTrue(again, "the screenshots released on leaving were not asked for again")
        model.leave()
    }

    @MainActor
    func test_C_DET_10_screenshotsThatStoppedBeforeLeavingAreTakenAfterComingBack() async throws {
        let source = try DemoSource()
        await source.failDetails(with: .timedOut)
        let model = InspectionStore(source: source, newLayers: .expanded)
        model.enter()
        let stopped = await Wait.until {
            await MainActor.run { model.notice == .screenshotsFailed }
        }
        XCTAssertTrue(stopped)
        model.leave()

        await source.failDetails(with: nil)
        await source.failHierarchy(with: .timedOut)
        model.enter()
        let again = await Self.screenshotsSettle(model)
        XCTAssertTrue(again, "asking for screenshots stayed stopped after coming back")
        model.leave()
    }

    // Through the app list, which leaves an inspection when another app is inspected and keeps
    // what a lost app showed (C-WIN-03).

    private static let demo = AppInfo(
        name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.1.0")

    /// A server that answers as the fixtures' app does, and a session to it.
    private static func demoApp() async throws -> (MockServer, Session) {
        let steps = try MockScript.fixtures("handshake").steps + [.respond(try MockResponder.demo())]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: ClientInfo(name: "Cutaway", version: "0.1.0"))
        _ = try await session.handshake()
        return (server, session)
    }

    @MainActor
    func test_C_DET_10_inspectingAnotherAppReleasesTheFirstOnesScreenshots() async throws {
        let (firstServer, firstSession) = try await Self.demoApp()
        let (secondServer, secondSession) = try await Self.demoApp()
        let first = AppLocation.simulator(port: firstServer.port)
        let second = AppLocation.simulator(port: secondServer.port)
        var other = Self.demo
        other.bundleID = "dev.cutaway.other"
        let list = AppListStore()
        list.apply(.found(first, Self.demo, firstSession))
        list.apply(.found(second, other, secondSession))
        let tracker = PixelTracker()

        list.inspect(first)
        let inspection = try XCTUnwrap(list.inspection(at: first))
        // Set before any screenshot is asked for: that waits for the icon and the tree.
        inspection.decodeImage = tracker.decode
        let shown = await Self.screenshotsSettle(inspection)
        XCTAssertTrue(shown)

        list.inspect(second)
        XCTAssertTrue(list.inspection(at: first) === inspection, "the state is kept (C-HIER-02)")
        XCTAssertTrue(inspection.images.isEmpty, "the first app's screenshots were kept")
        XCTAssertEqual(tracker.liveCount, 0)

        list.leaveInspection()
        await firstSession.close()
        await secondSession.close()
        await firstServer.stop()
        await secondServer.stop()
    }

    @MainActor
    func test_C_DET_10_C_WIN_03_anAppThatGoesAwayKeepsItsLastScreenshots() async throws {
        let (server, session) = try await Self.demoApp()
        let location = AppLocation.simulator(port: server.port)
        let list = AppListStore()
        list.apply(.found(location, Self.demo, session))
        list.inspect(location)
        let inspection = try XCTUnwrap(list.inspection(at: location))
        let shown = await Self.screenshotsSettle(inspection)
        XCTAssertTrue(shown)
        let held = inspection.images

        list.apply(.lost(location))
        XCTAssertNil(list.inspection(at: location))
        XCTAssertEqual(inspection.images, held, "the window lost its last picture")

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_10_C_WIN_03_aLostAppKeepsItsLastScreenshots() async throws {
        let model = try await loadedModel(try DemoSource(), tracker: PixelTracker())
        let held = model.images

        model.connectionLost()
        model.leave()
        XCTAssertEqual(model.images, held)
        XCTAssertNotNil(model.layout.texture(of: 3))
    }
}
