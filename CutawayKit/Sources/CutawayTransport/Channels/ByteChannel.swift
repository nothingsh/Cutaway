import Foundation

/// A reliable, ordered stream of bytes to one peer. A session does not care whether the bytes
/// travel over loopback TCP or through usbmuxd to a device.
package protocol ByteChannel: Sendable {
    /// Sends all of `data`.
    func send(_ data: Data) async throws

    /// The next bytes from the peer, at least one. Nil when the peer closed the connection.
    /// Throws when the connection failed or was closed from this side.
    func receive() async throws -> Data?

    /// Closes the connection. A `receive` that is waiting then throws.
    func close()
}

package enum ChannelError: Error, Equatable {
    /// The connection could not be made. The text is for logs.
    case connectionFailed(String)
    case timedOut
}
