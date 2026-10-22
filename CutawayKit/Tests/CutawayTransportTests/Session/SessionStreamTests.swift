import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// C-CONN-05 and C-CONN-06: streamed responses and cancelling them.
final class SessionStreamTests: XCTestCase {
    /// The request of a fixture scenario's first frame.
    private func request(_ scenario: String) throws -> GetLayerDetails {
        guard case .getLayerDetails(let request) =
            try Harness.fixture(scenario, "01-c2s-get-layer-details.bin").body
        else { throw RequestError.protocolViolation("the fixture is not a GetLayerDetails") }
        return request
    }

    /// Collects a stream. Returns the layer IDs of each chunk and how the stream ended.
    private func collect(
        _ stream: LayerDetailsStream, afterEachChunk: (Int) async -> Void = { _ in }
    ) async -> (chunks: [[UInt64]], error: RequestError?, other: (any Error)?) {
        var chunks: [[UInt64]] = []
        do {
            for try await details in stream.chunks {
                chunks.append(details.map(\.layerID))
                await afterEachChunk(chunks.count)
            }
            return (chunks, nil, nil)
        } catch let error as RequestError {
            return (chunks, error, nil)
        } catch {
            return (chunks, nil, error)
        }
    }

    private func chunk(_ scenario: String, _ file: String) throws -> Frame {
        try Harness.fixture(scenario, file)
    }

    // MARK: - C-WIRE-06

    func test_C_WIRE_06_sessionReceivesConstraintsFromMockServer() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "layout-constraints"))
        let session = try await Harness.readySession(for: server)

        var details: [LayerDetail] = []
        for try await chunk in await session.layerDetails(try request("layout-constraints")).chunks {
            details += chunk
        }
        XCTAssertEqual(details.map(\.layerID), [3, 4, 9, 8, 99])
        XCTAssertEqual(details.map(\.constraints.count), [4, 4, 4, 0, 0])
        XCTAssertEqual(details[0].constraints.map(\.id), [1, 2, 3, 4])
        XCTAssertEqual(details[0].constraints[3], details[1].constraints[0])
        XCTAssertEqual(details[4].status, .layerNotFound)

        let sent = await server.receivedFrames.last
        XCTAssertEqual(sent?.body, try Harness.fixture(
            "layout-constraints", "01-c2s-get-layer-details.bin").body)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    // MARK: - C-CONN-05

    func test_C_CONN_05_aCompletedStreamDeliversItsChunksInOrder() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "layer-details"))
        let session = try await Harness.readySession(for: server)

        let result = await collect(await session.layerDetails(try request("layer-details")))
        XCTAssertEqual(result.chunks, [[3], [4, 99, 6, 10, 13]])
        XCTAssertNil(result.error)
        XCTAssertNil(result.other)

        // The client sent exactly the fixture's request.
        let sent = await server.receivedFrames.last
        XCTAssertEqual(sent?.body, try Harness.fixture(
            "layer-details", "01-c2s-get-layer-details.bin").body)

        await session.close()
        await server.stop()
    }

    func test_C_CONN_05_aFailedStreamThrowsItsReason() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "layer-details-failed"))
        let session = try await Harness.readySession(for: server)

        let result = await collect(await session.layerDetails(try request("layer-details-failed")))
        XCTAssertEqual(result.chunks, [])
        // C-CONN-08: AppNotActive is told apart from an ordinary failure.
        XCTAssertEqual(
            result.error,
            .appNotActive(message: "the app left the active state during capture"))

        // The state change that caused it arrived as an event.
        let events = await Harness.events(2, from: session)
        XCTAssertEqual(events, [.appStateChanged(.active), .appStateChanged(.inactive)])

        await session.close()
        await server.stop()
    }

    func test_C_CONN_05_aSequenceGapIsAProtocolError() async throws {
        var steps = try Harness.handshakeSteps()
        steps += [
            .expect(.getLayerDetails, as: 3),
            // Sequence 1 arrives where 0 was due.
            .send(try chunk("layer-details", "03-s2c-chunk-1.bin")),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server)

        let result = await collect(await session.layerDetails(try request("layer-details")))
        XCTAssertEqual(result.chunks, [])
        guard case .protocolViolation = result.error else {
            XCTFail("ended with \(String(describing: result.error))")
            return
        }
        let events = await Harness.events(2, from: session)
        XCTAssertEqual(events.last, .closed)
        let left = await Harness.eventually { await server.clientCloseCount == 1 }
        XCTAssertTrue(left, "the client did not close the connection")
        // Keeps the session alive up to here: releasing it would close the connection too.
        withExtendedLifetime(session) {}
        await server.stop()
    }

    func test_C_CONN_05_aWrongChunkCountIsAProtocolError() async throws {
        var steps = try Harness.handshakeSteps()
        steps += [
            .expect(.getLayerDetails, as: 3),
            .send(try chunk("layer-details", "02-s2c-chunk-0.bin")),
            // Claims two chunks; one was sent.
            .send(try chunk("layer-details", "04-s2c-stream-end.bin")),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server)

        let result = await collect(await session.layerDetails(try request("layer-details")))
        XCTAssertEqual(result.chunks, [[3]])
        guard case .protocolViolation = result.error else {
            XCTFail("ended with \(String(describing: result.error))")
            return
        }
        let events = await Harness.events(2, from: session)
        XCTAssertEqual(events.last, .closed)
        let left = await Harness.eventually { await server.clientCloseCount == 1 }
        XCTAssertTrue(left, "the client did not close the connection")
        // Keeps the session alive up to here: releasing it would close the connection too.
        withExtendedLifetime(session) {}
        await server.stop()
    }

    func test_C_CONN_05_aStreamIsNotTimedOutWhileChunksKeepArriving() async throws {
        var steps = try Harness.handshakeSteps()
        steps += [
            .expect(.getLayerDetails, as: 3),
            .pause(.milliseconds(600)),
            .send(try chunk("layer-details", "02-s2c-chunk-0.bin")),
            .pause(.milliseconds(600)),
            .send(try chunk("layer-details", "03-s2c-chunk-1.bin")),
            .pause(.milliseconds(600)),
            .send(try chunk("layer-details", "04-s2c-stream-end.bin")),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        // 1.8 s in total, longer than the timeout, but never more than 600 ms without a frame.
        let session = try await Harness.readySession(for: server, requestTimeout: .milliseconds(1500))

        let result = await collect(await session.layerDetails(try request("layer-details")))
        XCTAssertEqual(result.chunks, [[3], [4, 99, 6, 10, 13]])
        XCTAssertNil(result.error)

        await session.close()
        await server.stop()
    }

    func test_C_CONN_05_aSilentStreamTimesOut() async throws {
        var steps = try Harness.handshakeSteps()
        steps += [
            .expect(.getLayerDetails, as: 3),
            .send(try chunk("layer-details", "02-s2c-chunk-0.bin")),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server, requestTimeout: .milliseconds(200))

        let result = await collect(await session.layerDetails(try request("layer-details")))
        XCTAssertEqual(result.chunks, [[3]])
        XCTAssertEqual(result.error, .timedOut)

        await session.close()
        await server.stop()
    }

    /// Reads `chunks` to the end, giving up after `limit`. The error it ended with; nil when
    /// it ended normally or the reader gave up.
    private func ending(
        of chunks: ChunkSequence<[LayerDetail]>, within limit: Duration = .seconds(2)
    ) async -> RequestError? {
        let reader = Task { () -> RequestError? in
            do {
                for try await _ in chunks {}
                return nil
            } catch {
                return error as? RequestError ?? .protocolViolation("\(error)")
            }
        }
        let timer = Task {
            try await Task.sleep(for: limit)
            reader.cancel()
        }
        defer { timer.cancel() }
        return await reader.value
    }

    func test_C_CONN_07_aStreamEndsWhenItsSessionIsReleased() async throws {
        var steps = try Harness.handshakeSteps()
        steps.append(.expect(.getLayerDetails, as: 3))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        var session: Session? = try await Harness.readySession(
            for: server, requestTimeout: .seconds(30))
        let stream = await session!.layerDetails(try request("layer-details"))
        let asked = await Harness.eventually { await server.receivedFrames.count == 2 }
        XCTAssertTrue(asked, "the request was not sent")

        // The handshake fixture's AppStateChanged has been handled: the read task holds the
        // session only while it handles a frame.
        let events = await Harness.events(1, from: session!)
        XCTAssertEqual(events, [.appStateChanged(.active)])
        weak let released = session
        session = nil
        XCTAssertNil(released, "the session was not released")

        let error = await ending(of: stream.chunks)
        XCTAssertEqual(error, .disconnected)
        await server.stop()
    }

    func test_C_CONN_07_aStreamBeingCancelledEndsWhenItsSessionIsReleased() async throws {
        var steps = try Harness.handshakeSteps()
        steps += [.expect(.getLayerDetails, as: 3), .expect(.cancel, as: 4)]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        var session: Session? = try await Harness.readySession(
            for: server, requestTimeout: .seconds(30))
        let stream = await session!.layerDetails(try request("layer-details"))
        await stream.cancel()
        let cancelled = await Harness.eventually { await server.receivedFrames.count == 3 }
        XCTAssertTrue(cancelled, "the Cancel was not sent")

        // The handshake fixture's AppStateChanged has been handled: the read task holds the
        // session only while it handles a frame.
        let events = await Harness.events(1, from: session!)
        XCTAssertEqual(events, [.appStateChanged(.active)])
        weak let released = session
        session = nil
        XCTAssertNil(released, "the session was not released")

        let error = await ending(of: stream.chunks)
        XCTAssertEqual(error, .disconnected)
        await server.stop()
    }

    func test_C_CONN_07_aDisconnectEndsAStreamInFlight() async throws {
        var steps = try Harness.handshakeSteps()
        steps += [
            .expect(.getLayerDetails, as: 3),
            .send(try chunk("layer-details", "02-s2c-chunk-0.bin")),
            .close,
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server)

        let result = await collect(await session.layerDetails(try request("layer-details")))
        XCTAssertEqual(result.chunks, [[3]])
        XCTAssertEqual(result.error, .disconnected)
        await server.stop()
    }

    func test_C_CONN_07_aStreamRequestedAfterTheConnectionEndedFailsAtOnce() async throws {
        var steps = try Harness.handshakeSteps()
        steps.append(.close)
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server)
        _ = await Harness.events(2, from: session)

        let result = await collect(await session.layerDetails(try request("layer-details")))
        XCTAssertEqual(result.error, .disconnected)
        await server.stop()
    }

    // MARK: - C-CONN-06

    func test_C_CONN_06_cancelSendsCancelAndTheStreamEndsAsCancelled() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "layer-details-cancelled"))
        let session = try await Harness.readySession(for: server)

        let stream = await session.layerDetails(try request("layer-details-cancelled"))
        let result = await collect(stream) { count in
            if count == 1 { await stream.cancel() }
        }
        XCTAssertEqual(result.chunks, [[2]])
        XCTAssertEqual(result.error, .cancelled)

        // Hello (0), GetLayerDetails (1), Cancel (2) pointing at request 1 (C-CONN-04).
        let frames = await server.receivedFrames
        XCTAssertEqual(frames.map(\.requestID), [0, 1, 2])
        XCTAssertEqual(frames.last?.body, .cancel(Cancel(targetRequestID: 1)))
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    func test_C_CONN_06_chunksThatArriveAfterCancelAreDropped() async throws {
        var steps = try Harness.handshakeSteps()
        var end = try chunk("layer-details-cancelled", "04-s2c-stream-end.bin")
        end.requestID = 3
        end.body = .streamEnd(StreamEnd(status: .cancelled, chunkCount: 2, error: nil))
        steps += [
            .expect(.getLayerDetails, as: 3),
            .send(try chunk("layer-details", "02-s2c-chunk-0.bin")),
            .expect(.cancel, as: 4),
            // Already on its way when the Cancel arrived.
            .send(try chunk("layer-details", "03-s2c-chunk-1.bin")),
            .send(end),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server)

        let stream = await session.layerDetails(try request("layer-details"))
        let result = await collect(stream) { count in
            if count == 1 { await stream.cancel() }
        }
        XCTAssertEqual(result.chunks, [[3]], "the chunk after the cancel must not be delivered")
        XCTAssertEqual(result.error, .cancelled)

        // The connection is still good.
        let events = await Harness.events(2, from: session, within: .milliseconds(200))
        XCTAssertEqual(events, [.appStateChanged(.active)])

        await session.close()
        await server.stop()
    }

    func test_C_CONN_06_aStreamThatCompletesAfterCancelIsStillReportedCancelled() async throws {
        var steps = try Harness.handshakeSteps()
        steps += [
            .expect(.getLayerDetails, as: 3),
            .send(try chunk("layer-details", "02-s2c-chunk-0.bin")),
            .expect(.cancel, as: 4),
            // The server had already finished: it ignores the Cancel (P-REQ-04).
            .send(try chunk("layer-details", "03-s2c-chunk-1.bin")),
            .send(try chunk("layer-details", "04-s2c-stream-end.bin")),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server)

        let stream = await session.layerDetails(try request("layer-details"))
        let result = await collect(stream) { count in
            if count == 1 { await stream.cancel() }
        }
        XCTAssertEqual(result.chunks, [[3]])
        XCTAssertEqual(result.error, .cancelled)

        await session.close()
        await server.stop()
    }

    func test_C_CONN_06_cancellingTwiceSendsOneCancel() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "layer-details-cancelled"))
        let session = try await Harness.readySession(for: server)

        let stream = await session.layerDetails(try request("layer-details-cancelled"))
        let result = await collect(stream) { count in
            if count == 1 {
                await stream.cancel()
                await stream.cancel()
            }
        }
        XCTAssertEqual(result.error, .cancelled)
        let cancels = await server.receivedFrames.filter { MessageKind($0.body) == .cancel }
        XCTAssertEqual(cancels.count, 1)

        await session.close()
        await server.stop()
    }

    // MARK: - C-DET-02: a reader that stops cancels the stream

    func test_C_DET_02_aReaderThatIsCancelledCancelsTheStream() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "layer-details-cancelled"))
        let session = try await Harness.readySession(for: server)

        let stream = await session.layerDetails(try request("layer-details-cancelled"))
        let reader = Task {
            for try await _ in stream.chunks {}
        }
        let asked = await Harness.eventually { await server.receivedFrames.count == 2 }
        XCTAssertTrue(asked)
        reader.cancel()

        // Hello (0), GetLayerDetails (1), Cancel (2) pointing at request 1.
        let cancelled = await Harness.eventually {
            await server.receivedFrames.last?.body == .cancel(Cancel(targetRequestID: 1))
        }
        XCTAssertTrue(cancelled)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    func test_C_DET_02_aStreamThatEndsSendsNoCancel() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "layer-details"))
        let session = try await Harness.readySession(for: server)

        let result = await collect(await session.layerDetails(try request("layer-details")))
        XCTAssertNil(result.error)
        try await Task.sleep(for: .milliseconds(200))
        let kinds = await server.receivedFrames.map { MessageKind($0.body) }
        XCTAssertEqual(kinds, [.hello, .getLayerDetails])

        await session.close()
        await server.stop()
    }
}
