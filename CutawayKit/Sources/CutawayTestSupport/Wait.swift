import Foundation

public enum Wait {
    /// Polls `condition` until it holds or `timeout` passes. Returns whether it held.
    public static func until(
        within timeout: Duration = .seconds(2), _ condition: @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    /// The same, for a condition on the main actor: it can read the interface's objects, which
    /// a `@Sendable` closure must not capture.
    @MainActor
    public static func untilOnMain(
        within timeout: Duration = .seconds(2), _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}

extension Wait {
    /// Runs `body` on the main actor and turns the main run loop until it ends, for tests
    /// that are not async: an async test runs inside a job of the main queue, where turning
    /// the run loop draws no frames. Fails after `timeout`.
    @MainActor
    public static func running(
        within timeout: TimeInterval = 10, _ body: @escaping @MainActor () async throws -> Void
    ) throws {
        final class Outcome {
            var result: Result<Void, any Error>?
        }
        let outcome = Outcome()
        Task { @MainActor in
            do {
                try await body()
                outcome.result = .success(())
            } catch {
                outcome.result = .failure(error)
            }
        }
        let deadline = Date().addingTimeInterval(timeout)
        while outcome.result == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        guard let result = outcome.result else { throw CancellationError() }
        try result.get()
    }
}
