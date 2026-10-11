import Foundation

/// Cuts frames out of a byte stream (P-FRAME-01): each frame is a 4-byte little-endian
/// length followed by that many bytes. The reader does no I/O and does not decode; hand the
/// payloads it returns to `FrameCodec.decode`.
///
/// Each byte of a payload is copied once, into a buffer of the payload's own that starts at
/// index 0. A frame that is complete among the bytes at hand is copied out of them; a frame
/// that is not yet complete gets a buffer of its full length at once, and the bytes that
/// arrive later go straight into it, so a large frame is neither grown piece by piece nor
/// copied again when it is handed out.
package struct FrameReader: Sendable {
    /// Bytes not yet cut into frames start at `offset`; those before it were handed out.
    private var buffer = Data()
    private var offset = 0
    /// The frame being filled, once its length is known and its bytes did not all arrive
    /// together: everything after its length prefix that arrived so far.
    private var partial: Data?
    /// The length of `partial` once complete.
    private var partialLength = 0
    private var failure: FrameError?

    /// Handed-out bytes at the front of `buffer` are dropped once there are this many and
    /// they are at least half of it, so dropping them costs no more, over time, than
    /// appending did.
    private static let compactionThreshold = 65536

    package init() {}

    /// Adds bytes that arrived from the peer.
    package mutating func append(_ bytes: Data) {
        guard failure == nil, !bytes.isEmpty else { return }
        var rest = bytes[...]
        if var frame = partial {
            // Take the copy-on-write reference out of `partial` so that appending does not
            // copy the frame.
            partial = nil
            let taken = min(partialLength - frame.count, rest.count)
            frame.append(rest.prefix(taken))
            partial = frame
            rest = rest.dropFirst(taken)
            if rest.isEmpty { return }
        }
        if offset == buffer.count {
            // Nothing is waiting: keep the bytes as they came, without copying them.
            buffer = rest
            offset = 0
        } else {
            buffer.append(rest)
        }
    }

    /// The next complete payload, or nil when more bytes are needed.
    ///
    /// Throws `FrameError.tooLarge` when a length exceeds the maximum. The stream cannot be
    /// resynchronised after that, so every later call throws the same error.
    package mutating func nextPayload() throws -> Data? {
        if let failure { throw failure }

        if let frame = partial {
            guard frame.count == partialLength else { return nil }
            partial = nil
            return frame
        }

        let available = buffer.count - offset
        guard available >= 4 else { return nil }

        let start = buffer.startIndex + offset
        let length = (0..<4).reduce(0) { $0 | Int(buffer[start + $1]) << (8 * $1) }
        guard length <= FrameCodec.maximumFrameLength else {
            let error = FrameError.tooLarge(length: length)
            failure = error
            buffer = Data()
            offset = 0
            throw error
        }

        let body = (start + 4)..<min(start + 4 + length, buffer.endIndex)
        if available >= 4 + length {
            // A copy that starts at index 0; the reader then drops these bytes.
            let payload = Data(buffer[body])
            offset += 4 + length
            compact()
            return payload
        }

        // The rest has not arrived. The buffer is reserved in full now, as virtual memory
        // that is only touched as bytes arrive; the length is within the frame limit.
        var frame = Data(capacity: length)
        frame.append(buffer[body])
        partial = frame
        partialLength = length
        // Everything at hand went into the frame.
        buffer.removeAll(keepingCapacity: buffer.count <= Self.compactionThreshold)
        offset = 0
        return nil
    }

    /// Drops the handed-out bytes at the front of the buffer when that is cheap enough.
    private mutating func compact() {
        if offset == buffer.count {
            buffer.removeAll(keepingCapacity: buffer.count <= Self.compactionThreshold)
            offset = 0
        } else if offset >= Self.compactionThreshold, offset * 2 >= buffer.count {
            buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + offset))
            offset = 0
        }
    }
}
