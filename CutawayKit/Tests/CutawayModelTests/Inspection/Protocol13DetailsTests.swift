import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-WIRE-13, the part of protocol 1.3's `dev.1` the model meets: nothing held, no digests
/// given, and an unchanged image that stands for nothing held is not received (P-IMG-06).
final class Protocol13DetailsTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    private static func server(_ responder: MockResponder) async throws -> MockServer {
        let steps = try MockScript.fixtures("handshake").steps
        return try await MockServer.start(script: MockScript(steps: steps + [.respond(responder)]))
    }

    private static func session(to server: MockServer) async throws -> Session {
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: client, requestTimeout: .seconds(5))
        _ = try await session.handshake()
        return session
    }

    private static func detailRequests(_ server: MockServer) async -> [LayerDetailRequest] {
        await server.receivedFrames.flatMap { frame -> [LayerDetailRequest] in
            guard case .getLayerDetails(let request) = frame.body else { return [] }
            return request.requests
        }
    }

    @MainActor
    private static func roundDone(_ model: InspectionStore) async -> Bool {
        await Wait.until {
            await MainActor.run {
                model.loadState == .loaded && model.detailProgress.total > 0
                    && model.detailProgress.completed == model.detailProgress.total
            }
        }
    }

    @MainActor
    func test_C_WIRE_13_anUnchangedImageIsNotReceivedAndIsAskedForAgain() async throws {
        var responder = try MockResponder.demo()
        // Layer 3's group, which the fully expanded tree asks for.
        responder.details[3]?.group = .unchanged(digest: Data(repeating: 1, count: 16))
        let server = try await Self.server(responder)
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .zero
        model.enter()

        let first = await Self.roundDone(model)
        XCTAssertTrue(first, "the round ends; the image counts as failed this round")
        XCTAssertNil(model.images[3]?.group)
        XCTAssertNotNil(model.images[4]?.solo, "the other layers' images are taken")
        XCTAssertNil(model.notice)
        let asked = await Self.detailRequests(server).filter { $0.layerID == 3 && $0.wantGroup }
        XCTAssertEqual(asked.count, 1)

        model.refresh()
        let again = await Wait.until {
            await Self.detailRequests(server).filter { $0.layerID == 3 && $0.wantGroup }.count == 2
        }
        XCTAssertTrue(again, "the next round asks for it again")
        let second = await Self.roundDone(model)
        XCTAssertTrue(second)
        XCTAssertNil(model.notice)
        XCTAssertEqual(model.loadState, .loaded, "the connection stays")

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_WIRE_13_theFirstRequestsCarryNoDigests() async throws {
        let server = try await Self.server(try MockResponder.demo())
        let session = try await Self.session(to: server)
        let negotiated = await session.negotiatedVersion
        XCTAssertEqual(negotiated, Version(major: 1, minor: 3))
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .zero
        model.enter()
        let first = await Self.roundDone(model)
        XCTAssertTrue(first)
        // The images that came carry their digests; the requests after a refresh give them
        // (C-DET-12).
        XCTAssertNotNil(model.images[4]?.solo?.image.digest)
        let requests = await Self.detailRequests(server)
        XCTAssertFalse(requests.isEmpty)
        XCTAssertTrue(requests.allSatisfy { $0.knownSoloDigest == nil && $0.knownGroupDigest == nil })

        await session.close()
        await server.stop()
    }
}
