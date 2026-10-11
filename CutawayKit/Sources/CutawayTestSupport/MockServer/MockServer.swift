import CutawayTransport
import CutawayWire
import Foundation
import Network

/// A local service that replays a script over the real protocol (C-MOCK-01). Every connection
/// starts the script from the beginning.
public actor MockServer {
    /// The TCP port the server listens on.
    public nonisolated let port: UInt16

    public private(set) var connectionCount = 0
    /// Every frame clients sent, in arrival order, across all connections. Empty when the
    /// server does not record.
    public private(set) var receivedFrames: [Frame] = []
    /// How many frames clients sent, recorded or not.
    public private(set) var receivedFrameCount = 0
    /// The buffer of every frame the server sent, in sending order, across all connections.
    /// Frames sent as raw bytes (`sendBytes`) are not included. Empty when the server does
    /// not record.
    public private(set) var sentPayloads: [Data] = []
    /// What did not match the script. Empty when clients behaved as scripted.
    public private(set) var mismatches: [String] = []
    /// How many connections ended because the client closed them.
    public private(set) var clientCloseCount = 0
    /// Bytes whose sending completed: handed to the system's send buffer, across all
    /// connections. A client that does not read stops it growing (C-CONN-12).
    public private(set) var writtenByteCount = 0

    private let listener: NWListener
    private let script: MockScript
    /// Whether frames are kept in `receivedFrames` and `sentPayloads`. A server for a long
    /// run keeps none, or the test process would hold every screenshot it sent.
    private let records: Bool
    private var channels: [ConnectionChannel] = []
    private var isStopped = false

    private init(listener: NWListener, port: UInt16, script: MockScript, records: Bool) {
        self.listener = listener
        self.port = port
        self.script = script
        self.records = records
    }

    /// Starts listening on loopback. Port 0 picks any free port. A server that does not
    /// `record` keeps no frames, only counts.
    public static func start(
        port: UInt16 = 0, script: MockScript, records: Bool = true
    ) async throws -> MockServer {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback
        let requested = port == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(integerLiteral: port)
        let listener = try NWListener(using: parameters, on: requested)

        let connections = try await ListenerSupport.start(listener, label: "dev.cutaway.mock-server")

        let server = MockServer(
            listener: listener, port: listener.port?.rawValue ?? 0, script: script,
            records: records)
        Task { await server.accept(connections) }
        return server
    }

    /// Stops listening and closes every connection. When it returns, the port is free.
    public func stop() async {
        guard !isStopped else { return }
        isStopped = true
        for channel in channels { channel.close() }
        channels = []
        await ListenerSupport.stop(listener)
    }

    private func accept(_ connections: AsyncStream<NWConnection>) async {
        for await connection in connections {
            connectionCount += 1
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

        var reader = FrameReader()
        var requestIDs: [UInt32: UInt32] = [:]
        do {
            for step in script.steps {
                switch step {
                case .expect(let kind, let scriptID):
                    guard let frame = try await nextFrame(from: channel, reader: &reader) else {
                        mismatches.append("expected \(kind), but the client closed the connection")
                        clientCloseCount += 1
                        channel.close()
                        return
                    }
                    record(frame)
                    let actual = MessageKind(frame.body)
                    guard actual == kind else {
                        mismatches.append("expected \(kind), got \(actual)")
                        await closeGracefully(channel, reader: &reader)
                        return
                    }
                    requestIDs[scriptID] = frame.requestID
                case .send(var frame):
                    frame.requestID = requestIDs[frame.requestID] ?? frame.requestID
                    try await send(frame, on: channel)
                case .sendBytes(let bytes):
                    try await channel.send(bytes)
                    writtenByteCount += bytes.count
                case .sendMany(let count, let make):
                    for index in 0..<count {
                        var frame = make(index)
                        frame.requestID = requestIDs[frame.requestID] ?? frame.requestID
                        let bytes = FrameCodec.encodeForStream(frame)
                        try await channel.send(bytes)
                        writtenByteCount += bytes.count
                    }
                case .pause(let duration):
                    try await Task.sleep(for: duration)
                case .hold(let gate):
                    await gate.wait()
                case .close:
                    await closeGracefully(channel, reader: &reader)
                    return
                case .respond(let responder):
                    try await respond(with: responder, on: channel, reader: &reader)
                    return
                }
            }
            if script.closesWhenDone {
                await closeGracefully(channel, reader: &reader)
                return
            }
            // The script is over. Stay until the client leaves and record what it still sends.
            while let frame = try await nextFrame(from: channel, reader: &reader) {
                record(frame)
            }
            clientCloseCount += 1
            channel.close()
        } catch {
            // The connection failed. Unless this server ended it, the client did: a client
            // that closes with bytes still unread resets the connection instead of ending it.
            if !isStopped { clientCloseCount += 1 }
            channel.close()
        }
    }

    private func record(_ frame: Frame) {
        receivedFrameCount += 1
        if records { receivedFrames.append(frame) }
    }

    /// Sends one frame and records its buffer.
    private func send(_ frame: Frame, on channel: ConnectionChannel) async throws {
        let payload = FrameCodec.encode(frame)
        if records { sentPayloads.append(payload) }
        var bytes = withUnsafeBytes(of: UInt32(payload.count).littleEndian) { Data($0) }
        bytes.append(payload)
        try await channel.send(bytes)
        writtenByteCount += bytes.count
    }

    /// Answers each frame by its content until the client leaves (`MockResponder`).
    private func respond(
        with responder: MockResponder, on channel: ConnectionChannel, reader: inout FrameReader
    ) async throws {
        var responder = responder
        var detailRequests = 0
        var heldOnce = false
        while let frame = try await nextFrame(from: channel, reader: &reader) {
            record(frame)
            let id = frame.requestID
            switch frame.body {
            case .getAppIcon:
                try await send(Frame(requestID: id, body: .appIcon(responder.icon)), on: channel)
            case .getHierarchy:
                try await send(
                    Frame(requestID: id, body: .hierarchy(responder.hierarchy)), on: channel)
            case .getSubtree(let request):
                let body: Body = responder.subtree(of: request.rootID).map { .hierarchy($0) }
                    ?? .error(ServerError(code: .layerNotFound, message: nil))
                try await send(Frame(requestID: id, body: body), on: channel)
            case .setAttribute(let request):
                try await send(Frame(requestID: id, body: responder.edit(request)), on: channel)
            case .getLayerDetails(let request):
                detailRequests += 1
                if let (count, gate) = responder.holdBeforeDetailsRequest, count == detailRequests {
                    await gate.wait()
                }
                if !heldOnce, let (matches, gate) = responder.holdBeforeDetails, matches(request) {
                    heldOnce = true
                    await gate.wait()
                }
                let failure: MockResponder.Failure? =
                    if let (count, failure) = responder.failDetailsRequest, count == detailRequests {
                        failure
                    } else if let (matches, failure) = responder.failDetails, matches(request) {
                        failure
                    } else {
                        nil
                    }
                if let failure {
                    switch failure {
                    case .disconnect:
                        await closeGracefully(channel, reader: &reader)
                        return
                    case .appNotActive:
                        try await send(
                            Frame(requestID: id, body: .streamEnd(StreamEnd(
                                status: .failed, chunkCount: 0,
                                error: ServerError(code: .appNotActive, message: nil)))),
                            on: channel)
                    }
                    continue
                }
                let chunks = responder.answerChunks(request)
                for (sequence, details) in chunks.enumerated() {
                    let chunk = LayerDetailsChunk(sequence: UInt32(sequence), details: details)
                    try await send(Frame(requestID: id, body: .layerDetailsChunk(chunk)), on: channel)
                }
                try await send(
                    Frame(requestID: id, body: .streamEnd(StreamEnd(
                        status: .completed, chunkCount: UInt32(chunks.count), error: nil))),
                    on: channel)
            case .cancel:
                // Every stream ended before the next frame was read.
                continue
            default:
                mismatches.append("cannot answer \(MessageKind(frame.body))")
            }
        }
        clientCloseCount += 1
        channel.close()
    }

    private func nextFrame(
        from channel: ConnectionChannel, reader: inout FrameReader
    ) async throws -> Frame? {
        while true {
            if let payload = try reader.nextPayload() { return try FrameCodec.decode(payload) }
            guard let bytes = try await channel.receive() else { return nil }
            reader.append(bytes)
        }
    }

    /// Closes without resetting the connection: half-closes, reads until the client closes
    /// its side (for at most a second), then closes. A client that had bytes on the way still
    /// receives everything that was sent to it.
    private func closeGracefully(_ channel: ConnectionChannel, reader: inout FrameReader) async {
        await channel.finishSending()
        let start = ContinuousClock.now
        let limit = Task {
            try await Task.sleep(for: .seconds(1))
            channel.close()
        }
        do {
            while let frame = try await nextFrame(from: channel, reader: &reader) {
                record(frame)
            }
            // The client closed its side before the limit ran out.
            clientCloseCount += 1
        } catch {
            // Either the client reset the connection, or the limit closed it.
            if !isStopped, ContinuousClock.now - start < .milliseconds(900) {
                clientCloseCount += 1
            }
        }
        limit.cancel()
        channel.close()
    }
}
