import CutawayTransport
import Foundation

/// A channel to nowhere: nothing ever arrives and what is sent is dropped. For a `Session`
/// that a test needs only as a value; requests on such a session fail at once.
public final class InertChannel: ByteChannel {
    public init() {}

    public func send(_ data: Data) async throws {}

    public func receive() async throws -> Data? { nil }

    public func close() {}
}

/// A channel whose bytes arrive only when a test hands them over. Closing it is counted but
/// does not end a receive that is waiting: that models bytes that had already arrived when
/// the channel was closed, which a real connection can deliver after `close()`.
public actor GatedChannel: ByteChannel {
    private var waiting: CheckedContinuation<Data?, Never>?
    private var delivered: [Data] = []

    /// How many times `close()` was called.
    public private(set) var closeCount = 0

    public init() {}

    /// Whether a receive is waiting for bytes.
    public var isReceiving: Bool { waiting != nil }

    public func send(_ data: Data) async throws {}

    public func receive() async throws -> Data? {
        if !delivered.isEmpty { return delivered.removeFirst() }
        return await withCheckedContinuation { waiting = $0 }
    }

    /// Hands bytes to the waiting receive, or to the next one.
    public func deliver(_ data: Data) {
        if let waiting {
            self.waiting = nil
            waiting.resume(returning: data)
        } else {
            delivered.append(data)
        }
    }

    public nonisolated func close() {
        Task { await self.recordClose() }
    }

    private func recordClose() {
        closeCount += 1
    }
}
