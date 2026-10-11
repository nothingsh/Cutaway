import Foundation

/// The chunks of each stream that its reader has not taken yet: the size of each frame, in
/// order (C-CONN-12). Whether the session pauses reading follows from it alone. It is kept
/// apart from the pending requests, which forget a stream once it ends while its reader may
/// still have chunks to take.
struct StreamLedger {
    private struct Untaken {
        var sizes: [Int] = []
        var bytes = 0
    }

    let limit: ReadLimit
    private var streams: [UInt32: Untaken] = [:]

    init(limit: ReadLimit) {
        self.limit = limit
    }

    /// Whether some stream has as much waiting for its reader as is allowed.
    var isPaused: Bool {
        streams.values.contains { $0.sizes.count >= limit.chunks || $0.bytes >= limit.bytes }
    }

    /// Chunks that readers have not taken yet, over all streams.
    var untakenChunkCount: Int { streams.values.reduce(0) { $0 + $1.sizes.count } }

    /// A chunk of stream `id`, whose frame took `size` bytes, went to its reader.
    mutating func add(chunkOf size: Int, to id: UInt32) {
        streams[id, default: Untaken()].sizes.append(size)
        streams[id]?.bytes += size
    }

    /// The reader of stream `id` took its oldest chunk. False when it had none untaken, as
    /// after the stream was forgotten.
    mutating func take(from id: UInt32) -> Bool {
        guard var untaken = streams[id], !untaken.sizes.isEmpty else { return false }
        untaken.bytes -= untaken.sizes.removeFirst()
        streams[id] = untaken.sizes.isEmpty ? nil : untaken
        return true
    }

    /// What stream `id` left untaken holds nothing up any more.
    mutating func forget(_ id: UInt32) {
        streams[id] = nil
    }

    mutating func forgetAll() {
        streams = [:]
    }
}
