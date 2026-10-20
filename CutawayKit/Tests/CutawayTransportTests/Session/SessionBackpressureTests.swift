import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayTransport

/// C-CONN-12: while a reader has too much left to take, the session reads no more from the
/// connection, so that the server's sending stops at the full TCP window.
final class SessionBackpressureTests: XCTestCase {
    private static let mebibyte = 1 << 20

    /// A session over `channel` that has shaken hands with the fixtures' server.
    private func readySession(
        over channel: MeteredChannel, limit: ReadLimit = .standard
    ) async throws -> Session {
        await channel.feed(
            FrameCodec.encodeForStream(try Harness.fixture("handshake", "02-s2c-hello.bin")))
        let session = Session(
            channel: channel, client: Harness.client, clock: ContinuousSessionClock(),
            readLimit: limit)
        guard case .ready = try await session.handshake() else {
            XCTFail("the fixtures' handshake did not succeed")
            throw CancellationError()
        }
        return session
    }

    private static let request = GetLayerDetails(
        requests: [LayerDetailRequest(
            layerID: 1, wantSolo: true, wantGroup: false, wantAttributes: false)],
        maxTextureDimension: 0)

    /// Lines up `count` chunks of `imageBytes` each for request `id`, then its end.
    private func feedChunks(
        _ count: Int, of imageBytes: Int, for id: UInt32, to channel: MeteredChannel,
        ending status: StreamStatus = .completed
    ) async {
        for index in 0..<count {
            await channel.feed {
                FrameCodec.encodeForStream(.bulkyChunk(
                    requestID: id, sequence: UInt32(index), layerID: UInt64(index + 1),
                    imageBytes: imageBytes))
            }
        }
        await channel.feed(FrameCodec.encodeForStream(Frame(
            requestID: id,
            body: .streamEnd(StreamEnd(status: status, chunkCount: UInt32(count), error: nil)))))
    }

    /// The length of one chunk's frame, length prefix included.
    private static func frameLength(imageBytes: Int) -> Int {
        FrameCodec.encodeForStream(
            .bulkyChunk(requestID: 1, sequence: 0, layerID: 1, imageBytes: imageBytes)).count
    }

    /// Waits until the session has stopped reading and the count of bytes it read holds still.
    private func settled(_ session: Session, _ channel: MeteredChannel) async -> Int {
        let paused = await Harness.eventually(within: .seconds(5)) { await session.isReadingPaused }
        XCTAssertTrue(paused, "the reading never paused")
        let before = await channel.deliveredByteCount
        try? await Task.sleep(for: .milliseconds(100))
        let after = await channel.deliveredByteCount
        XCTAssertEqual(before, after, "the session went on reading")
        return after
    }

    func test_C_CONN_12_aStreamNobodyTakesFromStopsTheReading() async throws {
        let channel = MeteredChannel()
        let session = try await readySession(over: channel)
        let start = await channel.deliveredByteCount
        let stream = await session.layerDetails(Self.request)
        await feedChunks(64, of: 16 * Self.mebibyte, for: 1, to: channel)

        let read = await settled(session, channel) - start
        let frame = Self.frameLength(imageBytes: 16 * Self.mebibyte)
        // Two chunks wait for the reader; at most part of one 64 KiB piece more was read.
        XCTAssertGreaterThanOrEqual(read, 2 * frame)
        XCTAssertLessThanOrEqual(read, 2 * frame + MeteredChannel.pieceLength)
        // Within the requirement: the limit, one frame and one read.
        XCTAssertLessThanOrEqual(
            read, ReadLimit.standard.bytes + frame + MeteredChannel.pieceLength)
        let receiving = await channel.isReceiving
        XCTAssertFalse(receiving, "a receive waits although the reader is behind")
        let untaken = await session.untakenChunkCount
        XCTAssertEqual(untaken, 2)
        withExtendedLifetime(stream) {}
        await session.close()
    }

    func test_C_CONN_12_takingResumesTheReadingAndEveryChunkArrivesInOrder() async throws {
        let channel = MeteredChannel()
        let session = try await readySession(over: channel)
        let stream = await session.layerDetails(Self.request)
        await feedChunks(64, of: 16 * Self.mebibyte, for: 1, to: channel)
        _ = await settled(session, channel)

        var layers: [UInt64] = []
        for try await details in stream.chunks {
            layers += details.map(\.layerID)
        }
        XCTAssertEqual(layers, Array(1...64), "every chunk, in order, and the end counted them")
        // The session hears of the last chunk taken a moment after the reader took it.
        let allTaken = await Harness.eventually { await session.untakenChunkCount == 0 }
        XCTAssertTrue(allTaken, "the session still counts chunks that were taken")
        await session.close()
    }

    func test_C_CONN_12_theByteLimitStopsTheReadingBeforeTheChunkLimit() async throws {
        let channel = MeteredChannel()
        let limit = ReadLimit(chunks: 100, bytes: Self.mebibyte)
        let session = try await readySession(over: channel, limit: limit)
        let start = await channel.deliveredByteCount
        let stream = await session.layerDetails(Self.request)
        await feedChunks(10, of: 600 << 10, for: 1, to: channel)

        let read = await settled(session, channel) - start
        let frame = Self.frameLength(imageBytes: 600 << 10)
        let untaken = await session.untakenChunkCount
        XCTAssertEqual(untaken, 2, "the second chunk took the bytes over a mebibyte")
        XCTAssertLessThanOrEqual(read, limit.bytes + frame + MeteredChannel.pieceLength)
        withExtendedLifetime(stream) {}
        await session.close()
    }

    func test_C_CONN_12_anAbandonedStreamIsReadToTheEndAndDropped() async throws {
        try XCTSkipIf(TestRunner.isCI, "it feeds 64 MiB against a deadline, which a loaded runner has missed")
        let channel = MeteredChannel()
        let session = try await readySession(over: channel)
        do {
            // Fed once the request is out: chunks of a request not yet sent are dropped.
            let stream = await session.layerDetails(Self.request)
            await feedChunks(64, of: Self.mebibyte, for: 1, to: channel, ending: .cancelled)
            for try await _ in stream.chunks { break }
        }
        // The stream is gone: a Cancel goes out (request 2), the rest is read and dropped.
        let cancelled = await Harness.eventually {
            await channel.sentFrames().contains {
                if case .cancel(let cancel) = $0.body { return cancel.targetRequestID == 1 }
                return false
            }
        }
        XCTAssertTrue(cancelled, "no Cancel went out")
        let drained = await Harness.eventually(within: .seconds(5)) { await channel.isReceiving }
        XCTAssertTrue(drained, "the rest of the abandoned stream was not read")
        let untaken = await session.untakenChunkCount
        XCTAssertEqual(untaken, 0)

        // A request after it is answered (request 3).
        async let hierarchy = session.hierarchy()
        var answer = try Harness.fixture("hierarchy", "02-s2c-hierarchy.bin")
        answer.requestID = 3
        await channel.feed(FrameCodec.encodeForStream(answer))
        let nodes = try await hierarchy.nodes.count
        XCTAssertEqual(nodes, 14)

        // The same layers again (request 4): all of it, nothing left over from before.
        let again = await session.layerDetails(Self.request)
        await feedChunks(3, of: 1024, for: 4, to: channel)
        var layers: [UInt64] = []
        for try await details in again.chunks { layers += details.map(\.layerID) }
        XCTAssertEqual(layers, [1, 2, 3])
        await session.close()
    }

    func test_C_CONN_12_aFinishedStreamDroppedUnreadIsForgotten() async throws {
        let channel = MeteredChannel()
        let session = try await readySession(
            over: channel, limit: ReadLimit(chunks: 3, bytes: 1 << 30))
        do {
            let stream = await session.layerDetails(Self.request)
            await feedChunks(2, of: 1024, for: 1, to: channel)
            // The end is read: the session waits for more.
            let ended = await Harness.eventually { await channel.isReceiving }
            XCTAssertTrue(ended)
            let untaken = await session.untakenChunkCount
            XCTAssertEqual(untaken, 2)
            withExtendedLifetime(stream) {}
        }
        // The stream of the standard library said its end when it finished; only the token
        // says that the reader let go.
        let forgotten = await Harness.eventually { await session.untakenChunkCount == 0 }
        XCTAssertTrue(forgotten)
        await session.close()
    }

    func test_C_CONN_07_aPausedSessionThatIsReleasedEndsItsStreams() async throws {
        let channel = MeteredChannel()
        var session: Session? = try await readySession(over: channel)
        weak let released = session
        let stream = await session!.layerDetails(Self.request)
        await feedChunks(8, of: Self.mebibyte, for: 1, to: channel)
        let paused = await Harness.eventually { await released?.isReadingPaused ?? false }
        XCTAssertTrue(paused)

        // The reading task waits on its gate, not inside the session: nothing holds it.
        session = nil
        let gone = await Harness.eventually { released == nil }
        XCTAssertTrue(gone, "the paused session was kept alive")
        var ending: RequestError?
        do {
            for try await _ in stream.chunks {}
        } catch {
            ending = error as? RequestError
        }
        XCTAssertEqual(ending, .disconnected)
        // The channel records its close on a task of its own, after the deinit asked for it.
        let closed = await Harness.eventually { await channel.closeCount >= 1 }
        XCTAssertTrue(closed, "the channel was not closed")
    }

    func test_C_CONN_12_aCancelGoesOutWhileTheReadingIsPaused() async throws {
        let channel = MeteredChannel()
        let session = try await readySession(over: channel)
        let stream = await session.layerDetails(Self.request)
        await feedChunks(8, of: Self.mebibyte, for: 1, to: channel, ending: .cancelled)
        _ = await settled(session, channel)

        await stream.cancel()
        // The Cancel leaves through the writing task, which the paused reading does not hold.
        let sent = await Harness.eventually {
            await channel.sentFrames().contains {
                if case .cancel(let cancel) = $0.body { return cancel.targetRequestID == 1 }
                return false
            }
        }
        XCTAssertTrue(sent, "the Cancel waited for the reading")
        // What the stream left untaken holds nothing up any more.
        let resumed = await Harness.eventually { await !session.isReadingPaused }
        XCTAssertTrue(resumed)
        var ending: RequestError?
        do {
            for try await _ in stream.chunks {}
        } catch {
            ending = error as? RequestError
        }
        XCTAssertEqual(ending, .cancelled)
        await session.close()
    }

    func test_C_CONN_12_anAppThatLeavesWhileTheReadingIsPausedEndsAsNotActive() async throws {
        let channel = MeteredChannel()
        let session = try await readySession(over: channel)
        let events = Task { () -> [SessionEvent] in
            var seen: [SessionEvent] = []
            for await event in session.events {
                seen.append(event)
                if case .appStateChanged = event { break }
            }
            return seen
        }
        let stream = await session.layerDetails(Self.request)
        for index in 0..<4 {
            await channel.feed(FrameCodec.encodeForStream(.bulkyChunk(
                requestID: 1, sequence: UInt32(index), layerID: UInt64(index + 1),
                imageBytes: 1024)))
        }
        await channel.feed(FrameCodec.encodeForStream(Frame(
            requestID: 0, body: .appStateChanged(.background))))
        await channel.feed(FrameCodec.encodeForStream(Frame(
            requestID: 1,
            body: .streamEnd(StreamEnd(
                status: .failed, chunkCount: 4,
                error: ServerError(code: .appNotActive, message: nil))))))
        let paused = await Harness.eventually { await session.isReadingPaused }
        XCTAssertTrue(paused)

        // Taken in order: the chunks, then the stream ends as the app not being active, and
        // the change of state comes.
        var layers: [UInt64] = []
        var ending: RequestError?
        do {
            for try await details in stream.chunks { layers += details.map(\.layerID) }
        } catch {
            ending = error as? RequestError
        }
        XCTAssertEqual(layers, [1, 2, 3, 4])
        XCTAssertEqual(ending, .appNotActive(message: nil))
        let seen = await events.value
        XCTAssertEqual(seen.last, .appStateChanged(.background))
        await session.close()
    }

    func test_C_CONN_12_theServerCannotWriteEverythingWhileNobodyTakes() async throws {
        let count = 64
        let imageBytes = 16 * Self.mebibyte
        var steps = try MockScript.fixtures("handshake").steps
        steps.append(.expect(.getLayerDetails, as: 7))
        steps.append(.sendMany(count: count) { index in
            .bulkyChunk(
                requestID: 7, sequence: UInt32(index), layerID: UInt64(index + 1),
                imageBytes: imageBytes)
        })
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.session(for: server)
        _ = try await session.handshake()
        let stream = await session.layerDetails(Self.request)

        // Let the server write what it can.
        var written = 0
        for _ in 0..<50 {
            try await Task.sleep(for: .milliseconds(100))
            let now = await server.writtenByteCount
            if now == written, now > 0 { break }
            written = now
        }
        let total = count * Self.frameLength(imageBytes: imageBytes)
        XCTAssertLessThan(written, total / 2, "\(written) of \(total) bytes were written")
        let paused = await session.isReadingPaused
        XCTAssertTrue(paused)
        withExtendedLifetime(stream) {}
        await session.close()
        await server.stop()
    }
}
