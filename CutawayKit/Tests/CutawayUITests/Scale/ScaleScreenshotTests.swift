import AppKit
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// C-SCALE-04: with batches of 32 layers, two of them under way, an inspection window takes
/// every screenshot of 5,000 layers at least 30% faster than with the scheduling of before,
/// batches of 8 one after another. Both are timed in the same test, on the same
/// machine, so that the comparison does not depend on how fast it is.
final class ScaleScreenshotTests: XCTestCase {
    private static let scene = SyntheticScene(
        layerCount: 5_000, shape: .app(AppShape()), imagePixels: .fixed(width: 32, height: 32),
        attributes: false, constraints: false)

    /// How long a shown window takes from being entered to every screenshot it needs.
    @MainActor
    private func timeEveryScreenshot(batchSize: Int, batchesInFlight: Int) async throws -> Duration {
        let server = try await MockServer.start(
            script: MockScript(
                steps: try MockScript.fixtures("handshake").steps + [.respond(Self.scene.responder())]),
            records: false)
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: ClientInfo(name: "Cutaway", version: "0.1.0"), requestTimeout: .seconds(30))
        _ = try await session.handshake()
        let model = InspectionStore(session: session, maxTextureDimension: 4096)
        model.screenshotBatchSize = batchSize
        model.screenshotBatchesInFlight = batchesInFlight
        let inspector = InspectorWindowController(location: .simulator(port: server.port), entry: nil, store: model)
        inspector.showWindow(nil)
        let start = ContinuousClock.now
        model.enter()
        let done = await Wait.untilOnMain(within: .seconds(60)) {
            model.detailProgress.total > 0 && model.detailProgress.completed == model.detailProgress.total
        }
        let elapsed = ContinuousClock.now - start
        XCTAssertTrue(done, "\(model.detailProgress)")
        XCTAssertGreaterThan(model.detailProgress.total, 4_000)
        model.leave()
        inspector.window?.animationBehavior = .none
        inspector.close()
        await session.close()
        await server.stop()
        return elapsed
    }

    @MainActor
    func test_C_SCALE_04_everyScreenshotIsTakenAtLeastThirtyPercentFaster() async throws {
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
        let now = (size: DetailScheduler.defaultBatchSize, inFlight: DetailScheduler.batchesInFlight)
        XCTAssertEqual(now.size, 32)
        XCTAssertEqual(now.inFlight, 2)
        // A first run warms the caches, so that neither of the two compared pays for it.
        _ = try await timeEveryScreenshot(batchSize: now.size, batchesInFlight: now.inFlight)
        let before = try await timeEveryScreenshot(batchSize: 8, batchesInFlight: 1)
        let after = try await timeEveryScreenshot(batchSize: now.size, batchesInFlight: now.inFlight)
        print("C-SCALE-04: every screenshot of 5,000 layers, 8 a batch one after another \(before), now \(after)")
        XCTAssertLessThanOrEqual(after, before * 0.7, "before \(before), now \(after)")
    }
}
