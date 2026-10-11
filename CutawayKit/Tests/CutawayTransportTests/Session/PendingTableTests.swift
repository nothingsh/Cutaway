import CutawayWire
import XCTest
@testable import CutawayTransport

/// The requests a session waits on, apart from the session: how they end (C-CONN-04,
/// C-CONN-07), how a stream is cancelled once (C-CONN-06), and whose silence is too long
/// (C-CONN-13).
final class PendingTableTests: XCTestCase {
    /// A single request whose caller waits in `outcome`.
    private struct Caller {
        var request: Session.SingleRequest
        var outcome: Task<Session.Received, any Error>

        /// The error the caller's request ended with; nil when it ended otherwise.
        func error() async -> RequestError? {
            if case .failure(let error) = await outcome.result { return error as? RequestError }
            return nil
        }
    }

    /// A stream whose reader reads `outcome`.
    private struct Reader {
        var request: Session.StreamRequest
        var outcome: Task<Void, any Error>

        func error() async -> RequestError? {
            if case .failure(let error) = await outcome.result { return error as? RequestError }
            return nil
        }
    }

    private func caller(sentAt: Duration = .zero) async -> Caller {
        let (handoff, input) = AsyncStream.makeStream(
            of: CheckedContinuation<Session.Received, any Error>.self)
        let outcome = Task {
            try await withCheckedThrowingContinuation { input.yield($0) }
        }
        var iterator = handoff.makeAsyncIterator()
        let continuation = await iterator.next()!
        return Caller(
            request: Session.SingleRequest(
                expects: .hierarchy, continuation: continuation, sentAt: sentAt),
            outcome: outcome)
    }

    private func reader(sentAt: Duration = .zero) -> Reader {
        let (chunks, continuation) = AsyncThrowingStream.makeStream(of: [LayerDetail].self)
        let outcome = Task {
            for try await _ in chunks {}
        }
        return Reader(
            request: Session.StreamRequest(continuation: .plain(continuation), sentAt: sentAt),
            outcome: outcome)
    }

    func test_C_CONN_04_endingARequestHandsItsCallerTheErrorOnce() async {
        var table = PendingTable()
        let single = await caller()
        let stream = reader()
        table.insert(single.request, for: 1)
        table.store(stream.request, for: 2)
        XCTAssertEqual(table.singleCount, 1)
        XCTAssertEqual(table.streamCount, 1)

        table.end(1, throwing: .timedOut)
        table.end(2, throwing: .appNotActive(message: nil))
        // A late answer, or a second timeout, finds nothing.
        table.end(1, throwing: .disconnected)

        XCTAssertTrue(table.isEmpty)
        let singleError = await single.error()
        let streamError = await stream.error()
        XCTAssertEqual(singleError, .timedOut)
        XCTAssertEqual(streamError, .appNotActive(message: nil))
    }

    func test_C_CONN_04_aRemovedRequestIsNotEnded() async {
        var table = PendingTable()
        let single = await caller()
        table.insert(single.request, for: 1)

        guard case .single(let removed) = table.remove(1) else {
            XCTFail("the request was not pending")
            return
        }
        XCTAssertTrue(table.isEmpty)
        // Its answer is the session's to give.
        removed.continuation.resume(throwing: RequestError.cancelled)
        let error = await single.error()
        XCTAssertEqual(error, .cancelled)
    }

    func test_C_CONN_07_endingAllEndsEveryRequest() async {
        var table = PendingTable()
        let single = await caller()
        let stream = reader()
        table.insert(single.request, for: 1)
        table.store(stream.request, for: 2)

        table.endAll(throwing: .disconnected)

        XCTAssertTrue(table.isEmpty)
        let singleError = await single.error()
        let streamError = await stream.error()
        XCTAssertEqual(singleError, .disconnected)
        XCTAssertEqual(streamError, .disconnected)
    }

    func test_C_CONN_07_finishingTheStreamsLeavesSingleRequests() async {
        var table = PendingTable()
        let single = await caller()
        let stream = reader()
        table.insert(single.request, for: 1)
        table.store(stream.request, for: 2)

        table.finishStreams(throwing: .disconnected)
        let streamError = await stream.error()
        XCTAssertEqual(streamError, .disconnected)
        XCTAssertEqual(table.singleCount, 1)

        table.endAll(throwing: .disconnected)
        _ = await single.error()
    }

    func test_C_CONN_06_aStreamIsMarkedCancellingOnce() async {
        var table = PendingTable()
        let single = await caller()
        let stream = reader()
        table.insert(single.request, for: 1)
        table.store(stream.request, for: 2)

        XCTAssertTrue(table.markCancelling(2))
        XCTAssertFalse(table.markCancelling(2))
        guard case .stream(let marked) = table[2] else {
            XCTFail("the stream went")
            return
        }
        XCTAssertTrue(marked.isCancelling)
        // Only streams are cancelled.
        XCTAssertFalse(table.markCancelling(1))
        XCTAssertFalse(table.markCancelling(3))

        table.endAll(throwing: .disconnected)
        _ = await single.error()
        _ = await stream.error()
    }

    func test_C_CONN_13_silenceCountsFromTheLaterOfSendingAndHearing() async {
        var table = PendingTable()
        let early = await caller(sentAt: .seconds(1))
        let late = reader(sentAt: .seconds(5))
        table.insert(early.request, for: 1)
        table.store(late.request, for: 2)

        // Nothing heard since 0: request 1 has been silent for 10 s, request 2 for 6 s.
        XCTAssertEqual(table.silent(now: .seconds(11), lastHeard: .zero, timeout: .seconds(10)), [1])
        XCTAssertEqual(
            Set(table.silent(now: .seconds(15), lastHeard: .zero, timeout: .seconds(10))), [1, 2])
        // A byte at 4 s: request 1 is silent from then.
        XCTAssertEqual(table.silent(now: .seconds(13), lastHeard: .seconds(4), timeout: .seconds(10)), [])
        XCTAssertEqual(table.silent(now: .seconds(14), lastHeard: .seconds(4), timeout: .seconds(10)), [1])

        table.endAll(throwing: .disconnected)
        _ = await early.error()
        _ = await late.error()
    }

    func test_C_CONN_13_excusedTimeMovesSilenceButNotPastNow() async {
        var table = PendingTable()
        let early = await caller(sentAt: .seconds(1))
        let late = reader(sentAt: .seconds(8))
        table.insert(early.request, for: 1)
        table.store(late.request, for: 2)

        table.excuse(.seconds(5), now: .seconds(10))

        XCTAssertEqual(table[1]?.sentAt, .seconds(6))
        XCTAssertEqual(table[2]?.sentAt, .seconds(10))

        table.endAll(throwing: .disconnected)
        _ = await early.error()
        _ = await late.error()
    }
}
