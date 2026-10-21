import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-SCALE-04: two batches of screenshots under way. A change cancels both before it goes out
/// (C-DET-06), and when one fails the other is cancelled too. The fixtures' seven
/// layers are asked for four to a batch, so that there are two.
final class TwoBatchesTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.4.0")

    private static func session(to server: MockServer) async throws -> Session {
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client, requestTimeout: .seconds(10))
        _ = try await session.handshake()
        return session
    }

    @MainActor
    private static func model(_ session: Session) async -> InspectionStore {
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.screenshotBatchSize = 4
        model.rowsWait = .zero
        model.enter()
        let ready = await Wait.until {
            await MainActor.run { model.loadState == .loaded && model.attributes.canEdit }
        }
        XCTAssertTrue(ready)
        return model
    }

    private static func end(_ requestID: UInt32, _ status: StreamStatus, error: ServerError? = nil)
        -> MockScript.Step
    {
        .send(Frame(requestID: requestID, body: .streamEnd(StreamEnd(
            status: status, chunkCount: 0, error: error))))
    }

    private static func kinds(_ server: MockServer) async -> [MessageKind] {
        await server.receivedFrames.map { MessageKind($0.body) }
    }

    /// The layers each `GetLayerDetails` asked for, in order.
    private static func asked(_ server: MockServer) async -> [[UInt64]] {
        await InspectionStoreDetailsTests.detailRequests(server).map { $0.requests.map(\.layerID) }
    }

    @MainActor
    func test_C_SCALE_04_twoBatchesGoOutAtOnceAndAskForDifferentLayers() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += [.expect(.getLayerDetails, as: 50), .expect(.getLayerDetails, as: 52), .hold(gate)]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session)
        let both = await Wait.until { await Self.asked(server).count == 2 }
        XCTAssertTrue(both, "the second goes out before the first is answered")
        let asked = await Self.asked(server)
        XCTAssertEqual(asked, [[1, 2, 3, 4], [6, 7, 8]])
        try await Task.sleep(for: .milliseconds(100))
        let still = await Self.asked(server).count
        XCTAssertEqual(still, 2, "no third while two are under way")
        withExtendedLifetime(model) {}
        await gate.open()
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_06_bothBatchesAreCancelledBeforeAChangeGoesOut() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += [
            .expect(.getLayerDetails, as: 50),
            .expect(.getLayerDetails, as: 52),
            .hold(gate),
            .expect(.cancel, as: 51),
            .expect(.cancel, as: 53),
            Self.end(50, .cancelled),
            Self.end(52, .cancelled),
            .expect(.setAttribute, as: 30),
            .send(Frame(requestID: 30, body: .setAttributeResult(SetAttributeResult(
                layerID: 3, attributeGroups: try Fixtures.setAttributeResults()[0].attributeGroups)))),
            .expect(.getSubtree, as: 31),
            .send(Frame(requestID: 31, body: .hierarchy(try Fixtures.hierarchy()))),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session)
        let both = await Wait.until { await Self.asked(server).count == 2 }
        XCTAssertTrue(both)

        model.attributes.setRegardlessOfSelection(
            AttributeKey(layerID: 3, attributeID: "label.text"), to: .string("Welcome back"), continuous: false)
        await gate.open()
        let changed = await Wait.until { await Self.kinds(server).contains(.getSubtree) }
        XCTAssertTrue(changed)
        let kinds = await Self.kinds(server)
        XCTAssertEqual(
            Array(kinds.prefix(8)),
            [.hello, .getHierarchy, .getLayerDetails, .getLayerDetails, .cancel, .cancel, .setAttribute, .getSubtree],
            "both Cancels go out before the change")
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_SCALE_04_whenOneBatchFailsTheOtherIsCancelled() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += [
            .expect(.getLayerDetails, as: 50),
            .expect(.getLayerDetails, as: 52),
            Self.end(50, .failed, error: ServerError(code: .internalError, message: "capture failed")),
            .expect(.cancel, as: 53),
            .hold(gate),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session)
        let cancelled = await Wait.until { await Self.kinds(server).contains(.cancel) }
        XCTAssertTrue(cancelled, "the second batch is cancelled")
        let cancels = await server.receivedFrames.compactMap { frame -> UInt32? in
            guard case .cancel(let cancel) = frame.body else { return nil }
            return cancel.targetRequestID
        }
        let ids = await server.receivedFrames.compactMap { frame -> UInt32? in
            guard case .getLayerDetails = frame.body else { return nil }
            return frame.requestID
        }
        XCTAssertEqual(cancels, [ids[1]], "only the second: the first had ended")
        try await Task.sleep(for: .milliseconds(100))
        let asked = await Self.asked(server).count
        XCTAssertEqual(asked, 2, "asking stopped on the failure, as with one batch")
        withExtendedLifetime(model) {}
        await gate.open()
        await session.close()
        await server.stop()
    }
}
