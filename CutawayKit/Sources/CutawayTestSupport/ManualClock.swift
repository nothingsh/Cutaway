import Foundation

import CutawayTransport

/// A clock that moves only when a test moves it (C-CONN-13). Sleepers wake when the time they
/// asked for is reached; `advance(by:)` can also leap far past it, as a stopped process or a
/// sleeping Mac does.
public final class ManualClock: SessionClock, @unchecked Sendable {
    private struct Sleeper {
        var deadline: Duration
        var continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var current: Duration = .zero
    private var sleepers: [UUID: Sleeper] = [:]

    public init() {}

    /// How many tasks wait on this clock.
    public var sleeperCount: Int {
        lock.withLock { sleepers.count }
    }

    public func now() -> Duration {
        lock.withLock { current }
    }

    public func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enum Now { case wait, wake, cancel }
                let now: Now = lock.withLock {
                    // Cancelled before it got here: the cancellation handler found nothing to
                    // wake, so it must not wait.
                    if Task.isCancelled { return .cancel }
                    guard duration > .zero else { return .wake }
                    sleepers[id] = Sleeper(deadline: current + duration, continuation: continuation)
                    return .wait
                }
                switch now {
                case .wait: break
                case .wake: continuation.resume()
                case .cancel: continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let sleeper = lock.withLock { sleepers.removeValue(forKey: id) }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves the time on at once by `duration` and, unless told not to, wakes whoever's time
    /// has come. Not waking them lets a test do something first, as bytes that arrive while a
    /// process is stopped are there before its timers run.
    public func advance(by duration: Duration, wakingSleepers: Bool = true) {
        lock.withLock { current += duration }
        if wakingSleepers { wakeDueSleepers() }
    }

    /// Wakes whoever's time has come.
    public func wakeDueSleepers() {
        let due: [Sleeper] = lock.withLock {
            let due = sleepers.filter { $0.value.deadline <= current }
            for key in due.keys { sleepers[key] = nil }
            return Array(due.values)
        }
        for sleeper in due { sleeper.continuation.resume() }
    }

    /// Moves the time on by `duration` in steps of `step`, as time passes for a process that
    /// runs: before each step, waits for a sleeper, so that one woken by the last step has gone
    /// back to sleep. Returns false when no sleeper came for some step: that step then woke
    /// nobody, and a test that relies on each step being seen should fail.
    @discardableResult
    public func advance(by duration: Duration, inStepsOf step: Duration) async -> Bool {
        var everyStepSeen = true
        var left = duration
        while left > .zero {
            let next = min(step, left)
            if await !waitForSleepers() { everyStepSeen = false }
            advance(by: next)
            left -= next
        }
        return everyStepSeen
    }

    /// Waits until at least `count` tasks sleep on this clock, for at most two seconds of real
    /// time. Returns whether they do.
    @discardableResult
    public func waitForSleepers(_ count: Int = 1) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while sleeperCount < count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return sleeperCount >= count
    }
}
