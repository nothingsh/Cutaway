import Foundation

/// The requests sent that have not ended, by request ID (C-CONN-04): single requests that wait
/// for their answer, and streams that have not ended. Ending one here hands its caller the
/// outcome; deciding which outcome is the session's.
struct PendingTable {
    private var requests: [UInt32: Session.Pending] = [:]

    subscript(id: UInt32) -> Session.Pending? { requests[id] }

    var isEmpty: Bool { requests.isEmpty }

    /// Requests that wait for their single answer.
    var singleCount: Int {
        requests.values.reduce(0) { count, request in
            if case .single = request { return count + 1 }
            return count
        }
    }

    /// Streams that have not ended.
    var streamCount: Int { requests.count - singleCount }

    mutating func insert(_ request: Session.SingleRequest, for id: UInt32) {
        requests[id] = .single(request)
    }

    /// Adds stream `id`, or stores what changed about it.
    mutating func store(_ stream: Session.StreamRequest, for id: UInt32) {
        requests[id] = .stream(stream)
    }

    /// Forgets request `id` and returns it, without ending it.
    @discardableResult
    mutating func remove(_ id: UInt32) -> Session.Pending? {
        requests.removeValue(forKey: id)
    }

    /// Marks stream `id` as being cancelled. False when it is not a pending stream, or was
    /// marked already.
    mutating func markCancelling(_ id: UInt32) -> Bool {
        guard case .stream(var stream) = requests[id], !stream.isCancelling else { return false }
        stream.isCancelling = true
        requests[id] = .stream(stream)
        return true
    }

    /// Ends request `id` with `error`, whichever kind it is. Nothing happens when it is not
    /// pending, as when its answer came, or it timed out, earlier.
    mutating func end(_ id: UInt32, throwing error: RequestError) {
        guard let request = remove(id) else { return }
        Self.end(request, throwing: error)
    }

    /// Ends every request with `error`. The table is empty before the first one is ended.
    mutating func endAll(throwing error: RequestError) {
        let ended = requests
        requests = [:]
        for request in ended.values {
            Self.end(request, throwing: error)
        }
    }

    /// Ends the streams with `error`, leaving the table as it is: for a session that goes
    /// away, whose readers may still hold its streams. Single requests cannot be pending then,
    /// because their callers keep the session alive.
    func finishStreams(throwing error: RequestError) {
        for request in requests.values {
            guard case .stream(let stream) = request else { continue }
            stream.continuation.finish(throwing: error)
        }
    }

    // MARK: - Silence (C-CONN-13)

    /// The requests that have heard nothing for `timeout`: neither since they were sent nor
    /// since bytes last arrived.
    func silent(now: Duration, lastHeard: Duration, timeout: Duration) -> [UInt32] {
        requests.compactMap { id, request in
            now - max(request.sentAt, lastHeard) >= timeout ? id : nil
        }
    }

    /// Moves every request's start of silence `duration` later, but not past `now`: the
    /// process was not running.
    mutating func excuse(_ duration: Duration, now: Duration) {
        for (id, request) in requests {
            switch request {
            case .single(var single):
                single.sentAt = min(single.sentAt + duration, now)
                requests[id] = .single(single)
            case .stream(var stream):
                stream.sentAt = min(stream.sentAt + duration, now)
                requests[id] = .stream(stream)
            }
        }
    }

    private static func end(_ request: Session.Pending, throwing error: RequestError) {
        switch request {
        case .single(let single): single.continuation.resume(throwing: error)
        case .stream(let stream): stream.continuation.finish(throwing: error)
        }
    }
}

extension Session.Pending {
    /// When the request was sent, on the session's clock.
    var sentAt: Duration {
        switch self {
        case .single(let single): single.sentAt
        case .stream(let stream): stream.sentAt
        }
    }
}
