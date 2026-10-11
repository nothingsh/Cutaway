import CutawayTestSupport
import CutawayWire
import XCTest

@testable import CutawayTransport

/// C-CONN-13: a request times out after ten seconds without a byte from the server. The time
/// this side spends not reading does not count, nor the time the process did not run.
final class SessionSilenceTests: XCTestCase {
    private let step = Duration.milliseconds(500)

    /// How a request ended, once it has.
    private actor Outcome<Value: Sendable> {
        private(set) var result: Result<Value, RequestError>?

        func end(_ result: Result<Value, RequestError>) {
            self.result = result
        }

        var isOver: Bool { result != nil }
    }

    /// Runs `body` and keeps how it ended.
    private func track<Value: Sendable>(
        _ body: @escaping @Sendable () async throws -> Value
    ) -> Outcome<Value> {
        let outcome = Outcome<Value>()
        Task {
            do {
                await outcome.end(.success(try await body()))
            } catch {
                let reason = error as? RequestError ?? .protocolViolation("\(error)")
                await outcome.end(.failure(reason))
            }
        }
        return outcome
    }

    private func session(
        over channel: MeteredChannel, clock: ManualClock, limit: ReadLimit = .standard
    ) -> Session {
        Session(
            channel: channel, client: Harness.client, requestTimeout: .seconds(10), clock: clock,
            readLimit: limit)
    }

    private func readySession(
        over channel: MeteredChannel, clock: ManualClock
    ) async throws -> Session {
        await channel.feed(
            FrameCodec.encodeForStream(try Harness.fixture("handshake", "02-s2c-hello.bin")))
        let session = session(over: channel, clock: clock)
        guard case .ready = try await session.handshake() else {
            XCTFail("the fixtures' handshake did not succeed")
            throw CancellationError()
        }
        return session
    }

    /// Whether the outcome is still open once the watchdog has looked at the last step: it
    /// going back to sleep says it has.
    private func isOpen(_ outcome: Outcome<some Any>, on clock: ManualClock) async -> Bool {
        let looked = await clock.waitForSleepers()
        XCTAssertTrue(looked, "the watchdog did not go back to sleep")
        return await !outcome.isOver
    }

    /// Moves the clock on in the watchdog's steps, each of them seen by it.
    private func pass(_ duration: Duration, on clock: ManualClock) async {
        let seen = await clock.advance(by: duration, inStepsOf: step)
        XCTAssertTrue(seen, "a step went by with nobody watching")
    }

    /// Waits until the session sent a frame of this kind: silence counts from there.
    private func sent(_ kind: MessageKind, on channel: MeteredChannel) async {
        let went = await Harness.eventually {
            await channel.sentFrames().contains { MessageKind($0.body) == kind }
        }
        XCTAssertTrue(went, "no \(kind) was sent")
    }

    private func timedOut(_ outcome: Outcome<some Any>) async -> Bool {
        await Harness.eventually {
            if case .failure(.timedOut) = await outcome.result { return true }
            return false
        }
    }

    func test_C_CONN_13_aResponseStillArrivingDoesNotTimeOut() async throws {
        let clock = ManualClock()
        let channel = MeteredChannel()
        let session = try await readySession(over: channel, clock: clock)
        // About 50 MiB: the nine layers of the fixture with very long class names.
        var hierarchy = try Fixtures.hierarchy()
        for index in hierarchy.nodes.indices {
            hierarchy.nodes[index].className = String(repeating: "C", count: 5_600_000)
        }
        let bytes = FrameCodec.encodeForStream(Frame(requestID: 1, body: .hierarchy(hierarchy)))
        XCTAssertGreaterThan(bytes.count, 50_000_000)

        let outcome = track { try await session.hierarchy() }
        let segments = 15
        let length = (bytes.count + segments - 1) / segments
        for start in stride(from: 0, to: bytes.count, by: length) {
            await channel.feed(Data(bytes[start..<min(start + length, bytes.count)]))
            let read = await Harness.eventually(within: .seconds(5)) { await channel.isReceiving }
            XCTAssertTrue(read)
            // Two seconds between segments, thirty in all.
            if start + length < bytes.count {
                await pass(.seconds(2), on: clock)
            }
        }
        let answered = await Harness.eventually(within: .seconds(10)) {
            if case .success = await outcome.result { return true }
            return false
        }
        let result = await outcome.result
        XCTAssertTrue(answered, "\(String(describing: result))")
        await session.close()
    }

    func test_C_CONN_13_silenceEndsARequestAfterTheTimeout() async throws {
        let clock = ManualClock()
        let channel = MeteredChannel()
        let session = try await readySession(over: channel, clock: clock)
        let outcome = track { try await session.hierarchy() }
        await sent(.getHierarchy, on: channel)
        await pass(.milliseconds(9_500), on: clock)
        let open = await isOpen(outcome, on: clock)
        XCTAssertTrue(open, "ended before ten seconds")
        await pass(step, on: clock)
        let ended = await timedOut(outcome)
        XCTAssertTrue(ended)
        await session.close()
    }

    func test_C_CONN_13_thePausedTimeDoesNotCount() async throws {
        let clock = ManualClock()
        let channel = MeteredChannel()
        let session = try await readySession(over: channel, clock: clock)
        let request = GetLayerDetails(
            requests: [LayerDetailRequest(
                layerID: 1, wantSolo: true, wantGroup: false, wantAttributes: false)],
            maxTextureDimension: 0)
        let stream = await session.layerDetails(request)
        for index in 0..<3 {
            await channel.feed(FrameCodec.encodeForStream(.bulkyChunk(
                requestID: 1, sequence: UInt32(index), layerID: UInt64(index + 1),
                imageBytes: 1024)))
        }
        let paused = await Harness.eventually { await session.isReadingPaused }
        XCTAssertTrue(paused)

        // Thirty seconds with the reader not taking: this side's doing, not the server's.
        await pass(.seconds(30), on: clock)
        let outcome = track { () -> Int in
            var count = 0
            for try await _ in stream.chunks { count += 1 }
            return count
        }
        let caughtUp = await Harness.eventually {
            let untaken = await session.untakenChunkCount
            let receiving = await channel.isReceiving
            return untaken == 0 && receiving
        }
        XCTAssertTrue(caughtUp)
        let open = await isOpen(outcome, on: clock)
        XCTAssertTrue(open, "the stream timed out for the pause")

        // From here the silence is the server's.
        await pass(.milliseconds(9_500), on: clock)
        let stillOpen = await isOpen(outcome, on: clock)
        XCTAssertTrue(stillOpen)
        await pass(step, on: clock)
        let ended = await timedOut(outcome)
        XCTAssertTrue(ended)
        await session.close()
    }

    func test_C_CONN_13_aSuspendedProcessReadsWhatArrivedBeforeTimingOut() async throws {
        let clock = ManualClock()
        let channel = MeteredChannel()
        let session = try await readySession(over: channel, clock: clock)
        let outcome = track { try await session.hierarchy() }
        await sent(.getHierarchy, on: channel)
        await clock.waitForSleepers()

        // The process was stopped for thirty seconds; the answer came meanwhile. The
        // watchdog wakes first and must not take the whole thirty seconds for silence.
        clock.advance(by: .seconds(30))
        var answer = try Harness.fixture("hierarchy", "02-s2c-hierarchy.bin")
        answer.requestID = 1
        await channel.feed(FrameCodec.encodeForStream(answer))

        let answered = await Harness.eventually {
            if case .success = await outcome.result { return true }
            return false
        }
        let result = await outcome.result
        XCTAssertTrue(answered, "\(String(describing: result))")
        await session.close()
    }

    func test_C_CONN_13_aSuspendedProcessStillTimesOutWhenNothingCame() async throws {
        let clock = ManualClock()
        let channel = MeteredChannel()
        let session = try await readySession(over: channel, clock: clock)
        let outcome = track { try await session.hierarchy() }
        await sent(.getHierarchy, on: channel)
        await clock.waitForSleepers()
        clock.advance(by: .seconds(30))
        let open = await isOpen(outcome, on: clock)
        XCTAssertTrue(open, "the time the process did not run counted as silence")

        // Only what the step overran is taken off: the step itself, half a second, was
        // silence the process could have seen.
        await pass(.seconds(9), on: clock)
        let stillOpen = await isOpen(outcome, on: clock)
        XCTAssertTrue(stillOpen)
        await pass(step, on: clock)
        let ended = await timedOut(outcome)
        XCTAssertTrue(ended)
        await session.close()
    }

    func test_C_CONN_13_bytesReadOnWakingStartTheSilenceWhereTheyCame() async throws {
        let clock = ManualClock()
        let channel = MeteredChannel()
        let session = try await readySession(over: channel, clock: clock)
        let request = GetLayerDetails(
            requests: [LayerDetailRequest(
                layerID: 1, wantSolo: true, wantGroup: false, wantAttributes: false)],
            maxTextureDimension: 0)
        let stream = await session.layerDetails(request)
        let outcome = track { () -> Int in
            var count = 0
            for try await _ in stream.chunks { count += 1 }
            return count
        }
        await sent(.getLayerDetails, on: channel)
        await clock.waitForSleepers()

        // Stopped for thirty seconds. On waking, a chunk is read before the watchdog's step.
        clock.advance(by: .seconds(30), wakingSleepers: false)
        await channel.feed(FrameCodec.encodeForStream(.bulkyChunk(
            requestID: 1, sequence: 0, layerID: 1, imageBytes: 1024)))
        let read = await Harness.eventually { await channel.isReceiving }
        XCTAssertTrue(read)
        clock.wakeDueSleepers()

        // The silence counts from the chunk, not from thirty seconds after it.
        await pass(.milliseconds(9_500), on: clock)
        let open = await isOpen(outcome, on: clock)
        XCTAssertTrue(open)
        await pass(step, on: clock)
        let ended = await timedOut(outcome)
        XCTAssertTrue(ended, "the silence after the chunk was not counted from it")
        await session.close()
    }

    func test_C_CONN_13_theHandshakeTimesOutBySilenceToo() async {
        let clock = ManualClock()
        let channel = MeteredChannel()
        let session = session(over: channel, clock: clock)
        let outcome = track { try await session.handshake() }
        await sent(.hello, on: channel)
        await clock.waitForSleepers()
        clock.advance(by: .seconds(30))  // Stopped: not silence, but for the step's own half.
        await pass(.seconds(9), on: clock)
        let open = await isOpen(outcome, on: clock)
        XCTAssertTrue(open)
        await pass(step, on: clock)
        let ended = await timedOut(outcome)
        XCTAssertTrue(ended)
    }

    func test_C_CONN_13_aSlowAnswerOverTheLoopbackDoesNotTimeOut() async throws {
        // Requirement's thirty seconds in segments two seconds apart, scaled down: a one-second
        // timeout, three seconds in segments half a second apart.
        var answer = try Harness.fixture("hierarchy", "02-s2c-hierarchy.bin")
        answer.requestID = 1
        let bytes = FrameCodec.encodeForStream(answer)
        var steps = try MockScript.fixtures("handshake").steps
        steps.append(.expect(.getHierarchy, as: 1))
        let segments = 6
        let length = (bytes.count + segments - 1) / segments
        for start in stride(from: 0, to: bytes.count, by: length) {
            steps.append(.pause(.milliseconds(500)))
            steps.append(.sendBytes(Data(bytes[start..<min(start + length, bytes.count)])))
        }
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.session(for: server, requestTimeout: .seconds(1))
        _ = try await session.handshake()
        let start = ContinuousClock.now
        let hierarchy = try await session.hierarchy()
        XCTAssertEqual(hierarchy.nodes.count, 9)
        XCTAssertGreaterThan(ContinuousClock.now - start, .milliseconds(2_500))
        await session.close()
        await server.stop()
    }
}
