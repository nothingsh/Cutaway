import AppKit
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel
@testable import CutawayUI

/// C-SCALE-05: once an inspection window holds every screenshot of 5,000 layers, ⌘R where the
/// app answers every image as unchanged decompresses nothing, makes no texture, and takes at
/// most half the time the first screenshots took (measured 0.32 to 0.36).
final class ScaleRefreshTests: XCTestCase {
    private static let scene = SyntheticScene(
        layerCount: 5_000, shape: .app(AppShape()), imagePixels: .fixed(width: 32, height: 32),
        attributes: false, constraints: false)

    /// Counts the images decompressed.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func add() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    private struct Timing {
        var first: Duration
        var refresh: Duration
        var firstBytes: Int
        var refreshBytes: Int
    }

    @MainActor
    private func timeFirstAndRefresh() async throws -> Timing {
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
        let decoded = Counter()
        model.decodeImage = { image in
            decoded.add()
            return try image.decoded()
        }
        let inspector = InspectorWindowController(location: .simulator(port: server.port), entry: nil, store: model)
        inspector.showWindow(nil)
        func roundDone() -> Bool {
            model.loadState == .loaded && model.detailProgress.total > 0
                && model.detailProgress.completed == model.detailProgress.total
        }

        let bytesBefore = await server.writtenByteCount
        let start = ContinuousClock.now
        model.enter()
        let first = await Wait.untilOnMain(within: .seconds(60)) { roundDone() }
        let firstTime = ContinuousClock.now - start
        XCTAssertTrue(first, "\(model.detailProgress)")
        XCTAssertGreaterThan(model.detailProgress.total, 4_000)
        let capabilities = await Wait.untilOnMain { model.reusesImages }
        XCTAssertTrue(capabilities)
        let bytesAfterFirst = await server.writtenByteCount

        let decodedBefore = decoded.count
        let revision = model.nextImageRevision
        var arriving = 0
        let subscription = model.arrivingPixels.sink { _ in arriving += 1 }
        let refreshStart = ContinuousClock.now
        model.refresh()
        let started = await Wait.untilOnMain(within: .seconds(10)) { !roundDone() }
        XCTAssertTrue(started, "the refresh starts a round")
        let second = await Wait.untilOnMain(within: .seconds(60)) { roundDone() }
        let refreshTime = ContinuousClock.now - refreshStart
        XCTAssertTrue(second, "\(model.detailProgress)")
        subscription.cancel()
        XCTAssertEqual(decoded.count, decodedBefore, "nothing decompressed")
        XCTAssertEqual(arriving, 0, "no texture made")
        XCTAssertEqual(model.nextImageRevision, revision)
        let bytesAfterRefresh = await server.writtenByteCount

        model.leave()
        inspector.window?.animationBehavior = .none
        inspector.close()
        await session.close()
        await server.stop()
        return Timing(
            first: firstTime, refresh: refreshTime, firstBytes: bytesAfterFirst - bytesBefore,
            refreshBytes: bytesAfterRefresh - bytesAfterFirst)
    }

    @MainActor
    func test_C_SCALE_05_aRefreshWhereNothingChangedTakesAFractionOfTheFirstScreenshots() async throws {
        try XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)
        // A first run warms the caches.
        _ = try await timeFirstAndRefresh()
        let timing = try await timeFirstAndRefresh()
        let ratio = timing.refresh / timing.first
        print(
            "C-SCALE-05: every screenshot of 5,000 layers \(timing.first), \(timing.firstBytes) bytes;",
            "the refresh where nothing changed \(timing.refresh), \(timing.refreshBytes) bytes;",
            "ratio \(String(format: "%.2f", ratio))")
        XCTAssertLessThan(timing.refreshBytes, timing.firstBytes)
        XCTAssertLessThanOrEqual(ratio, 0.5, "first \(timing.first), refresh \(timing.refresh)")
    }
}
