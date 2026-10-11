import Foundation
import Network

/// A `ByteChannel` over a Network.framework connection.
package final class ConnectionChannel: ByteChannel {
    private let connection: NWConnection

    /// Wraps a connection that is already started and ready.
    package init(connection: NWConnection) {
        self.connection = connection
    }

    /// Connects to a TCP port.
    package static func connect(
        host: String, port: UInt16, timeout: Duration
    ) async throws -> ConnectionChannel {
        guard let port = NWEndpoint.Port(rawValue: port) else {
            throw ChannelError.connectionFailed("port 0 is not a destination")
        }
        return try await connect(to: .hostPort(host: NWEndpoint.Host(host), port: port), timeout: timeout)
    }

    /// Connects to a Unix domain socket.
    package static func connect(
        unixSocketPath path: String, timeout: Duration
    ) async throws -> ConnectionChannel {
        try await connect(to: .unix(path: path), timeout: timeout)
    }

    private static func connect(
        to endpoint: NWEndpoint, timeout: Duration
    ) async throws -> ConnectionChannel {
        let connection = NWConnection(to: endpoint, using: .tcp)
        // Cancelling a connection that has not started ends its start as a timeout.
        try await StartDeadline.run(
            timeout: timeout, expired: ChannelError.timedOut,
            onExpiry: { connection.cancel() },
            operation: { try await start(connection) })
        return ConnectionChannel(connection: connection)
    }

    /// Starts a connection and returns once it is ready.
    package static func start(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            let gate = ConnectionStartGate()
            connection.stateUpdateHandler = { state in
                guard let outcome = gate.outcome(for: state) else { return }
                connection.stateUpdateHandler = nil
                if case .failure(.connectionFailed) = outcome { connection.cancel() }
                continuation.resume(with: outcome.mapError { $0 })
            }
            connection.start(queue: DispatchQueue(label: "dev.cutaway.channel"))
        }
    }

    package func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    package func receive() async throws -> Data? {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Data?, any Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
                data, _, _, error in
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    // No bytes and no error: the peer closed the connection.
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Tells the peer that no more bytes will come, while still receiving: a TCP half-close.
    /// Closing outright while the peer's bytes are unread resets the connection, and the peer
    /// may then lose what was sent to it.
    package func finishSending() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(
                content: nil, contentContext: .finalMessage, isComplete: true,
                completion: .contentProcessed { _ in continuation.resume() })
        }
    }

    package func close() {
        connection.cancel()
    }
}

/// Decides how starting a connection ends: the first state that ends it does, and every later
/// one is ignored. Removing the state handler is not enough, because Network.framework may
/// already have queued the next state (`waiting` then `failed`, or the `cancelled` that
/// cancelling a failed connection brings).
final class ConnectionStartGate: @unchecked Sendable {
    // Only touched on the connection's queue, which is serial.
    private var isDecided = false

    /// How the start ends for this state, or nil when the state does not end it or the start
    /// has already ended.
    func outcome(for state: NWConnection.State) -> Result<Void, ChannelError>? {
        guard !isDecided else { return nil }
        let outcome: Result<Void, ChannelError>
        switch state {
        case .ready:
            outcome = .success(())
        case .failed(let error), .waiting(let error):
            // "waiting" is how a refused connection shows up; do not wait for a retry.
            outcome = .failure(.connectionFailed("\(error)"))
        case .cancelled:
            outcome = .failure(.timedOut)
        default:
            return nil
        }
        isDecided = true
        return outcome
    }
}
