import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// C-MOCK-01: a local service that replays fixture scenarios over the real protocol.
final class MockServerTests: XCTestCase {
    func test_C_MOCK_01_recordsAMismatchAndClosesTheConnection() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake"))
        var client = FrameClient(channel: try await Harness.channel(to: server))

        // The script expects a Hello first.
        try await client.send(Frame(requestID: 1, body: .getHierarchy))
        let reply = try await client.next()
        XCTAssertNil(reply)

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches.count, 1)
        client.channel.close()
        await server.stop()
    }
}
