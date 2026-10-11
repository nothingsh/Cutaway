import CutawayTestSupport
import CutawayWire
import XCTest

import CutawayTransport

/// A session says how many requests wait for their answer and how many streams are not over,
/// so that repeated use can be checked for leftovers (C-SCALE-02).
final class SessionCountTests: XCTestCase {
    /// The handshake, then the steps of `scenario` with a hold at `gate` before the server's
    /// frame number `held` (counting the scenario's server frames from 0).
    private func script(
        _ scenario: String, holdingAt gate: MockGate, beforeServerFrame held: Int
    ) throws -> MockScript {
        var steps = try Harness.handshakeSteps()
        var serverFrames = 0
        for step in try MockScript.fixtures(scenario).steps {
            if case .send = step {
                if serverFrames == held { steps.append(.hold(gate)) }
                serverFrames += 1
            }
            steps.append(step)
        }
        return MockScript(steps: steps)
    }

    private func request(_ scenario: String) throws -> GetLayerDetails {
        guard case .getLayerDetails(let request) =
            try Harness.fixture(scenario, "01-c2s-get-layer-details.bin").body
        else { throw RequestError.protocolViolation("the fixture is not a GetLayerDetails") }
        return request
    }

    func test_C_SCALE_02_aSessionCountsItsPendingRequests() async throws {
        let gate = MockGate()
        let server = try await MockServer.start(
            script: try script("hierarchy", holdingAt: gate, beforeServerFrame: 0))
        let session = try await Harness.readySession(for: server)
        let idle = await session.pendingRequestCount
        XCTAssertEqual(idle, 0)

        let answer = Task { try await session.hierarchy() }
        let waiting = await Harness.eventually { await session.pendingRequestCount == 1 }
        XCTAssertTrue(waiting, "the request is pending")
        let streams = await session.openStreamCount
        XCTAssertEqual(streams, 0)

        await gate.open()
        _ = try await answer.value
        let answered = await session.pendingRequestCount
        XCTAssertEqual(answered, 0)

        await session.close()
        await server.stop()
    }

    func test_C_SCALE_02_aRequestThatTimesOutOrIsClosedOnIsNoLongerPending() async throws {
        for closes in [false, true] {
            let gate = MockGate()
            let server = try await MockServer.start(
                script: try script("hierarchy", holdingAt: gate, beforeServerFrame: 0))
            let session = try await Harness.readySession(
                for: server, requestTimeout: .milliseconds(400))
            let answer = Task { try await session.hierarchy() }
            let waiting = await Harness.eventually { await session.pendingRequestCount == 1 }
            XCTAssertTrue(waiting)
            if closes { await session.close() }
            do {
                _ = try await answer.value
                XCTFail("the request was answered")
            } catch {}
            let pending = await session.pendingRequestCount
            XCTAssertEqual(pending, 0, closes ? "closed" : "timed out")
            await session.close()
            await gate.open()
            await server.stop()
        }
    }

    func test_C_SCALE_02_aSessionCountsItsOpenStreams() async throws {
        // Held between the two chunks.
        let gate = MockGate()
        let server = try await MockServer.start(
            script: try script("layer-details", holdingAt: gate, beforeServerFrame: 1))
        let session = try await Harness.readySession(for: server)
        let stream = await session.layerDetails(try request("layer-details"))
        var chunks = stream.chunks.makeAsyncIterator()
        _ = try await chunks.next()
        let open = await session.openStreamCount
        XCTAssertEqual(open, 1)
        let requests = await session.pendingRequestCount
        XCTAssertEqual(requests, 0, "a stream is not a pending request")

        await gate.open()
        while try await chunks.next() != nil {}
        let ended = await session.openStreamCount
        XCTAssertEqual(ended, 0)

        await session.close()
        await server.stop()
    }

    func test_C_SCALE_02_aCancelledOrCutOffStreamIsNoLongerOpen() async throws {
        // Cancelled after the first chunk; the server confirms.
        do {
            let server = try await MockServer.start(
                script: try .fixtures("handshake", "layer-details-cancelled"))
            let session = try await Harness.readySession(for: server)
            let stream = await session.layerDetails(try request("layer-details-cancelled"))
            var chunks = stream.chunks.makeAsyncIterator()
            _ = try await chunks.next()
            await stream.cancel()
            let closed = await Harness.eventually { await session.openStreamCount == 0 }
            XCTAssertTrue(closed, "cancelled")
            await session.close()
            await server.stop()
        }
        // The connection goes in the middle of the stream.
        do {
            let gate = MockGate()
            var script = try script("layer-details", holdingAt: gate, beforeServerFrame: 1)
            script.steps.insert(.close, at: script.steps.count - 1)
            let server = try await MockServer.start(script: script)
            let session = try await Harness.readySession(for: server)
            let stream = await session.layerDetails(try request("layer-details"))
            var chunks = stream.chunks.makeAsyncIterator()
            _ = try await chunks.next()
            await gate.open()
            do {
                while try await chunks.next() != nil {}
            } catch {}
            let closed = await Harness.eventually { await session.openStreamCount == 0 }
            XCTAssertTrue(closed, "cut off")
            await session.close()
            await server.stop()
        }
    }
}
