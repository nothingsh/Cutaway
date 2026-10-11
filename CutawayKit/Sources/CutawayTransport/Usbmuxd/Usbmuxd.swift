import Foundation

/// A device arriving at or leaving usbmuxd. USB devices only.
package enum DeviceEvent: Equatable, Sendable {
    case attached(deviceID: Int, serial: String)
    case detached(deviceID: Int)
}

/// The two things Cutaway asks of usbmuxd.
package enum Usbmuxd {
    package static let defaultSocketPath = "/var/run/usbmuxd"

    /// Device arrivals and departures. Devices that are attached already are reported first.
    /// (That, and the shape of the notifications, follow the protocol's public description and
    /// have not been checked against the real usbmuxd yet.)
    /// The stream ends when the connection to usbmuxd ends or cannot be made.
    package static func deviceEvents(
        socketPath: String, timeout: Duration
    ) -> AsyncStream<DeviceEvent> {
        AsyncStream { continuation in
            let task = Task {
                defer { continuation.finish() }
                guard
                    let channel = try? await ConnectionChannel.connect(
                        unixSocketPath: socketPath, timeout: timeout)
                else { return }
                // A receive that is waiting does not notice task cancellation; closing the
                // channel is what ends it.
                await withTaskCancellationHandler {
                    await listen(on: channel, reportingTo: continuation)
                } onCancel: {
                    channel.close()
                }
                channel.close()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func listen(
        on channel: ConnectionChannel, reportingTo continuation: AsyncStream<DeviceEvent>.Continuation
    ) async {
        var reader = UsbmuxdPacketReader()
        do {
            try await channel.send(UsbmuxdCodec.encode(.listen, tag: 1))
            guard case .result(0) = try await nextIncoming(from: channel, reader: &reader) else {
                return
            }
            while true {
                let packet = try await nextPacket(from: channel, reader: &reader)
                // One message that cannot be read is skipped. Ending the connection instead
                // would make every device's apps leave, and usbmuxd replays the same message
                // on the next connection, so they would leave again every round.
                guard let message = try? UsbmuxdCodec.decodeIncoming(packet.payload) else {
                    continue
                }
                switch message {
                case .attached(let deviceID, let serial, let connectionType):
                    // Devices reached over Wi-Fi are out of scope until v0.9.
                    if connectionType == "USB" {
                        continuation.yield(.attached(deviceID: deviceID, serial: serial))
                    }
                case .detached(let deviceID):
                    continuation.yield(.detached(deviceID: deviceID))
                case .result, .other:
                    break
                }
            }
        } catch {
            // The connection ended, or usbmuxd sent bytes that are not messages at all.
        }
    }

    /// Opens a channel to a TCP port on a device. Each channel takes a connection of its own
    /// to usbmuxd, which becomes the tunnel once usbmuxd answers with success. (The success
    /// path follows the protocol's public description and has not been checked against the real
    /// usbmuxd yet.)
    package static func connect(
        socketPath: String, deviceID: Int, port: UInt16, timeout: Duration
    ) async throws -> any ByteChannel {
        let channel = try await ConnectionChannel.connect(
            unixSocketPath: socketPath, timeout: timeout)
        do {
            // Closing the channel ends the wait for an answer that never comes.
            return try await StartDeadline.run(
                timeout: timeout, expired: ChannelError.timedOut,
                onExpiry: { channel.close() },
                operation: { try await openTunnel(on: channel, deviceID: deviceID, port: port) })
        } catch {
            channel.close()
            throw error
        }
    }

    /// Asks usbmuxd to turn `channel` into a tunnel to the port, and returns the tunnel.
    private static func openTunnel(
        on channel: ConnectionChannel, deviceID: Int, port: UInt16
    ) async throws -> any ByteChannel {
        var reader = UsbmuxdPacketReader()
        try await channel.send(
            UsbmuxdCodec.encode(.connect(deviceID: deviceID, port: port), tag: 1))
        guard case .result(let number) = try await nextIncoming(from: channel, reader: &reader)
        else { throw UsbmuxdError.malformed("the answer to Connect is not a Result") }
        guard number == 0 else { throw UsbmuxdError.refused(number) }

        // From here on the connection carries the device's bytes. Any that arrived
        // together with the Result are handed out first.
        let early = reader.takeRemainder()
        return early.isEmpty ? channel : PrefixedChannel(prefix: early, base: channel)
    }

    /// The next message from usbmuxd on `channel`, decoded.
    private static func nextIncoming(
        from channel: any ByteChannel, reader: inout UsbmuxdPacketReader
    ) async throws -> UsbmuxdIncoming {
        try UsbmuxdCodec.decodeIncoming(try await nextPacket(from: channel, reader: &reader).payload)
    }

    /// The next message from usbmuxd on `channel`, not yet decoded. Throws when the
    /// connection ends or the bytes are not usbmuxd messages at all.
    private static func nextPacket(
        from channel: any ByteChannel, reader: inout UsbmuxdPacketReader
    ) async throws -> UsbmuxdPacket {
        while true {
            if let packet = try reader.next() { return packet }
            let bytes: Data?
            do {
                bytes = try await channel.receive()
            } catch {
                throw UsbmuxdError.closed
            }
            guard let bytes else { throw UsbmuxdError.closed }
            reader.append(bytes)
        }
    }
}
