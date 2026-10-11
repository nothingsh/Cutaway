import CutawayTestSupport
import CutawayTransport
import CutawayWire
import Foundation
import XCTest

/// Helpers shared by the transport tests.
enum Harness {
    static let client = ClientInfo(name: "Cutaway", version: "0.4.0")

    static let demoApp = AppInfo(
        name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.4.0")

    /// One decoded fixture frame.
    static func fixture(_ scenario: String, _ file: String) throws -> Frame {
        try FrameCodec.decode(try Fixtures.data(scenario: scenario, file: file))
    }

    static func channel(to server: MockServer) async throws -> ConnectionChannel {
        try await ConnectionChannel.connect(host: "127.0.0.1", port: server.port, timeout: .seconds(2))
    }

    /// Polls `condition` until it holds or `timeout` passes. Returns whether it held.
    static func eventually(
        within timeout: Duration = .seconds(2), _ condition: @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    static func session(
        for server: MockServer, protocolVersion: Version = ProtocolVersion.current,
        client: ClientInfo = client, requestTimeout: Duration = .seconds(2)
    ) async throws -> Session {
        Session(
            channel: try await channel(to: server), client: client,
            protocolVersion: protocolVersion, requestTimeout: requestTimeout)
    }

    /// A session that has completed the handshake.
    static func readySession(
        for server: MockServer, protocolVersion: Version = ProtocolVersion.current,
        requestTimeout: Duration = .seconds(2), file: StaticString = #filePath, line: UInt = #line
    ) async throws -> Session {
        let session = try await session(
            for: server, protocolVersion: protocolVersion, requestTimeout: requestTimeout)
        let outcome = try await session.handshake()
        guard case .ready = outcome else {
            XCTFail("handshake ended as \(outcome)", file: file, line: line)
            throw RequestError.disconnected
        }
        return session
    }

    /// The first `count` events of a session, or fewer when `timeout` passes first.
    static func events(
        _ count: Int, from session: Session, within timeout: Duration = .seconds(2)
    ) async -> [SessionEvent] {
        let collector = Task {
            var events: [SessionEvent] = []
            for await event in session.events {
                events.append(event)
                if events.count == count { break }
            }
            return events
        }
        let limit = Task {
            try await Task.sleep(for: timeout)
            collector.cancel()
        }
        let events = await collector.value
        limit.cancel()
        return events
    }

    /// The steps of the handshake scenario, to put in front of hand-written steps.
    static func handshakeSteps() throws -> [MockScript.Step] {
        try MockScript.fixtures("handshake").steps
    }
}

/// A client that speaks frames over a raw channel, for testing MockServer without Session.
struct FrameClient {
    let channel: ConnectionChannel
    private var reader = FrameReader()

    init(channel: ConnectionChannel) {
        self.channel = channel
    }

    func send(_ frame: Frame) async throws {
        try await channel.send(FrameCodec.encodeForStream(frame))
    }

    /// The next frame, or nil when the server closed the connection.
    mutating func next() async throws -> Frame? {
        while true {
            if let payload = try reader.nextPayload() { return try FrameCodec.decode(payload) }
            guard let bytes = try await channel.receive() else { return nil }
            reader.append(bytes)
        }
    }
}
