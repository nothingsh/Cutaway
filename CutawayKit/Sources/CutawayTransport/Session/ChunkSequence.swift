import Foundation

/// The chunks of a stream, as a stream of the standard library gives them, telling whoever
/// sends them how far the reader has got (C-CONN-12): each chunk taken, and the moment nothing
/// holds the sequence any more. A session reads no more from the connection while a reader
/// has too much left to take.
public struct ChunkSequence<Element: Sendable>: AsyncSequence, Sendable {
    public typealias Failure = any Error

    private let base: AsyncThrowingStream<Element, any Error>
    private let token: ConsumptionToken

    /// Chunks whose taking nobody needs to hear of, such as an archive's.
    package init(_ base: AsyncThrowingStream<Element, any Error>) {
        self.init(base, token: ConsumptionToken(onTake: {}, onRelease: {}))
    }

    init(_ base: AsyncThrowingStream<Element, any Error>, token: ConsumptionToken) {
        self.base = base
        self.token = token
    }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeAsyncIterator(), token: token)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        var base: AsyncThrowingStream<Element, any Error>.AsyncIterator
        let token: ConsumptionToken

        public mutating func next() async throws -> Element? {
            let element = try await base.next()
            if element != nil { token.took() }
            return element
        }

        /// On the caller's actor, as the stream it wraps does, so that a reader on the main
        /// actor does not hop off it for every chunk. macOS 14 uses `next()`.
        @available(macOS 15.0, *)
        public mutating func next(
            isolation actor: isolated (any Actor)?
        ) async throws -> Element? {
            let element = try await base.next(isolation: actor)
            if element != nil { token.took() }
            return element
        }
    }
}

/// Shared by a sequence and its iterators. It goes when the last of them does, which is how
/// the sender learns that a reader dropped a stream it had not read to the end: the stream of
/// the standard library reports its end when it finishes, not when its reader lets go.
final class ConsumptionToken: Sendable {
    private let onTake: @Sendable () -> Void
    private let onRelease: @Sendable () -> Void

    init(onTake: @escaping @Sendable () -> Void, onRelease: @escaping @Sendable () -> Void) {
        self.onTake = onTake
        self.onRelease = onRelease
    }

    func took() {
        onTake()
    }

    deinit {
        onRelease()
    }
}
