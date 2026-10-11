import Foundation
import Network

enum ListenerSupport {
    /// Starts a listener and returns its connections once it is ready.
    static func start(_ listener: NWListener, label: String) async throws -> AsyncStream<NWConnection> {
        let (connections, continuation) = AsyncStream.makeStream(of: NWConnection.self)
        listener.newConnectionHandler = { continuation.yield($0) }
        try await withCheckedThrowingContinuation {
            (ready: CheckedContinuation<Void, any Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    ready.resume()
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    ready.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: DispatchQueue(label: label))
        }
        return connections
    }

    /// Cancels a listener and returns once it has released its port or socket path.
    /// Call it once per listener.
    static func stop(_ listener: NWListener) async {
        await withCheckedContinuation { (released: CheckedContinuation<Void, Never>) in
            listener.stateUpdateHandler = { state in
                if case .cancelled = state {
                    listener.stateUpdateHandler = nil
                    released.resume()
                }
            }
            listener.cancel()
        }
    }
}
