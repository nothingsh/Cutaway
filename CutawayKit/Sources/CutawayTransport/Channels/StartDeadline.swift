import Foundation
import os

/// A time limit on getting something started, such as a connection, that either the start or
/// the limit wins, never both. Cancelling the timer is not enough on its own: a timer already
/// past its sleep runs its action anyway, and would then end what had just started.
final class StartDeadline: Sendable {
    private enum State { case running, started, expired }

    private let state = OSAllocatedUnfairLock(initialState: State.running)

    /// Records that the start succeeded. False when the limit came first: its action has
    /// run, or is about to, so what was started must not be used.
    func start() -> Bool {
        transition(to: .started)
    }

    /// Records that the limit was reached. False when the start came first: the action
    /// must not run.
    func expire() -> Bool {
        transition(to: .expired)
    }

    private func transition(to next: State) -> Bool {
        state.withLock { state in
            guard state == .running else { return false }
            state = next
            return true
        }
    }

    /// Runs `operation`, calling `onExpiry` if `timeout` passes before it returns. Throws
    /// `expired` when the limit won, even if `operation` then succeeded: `onExpiry` has ended
    /// what it started. `sleep` is how the limit waits; tests replace it.
    static func run<T>(
        timeout: Duration, expired: any Error,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onExpiry: @escaping @Sendable () -> Void,
        operation: () async throws -> T
    ) async throws -> T {
        let deadline = StartDeadline()
        let timer = Task {
            try await sleep(timeout)
            if deadline.expire() { onExpiry() }
        }
        defer { timer.cancel() }
        let result: T
        do {
            result = try await operation()
        } catch {
            // Nothing started; the limit has nothing left to end.
            _ = deadline.start()
            throw error
        }
        guard deadline.start() else { throw expired }
        return result
    }
}
