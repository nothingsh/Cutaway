import CutawayTransport
import CutawayWire
import Foundation

/// Helpers shared by the transport tests and the tests of MockServer and the fake usbmuxd.
package enum Harness {
    package static let client = ClientInfo(name: "Cutaway", version: "0.4.0")

    package static let demoApp = AppInfo(
        name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.4.0")

    /// One decoded fixture frame.
    package static func fixture(_ scenario: String, _ file: String) throws -> Frame {
        try FrameCodec.decode(try Fixtures.data(scenario: scenario, file: file))
    }

    package static func channel(to server: MockServer) async throws -> ConnectionChannel {
        try await ConnectionChannel.connect(host: "127.0.0.1", port: server.port, timeout: .seconds(2))
    }

    /// Polls `condition` until it holds or `timeout` passes. Returns whether it held.
    package static func eventually(
        within timeout: Duration = .seconds(2), _ condition: @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    /// The first `count` events of a session, or fewer when `timeout` passes first.
    package static func events(
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
    package static func handshakeSteps() throws -> [MockScript.Step] {
        try MockScript.fixtures("handshake").steps
    }
}

/// A client that speaks frames over a raw channel, for testing MockServer without Session.
package struct FrameClient {
    package let channel: ConnectionChannel
    private var reader = FrameReader()

    package init(channel: ConnectionChannel) {
        self.channel = channel
    }

    package func send(_ frame: Frame) async throws {
        try await channel.send(FrameCodec.encodeForStream(frame))
    }

    /// The next frame, or nil when the server closed the connection.
    package mutating func next() async throws -> Frame? {
        while true {
            if let payload = try reader.nextPayload() { return try FrameCodec.decode(payload) }
            guard let bytes = try await channel.receive() else { return nil }
            reader.append(bytes)
        }
    }
}
