import CutawayTransport
import Foundation
import Network

/// A device as the fake usbmuxd presents it.
public struct FakeDevice: Equatable, Sendable {
    public var deviceID: Int
    public var serial: String
    /// A port on the device → the local TCP port that plays the app listening there.
    public var ports: [UInt16: UInt16]
    /// "USB" or "Network".
    public var connectionType: String

    public init(
        deviceID: Int, serial: String, ports: [UInt16: UInt16], connectionType: String = "USB"
    ) {
        self.deviceID = deviceID
        self.serial = serial
        self.ports = ports
        self.connectionType = connectionType
    }
}

/// A stand-in for usbmuxd on a temporary Unix socket (C-MOCK-02). It answers Listen, reports
/// devices coming and going, and forwards Connect to a local TCP port.
public actor FakeUsbmuxd {
    public struct ConnectRequest: Equatable, Sendable {
        public var deviceID: Int
        public var port: UInt16

        public init(deviceID: Int, port: UInt16) {
            self.deviceID = deviceID
            self.port = port
        }
    }

    /// Give this to the code under test in place of `/var/run/usbmuxd`.
    public nonisolated let socketPath: String

    /// Every Connect that arrived, in order.
    public private(set) var connectRequests: [ConnectRequest] = []
    /// How many connections are in the listening state now.
    public var listenerCount: Int { listening.count }

    private let listener: NWListener
    private var devices: [Int: FakeDevice] = [:]
    private var listening: [ConnectionChannel] = []
    private var tunnels: [Int: [ConnectionChannel]] = [:]
    private var channels: [ConnectionChannel] = []
    private var isStopped = false

    private init(listener: NWListener, socketPath: String) {
        self.listener = listener
        self.socketPath = socketPath
    }

    /// Starts listening. Without a path, a fresh one in the temporary directory is used; pass
    /// one to come back on the path of an instance that was stopped.
    public static func start(socketPath: String? = nil) async throws -> FakeUsbmuxd {
        // Short, because a Unix socket path holds about a hundred bytes.
        let path = socketPath ?? NSTemporaryDirectory()
            + "cutaway-usbmuxd-\(getpid())-\(UInt32.random(in: 0...UInt32.max)).sock"
        unlink(path)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.unix(path: path)
        let listener = try NWListener(using: parameters)
        let connections = try await ListenerSupport.start(
            listener, label: "dev.cutaway.fake-usbmuxd")

        let fake = FakeUsbmuxd(listener: listener, socketPath: path)
        Task { await fake.accept(connections) }
        return fake
    }

    /// Plugs a device in: every listening client is told.
    public func attach(_ device: FakeDevice) async {
        devices[device.deviceID] = device
        let message = Self.attached(device)
        for channel in listening {
            try? await channel.send(message)
        }
    }

    /// Unplugs a device: every listening client is told, and its tunnels end. Passing false
    /// for `closingTunnels` leaves them open, to model a detach notification that overtakes
    /// the end of a connection still in use.
    public func detach(deviceID: Int, closingTunnels: Bool = true) async {
        guard devices.removeValue(forKey: deviceID) != nil else { return }
        if closingTunnels {
            for channel in tunnels.removeValue(forKey: deviceID) ?? [] {
                channel.close()
            }
        }
        let message = UsbmuxdCodec.encode(.detached(deviceID: deviceID), tag: 0)
        for channel in listening {
            try? await channel.send(message)
        }
    }

    /// Sends bytes as they are to every listening client: for messages the fake does not
    /// produce itself, such as one usbmuxd might send malformed.
    public func sendToListeners(raw message: Data) async {
        for channel in listening {
            try? await channel.send(message)
        }
    }

    /// Stops listening and closes every connection. When it returns, the socket path is free.
    public func stop() async {
        guard !isStopped else { return }
        isStopped = true
        for channel in channels { channel.close() }
        channels = []
        listening = []
        tunnels = [:]
        await ListenerSupport.stop(listener)
        unlink(socketPath)
    }

    private static func attached(_ device: FakeDevice) -> Data {
        UsbmuxdCodec.encode(
            .attached(
                deviceID: device.deviceID, serial: device.serial,
                connectionType: device.connectionType),
            tag: 0)
    }

    private func accept(_ connections: AsyncStream<NWConnection>) async {
        for await connection in connections {
            Task { await self.serve(connection) }
        }
    }

    private func serve(_ connection: NWConnection) async {
        do {
            try await ConnectionChannel.start(connection)
        } catch {
            return
        }
        let channel = ConnectionChannel(connection: connection)
        channels.append(channel)

        var reader = UsbmuxdPacketReader()
        do {
            guard let packet = try await nextPacket(from: channel, reader: &reader) else {
                channel.close()
                return
            }
            switch try UsbmuxdCodec.decodeRequest(packet.payload) {
            case .listen:
                try await channel.send(UsbmuxdCodec.encode(.result(0), tag: packet.tag))
                // Devices that are attached already are reported first.
                for device in devices.values.sorted(by: { $0.deviceID < $1.deviceID }) {
                    try await channel.send(Self.attached(device))
                }
                listening.append(channel)
                // Stay until the client leaves.
                while try await channel.receive() != nil {}
                listening.removeAll { $0 === channel }
                channel.close()

            case .connect(let deviceID, let port):
                connectRequests.append(ConnectRequest(deviceID: deviceID, port: port))
                guard let device = devices[deviceID] else {
                    try await channel.send(UsbmuxdCodec.encode(.result(2), tag: packet.tag))
                    channel.close()
                    return
                }
                guard let localPort = device.ports[port],
                      let upstream = try? await ConnectionChannel.connect(
                          host: "127.0.0.1", port: localPort, timeout: .seconds(1))
                else {
                    try await channel.send(UsbmuxdCodec.encode(.result(3), tag: packet.tag))
                    channel.close()
                    return
                }
                channels.append(upstream)
                tunnels[deviceID, default: []] += [channel, upstream]
                try await channel.send(UsbmuxdCodec.encode(.result(0), tag: packet.tag))
                let early = reader.takeRemainder()
                if !early.isEmpty { try await upstream.send(early) }
                await Self.pipe(channel, upstream)
            }
        } catch {
            listening.removeAll { $0 === channel }
            channel.close()
        }
    }

    private func nextPacket(
        from channel: ConnectionChannel, reader: inout UsbmuxdPacketReader
    ) async throws -> UsbmuxdPacket? {
        while true {
            if let packet = try reader.next() { return packet }
            guard let bytes = try await channel.receive() else { return nil }
            reader.append(bytes)
        }
    }

    /// Copies bytes both ways until both sides have finished.
    private static func pipe(_ client: ConnectionChannel, _ device: ConnectionChannel) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await copy(from: client, to: device) }
            group.addTask { await copy(from: device, to: client) }
        }
        client.close()
        device.close()
    }

    private static func copy(from source: ConnectionChannel, to destination: ConnectionChannel) async {
        while let bytes = try? await source.receive() {
            guard (try? await destination.send(bytes)) != nil else { return }
        }
        // The source finished: pass that on, and let the other direction run to its own end.
        await destination.finishSending()
    }
}
