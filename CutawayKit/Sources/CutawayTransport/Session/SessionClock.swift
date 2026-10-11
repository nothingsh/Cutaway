import Foundation

/// The time a session measures silence by (C-CONN-13). Tests replace it with one they move by
/// hand; everything else uses `ContinuousClock`.
package protocol SessionClock: Sendable {
    /// Time since some fixed point, the same for every call.
    func now() -> Duration
    /// Returns once `duration` has passed. Throws when the task is cancelled.
    func sleep(for duration: Duration) async throws
}

/// The clock that keeps going while the process is stopped and while the Mac sleeps, which is
/// why the session watches it in small steps rather than trusting one long sleep.
package struct ContinuousSessionClock: SessionClock {
    private let origin = ContinuousClock.now

    package init() {}

    package func now() -> Duration {
        ContinuousClock.now - origin
    }

    package func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
