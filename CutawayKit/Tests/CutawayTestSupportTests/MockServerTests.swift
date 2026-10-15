import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// C-MOCK-01: a local service that replays fixture scenarios over the real protocol.
final class MockServerTests: XCTestCase {
    private func clientHello() throws -> Frame {
        try Harness.fixture("handshake", "01-c2s-hello.bin")
    }

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

    // MARK: - Answering by content

    /// Sends a request and collects the frames that answer it, up to the end of a stream.
    private func answer(
        to frame: Frame, client: inout FrameClient
    ) async throws -> [Frame] {
        try await client.send(frame)
        var frames: [Frame] = []
        while let next = try await client.next() {
            frames.append(next)
            switch next.body {
            case .layerDetailsChunk: continue
            default: return frames
            }
        }
        return frames
    }

    private func handshake(_ client: inout FrameClient) async throws {
        try await client.send(try clientHello())
        _ = try await client.next()
        _ = try await client.next()
    }
}
