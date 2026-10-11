import Network
import os
import XCTest
@testable import CutawayTransport

/// Starting a connection ends once, whatever states Network.framework still had queued: the
/// connecting side of C-CONN-01.
final class ConnectionStartTests: XCTestCase {
    private let refused = NWError.posix(.ECONNREFUSED)

    private enum Ending: Equatable {
        case ready
        case failed(ChannelError)
    }

    /// The start's ending for the state, comparable; nil when the state does not end it.
    private func ending(_ gate: ConnectionStartGate, _ state: NWConnection.State) -> Ending? {
        gate.outcome(for: state).map { outcome in
            switch outcome {
            case .success: .ready
            case .failure(let error): .failed(error)
            }
        }
    }

    func test_C_CONN_01_aRefusedConnectionThatWaitsThenFailsEndsTheStartOnce() {
        let gate = ConnectionStartGate()

        XCTAssertEqual(
            ending(gate, .waiting(refused)), .failed(.connectionFailed("\(refused)")))
        XCTAssertNil(ending(gate, .failed(refused)))
        // Cancelling the failed connection brings one more state.
        XCTAssertNil(ending(gate, .cancelled))
    }

    func test_C_CONN_01_aStateAfterReadyDoesNotEndTheStartAgain() {
        let gate = ConnectionStartGate()

        XCTAssertNil(ending(gate, .preparing))
        XCTAssertEqual(ending(gate, .ready), .ready)
        XCTAssertNil(ending(gate, .failed(refused)))
    }

    func test_C_CONN_01_aCancelledStartIsATimeout() {
        let gate = ConnectionStartGate()

        XCTAssertEqual(ending(gate, .cancelled), .failed(.timedOut))
        XCTAssertNil(ending(gate, .ready))
    }

    // MARK: - The time limit on a start

    func test_C_CONN_01_aLimitReachedAfterTheStartDoesNotActAnyMore() {
        let deadline = StartDeadline()

        XCTAssertTrue(deadline.start())
        // The timer was already past its sleep when it was cancelled.
        XCTAssertFalse(deadline.expire())
    }

    func test_C_CONN_01_aStartAfterTheLimitIsNotUsed() {
        let deadline = StartDeadline()

        XCTAssertTrue(deadline.expire())
        XCTAssertFalse(deadline.start())
    }

    func test_C_CONN_01_aStartThatSucceedsAfterTheLimitEndedItFailsAsATimeout() async {
        let expired = Expectation()
        do {
            // The limit is reached while the start is under way; the start still succeeds,
            // as a connection that became ready just as the timer cancelled it would.
            _ = try await StartDeadline.run(
                timeout: .zero, expired: ChannelError.timedOut, sleep: { _ in },
                onExpiry: { expired.fulfil() },
                operation: { await expired.wait() })
            XCTFail("a start that the limit ended was returned")
        } catch {
            XCTAssertEqual(error as? ChannelError, .timedOut)
        }
    }

    func test_C_CONN_01_aStartWithinTheLimitIsReturned() async throws {
        let value = try await StartDeadline.run(
            timeout: .seconds(60), expired: ChannelError.timedOut,
            onExpiry: { XCTFail("the limit acted on a start that succeeded") },
            operation: { 7 })
        XCTAssertEqual(value, 7)
    }

    func test_C_CONN_01_aStartThatFailsKeepsItsOwnError() async {
        do {
            _ = try await StartDeadline.run(
                timeout: .seconds(60), expired: ChannelError.timedOut, onExpiry: {},
                operation: { () async throws -> Int in
                    throw ChannelError.connectionFailed("refused")
                })
            XCTFail("a failed start was returned")
        } catch {
            XCTAssertEqual(error as? ChannelError, .connectionFailed("refused"))
        }
    }
}

/// Something that happens once, which others can wait for.
private final class Expectation: Sendable {
    private let state = OSAllocatedUnfairLock(
        initialState: (done: false, waiters: [CheckedContinuation<Void, Never>]()))

    func fulfil() {
        let waiters = state.withLock { state in
            state.done = true
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiters { waiter.resume() }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let done = state.withLock { state in
                if !state.done { state.waiters.append(continuation) }
                return state.done
            }
            if done { continuation.resume() }
        }
    }
}
