import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// C-WIRE-09 at the session: a mutated answer either reaches the request, ends it with an
/// error and closes the connection (C-WIRE-02, C-CONN-10), or is dropped and the request
/// times out. No request is left waiting for ever.
final class SessionMutationTests: XCTestCase {
    private let settings = FuzzSettings.current(defaultIterations: 300)
    /// For bytes that are not a frame: they close the connection at once, and the timeout
    /// must not get there first on a loaded machine.
    private let generousTimeout = Duration.seconds(2)
    /// For a frame that decodes: it is answered, or dropped and the request times out, and
    /// either ending is right.
    private let shortTimeout = Duration.milliseconds(200)

    /// A session over `channel` that has shaken hands with the fixtures' server.
    private func readySession(
        over channel: GatedChannel, timeout: Duration
    ) async throws -> Session {
        let session = Session(channel: channel, client: Harness.client, requestTimeout: timeout)
        let handshake = Task { try await session.handshake() }
        await channel.deliver(
            FrameCodec.encodeForStream(try Harness.fixture("handshake", "02-s2c-hello.bin")))
        guard case .ready = try await handshake.value else {
            XCTFail("the fixtures' handshake did not succeed")
            throw CancellationError()
        }
        return session
    }

    /// About 40 of the payload's mutations, spread over the kinds and the offsets.
    private func sample(of payload: Data) -> [Mutation] {
        let all = Mutation.all(of: payload, randomCount: settings.iterations, seed: settings.seed)
        let step = max(1, all.count / 40)
        return stride(from: 0, to: all.count, by: step).map { all[$0] }
    }

    /// Delivers each mutation of the answer to a request on a fresh session and checks how
    /// the request ends.
    private func check(
        answer payload: Data, _ name: String,
        request: @escaping @Sendable (Session) async throws -> Void
    ) async throws {
        for mutation in sample(of: payload) {
            let mutated = mutation.applied(to: payload)
            let decodes = (try? FrameCodec.decode(mutated)) != nil
            let channel = GatedChannel()
            let session = try await readySession(
                over: channel, timeout: decodes ? shortTimeout : generousTimeout)
            let outcome = Outcome()
            let asked = Task {
                do {
                    try await request(session)
                    await outcome.end(.answered)
                } catch {
                    let reason = error as? RequestError ?? .protocolViolation("\(error)")
                    await outcome.end(.failed(reason))
                }
            }
            var length = UInt32(mutated.count).littleEndian
            await channel.deliver(Data(bytes: &length, count: 4) + mutated)

            // Bounded: the timeout ends a request whose answer was dropped.
            let ended = await Harness.eventually(within: .seconds(3)) {
                await outcome.ending != nil
            }
            asked.cancel()
            XCTAssertTrue(ended, "\(name), \(mutation): the request never ended")
            let ending = await outcome.ending
            if !decodes {
                // Bytes that are not a frame end the connection.
                XCTAssertEqual(ending, .failed(.disconnected), "\(name), \(mutation)")
                let closed = await Harness.eventually { await channel.closeCount >= 1 }
                XCTAssertTrue(closed, "\(name), \(mutation): the connection stayed open")
            }
            await session.close()
        }
    }

    func test_C_WIRE_09_aSessionClosesOnAFrameItCannotRead() async throws {
        try await check(
            answer: try Fixtures.data(scenario: "hierarchy", file: "02-s2c-hierarchy.bin"),
            "hierarchy"
        ) { session in
            _ = try await session.hierarchy()
        }
    }

    func test_C_WIRE_09_aSessionLeavesNoRequestPendingAfterMutatedFrames() async throws {
        guard case .getLayerDetails(let request) = try Harness.fixture(
            "layer-details", "01-c2s-get-layer-details.bin"
        ).body else {
            XCTFail("not a GetLayerDetails")
            return
        }
        try await check(
            answer: try Fixtures.data(scenario: "layer-details", file: "02-s2c-chunk-0.bin"),
            "chunk"
        ) { session in
            for try await _ in await session.layerDetails(request).chunks {}
        }
    }
}

/// How a request ended, once it has.
private actor Outcome {
    private(set) var ending: Ending?

    func end(_ ending: Ending) {
        self.ending = ending
    }
}

private enum Ending: Equatable, Sendable {
    case answered, failed(RequestError)
}
