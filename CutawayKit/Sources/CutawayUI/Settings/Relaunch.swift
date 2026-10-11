import AppKit

/// Quitting and opening Cutaway again, to start in a newly chosen language (C-LOC-01).
@MainActor
enum Relaunch {
    /// Opens the app again once it ends. The process ends right after it is set: it is
    /// never removed.
    private static var terminationObserver: (any NSObjectProtocol)?

    /// Quits as ⌘Q does; once this process has ended, a small shell opens the app again.
    /// The shell starts only when the app does terminate.
    static func restart() {
        let bundle = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in
            let shell = Process()
            shell.executableURL = URL(fileURLWithPath: "/bin/sh")
            shell.arguments = arguments(waitingFor: pid, thenOpening: bundle)
            try? shell.run()
        }
        NSApp.terminate(nil)
    }

    /// `sh` arguments that wait for `pid` to end, then open the app at `bundle`. Both are
    /// passed as positional parameters, never spliced into the script.
    nonisolated static func arguments(waitingFor pid: Int32, thenOpening bundle: String) -> [String] {
        [
            "-c",
            #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.1; done; /usr/bin/open "$2""#,
            "cutaway-relaunch", String(pid), bundle,
        ]
    }
}
