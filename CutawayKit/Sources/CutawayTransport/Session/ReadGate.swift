import Foundation

/// How much of a stream may wait for its reader before the session stops reading from the
/// connection (C-CONN-12): this many chunks, or this many bytes of their frames, whichever
/// comes first.
package struct ReadLimit: Sendable {
    package var chunks: Int
    package var bytes: Int

    package init(chunks: Int, bytes: Int) {
        self.chunks = chunks
        self.bytes = bytes
    }

    /// Two chunks or 64 MiB, whichever comes first, of a stream not yet taken (C-CONN-12).
    package static let standard = Self(chunks: 2, bytes: 64 << 20)
}

// Internal only so the files of Session can reach it.
/// Where the reading task waits while the readers catch up (C-CONN-12). It is the task's own,
/// not the session's: waiting inside the session would hold it, and a session that nobody
/// else holds must still go away and end its streams (C-CONN-07).
final class ReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = true
    private var waiter: CheckedContinuation<Void, Never>?

    /// Whether the reading task is, or is about to be, held here.
    var isClosed: Bool { lock.withLock { !isOpen } }

    func close() {
        lock.withLock { isOpen = false }
    }

    func open() {
        let waiter: CheckedContinuation<Void, Never>? = lock.withLock {
            isOpen = true
            defer { self.waiter = nil }
            return self.waiter
        }
        waiter?.resume()
    }

    /// Returns at once while open; otherwise when it opens.
    func pass() async {
        await withCheckedContinuation { continuation in
            let passes: Bool = lock.withLock {
                if isOpen { return true }
                waiter = continuation
                return false
            }
            if passes { continuation.resume() }
        }
    }
}
