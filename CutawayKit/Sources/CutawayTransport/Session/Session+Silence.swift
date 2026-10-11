import Foundation

// `startWatchdog()` is internal only so Session.swift can call it.
extension Session {
    // MARK: - Silence (C-CONN-13)

    /// The longest step the watchdog sleeps; shorter when the timeout is short.
    private static let watchStep = Duration.milliseconds(500)
    /// A step that took this much longer than it should have means the process did not run:
    /// it was stopped, or the Mac slept (C-CONN-13).
    private static let stoppedThreshold = Duration.seconds(1)

    /// Watches for silence while a request is open or the handshake goes on. One watchdog for
    /// all requests, in small steps: a step that took far longer than it should have means the
    /// process did not run, and that time counts as nobody's silence. The next step comes
    /// after the reading task has had its turn with whatever arrived meanwhile.
    func startWatchdog() {
        guard watchdog == nil, phase != .closed else { return }
        let step = min(Self.watchStep, requestTimeout / 4)
        watchdog = Task { [weak self, clock] in
            while true {
                let before = clock.now()
                guard (try? await clock.sleep(for: step)) != nil else { return }
                guard let self, await self.watch(sleptFrom: before, step: step) else { return }
            }
        }
    }

    /// One step of the watchdog. Returns whether to go on; stops it when nothing is open.
    private func watch(sleptFrom before: Duration, step: Duration) -> Bool {
        let now = clock.now()
        let overrun = now - before - step
        if overrun > Self.stoppedThreshold {
            excuse(overrun, now: now)
        } else {
            timeOutSilentRequests(now: now)
        }
        guard phase != .closed, phase == .handshaking || !pending.isEmpty else {
            watchdog = nil
            return false
        }
        return true
    }

    /// Takes `duration` off every silence: the process was not running. No moment moves past
    /// `now`: bytes read, or a request sent, after the process woke and before this step
    /// already start their silence at the right time.
    private func excuse(_ duration: Duration, now: Duration) {
        lastHeard = min(lastHeard + duration, now)
        pending.excuse(duration, now: now)
    }

    private func timeOutSilentRequests(now: Duration) {
        // A pause is this side's doing, not the server's silence.
        if isPaused {
            lastHeard = now
            return
        }
        if phase == .handshaking {
            // The handshake started its silence: it set `lastHeard`.
            if now - lastHeard >= requestTimeout { expireHandshake() }
            return
        }
        for id in pending.silent(now: now, lastHeard: lastHeard, timeout: requestTimeout) {
            pending.end(id, throwing: .timedOut)
        }
    }
}
