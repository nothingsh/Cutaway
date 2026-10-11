import Foundation

/// Where the tests run. A CI runner is a virtual Mac, slower than the developer's and with a
/// virtual GPU; scripts/check.sh says so with `CUTAWAY_CI=1`, which GitHub Actions sets
/// (.github/workflows/check.yml). There, tests are skipped whose limits are for the test
/// configuration (times, the main thread's pauses), or that need the GPU to hold more than a
/// virtual one does, or whose timing a loaded machine upsets. They still run on the developer's
/// Mac, which is what decides whether the work is done.
public enum TestRunner {
    public static var isCI: Bool {
        ProcessInfo.processInfo.environment["CUTAWAY_CI"] == "1"
    }

    /// For `XCTSkipIf(TestRunner.isCI, TestRunner.timedOnTheDevelopersMac)`.
    public static let timedOnTheDevelopersMac =
        "its limits are for the developer's Mac, not a CI runner"
}
