import CutawayWire
import Foundation

/// The response to `GetLayerDetails`: chunks in `sequence` order.
///
/// Iterating `chunks` ends normally when the stream completed, throws `RequestError.cancelled`
/// when it was cancelled, and throws the reason when it failed. A reader that stops reading —
/// its task cancelled, or the stream released unread — cancels the request as `cancel()` does.
///
/// While a reader leaves chunks untaken, the session stops reading from the connection
/// (C-CONN-12), and every other answer waits behind them. So a reader must not wait for
/// another answer of the same session while it holds chunks it has not taken.
public struct LayerDetailsStream: Sendable {
    public let chunks: ChunkSequence<[LayerDetail]>
    private let cancelAction: @Sendable () async -> Void

    /// A stream of `chunks` that `cancelAction` stops. Sessions make these; so can whatever
    /// answers the same requests otherwise, such as an archive.
    public init(
        chunks: AsyncThrowingStream<[LayerDetail], any Error>,
        cancelAction: @escaping @Sendable () async -> Void
    ) {
        self.init(chunks: ChunkSequence(chunks), cancelAction: cancelAction)
    }

    init(chunks: ChunkSequence<[LayerDetail]>, cancelAction: @escaping @Sendable () async -> Void) {
        self.chunks = chunks
        self.cancelAction = cancelAction
    }

    /// Asks the server to stop. Chunks that still arrive are dropped; the stream ends once the
    /// server confirms.
    public func cancel() async {
        await cancelAction()
    }
}

/// A response together with the buffer of the frame it came in, as received. An archive keeps
/// these bytes unchanged (Resources/ARCHIVE.md).
public struct Recorded<Value: Sendable>: Sendable {
    public var value: Value
    /// The frame's plain buffer, without the length prefix.
    public var payload: Data

    public init(value: Value, payload: Data) {
        self.value = value
        self.payload = payload
    }
}

/// `LayerDetailsStream` whose chunks come with the bytes of their frames. Ends, fails and
/// cancels as `LayerDetailsStream` does.
public struct RecordedLayerDetailsStream: Sendable {
    public let chunks: ChunkSequence<Recorded<[LayerDetail]>>
    private let cancelAction: @Sendable () async -> Void

    init(
        chunks: ChunkSequence<Recorded<[LayerDetail]>>,
        cancelAction: @escaping @Sendable () async -> Void
    ) {
        self.chunks = chunks
        self.cancelAction = cancelAction
    }

    /// Asks the server to stop, as `LayerDetailsStream.cancel()` does.
    public func cancel() async {
        await cancelAction()
    }
}
