import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// C-CONN-14 and the session's part of C-LIVE-01: turning hierarchy change notifications on
/// and off (P-WATCH-01), and the event, which may come between any two frames (P-WATCH-04).
final class SessionWatchTests: XCTestCase {
    private static func detailsRequest() throws -> GetLayerDetails {
        guard case .getLayerDetails(let request) = try Harness.fixture(
            "watch-hierarchy", "08-c2s-get-layer-details.bin").body
        else { throw CocoaError(.fileReadCorruptFile) }
        return request
    }

    func test_C_CONN_14_theWatchScenarioPlaysThroughTheSession() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake", "watch-hierarchy"))
        let session = try await Harness.readySession(for: server)
        let events = Task { await Harness.events(3, from: session, within: .seconds(5)) }

        _ = try await session.hierarchy()
        let on = try await session.watchHierarchy(true)
        XCTAssertTrue(on)
        // The fixture's client sends the three requests, in this order, before the first
        // answer (P-REQ-06).
        let received = await server.receivedFrames.count
        let three = Task { try await session.subtree(of: 3) }
        let threeSent = await Harness.eventually { await server.receivedFrames.count == received + 1 }
        XCTAssertTrue(threeSent)
        let four = Task { try await session.subtree(of: 4) }
        let fourSent = await Harness.eventually { await server.receivedFrames.count == received + 2 }
        XCTAssertTrue(fourSent)
        let stream = await session.layerDetails(try Self.detailsRequest())
        _ = try await (three.value, four.value)
        // The second event comes between the two chunks of this stream; the stream ends as usual.
        var chunks = 0
        for try await _ in stream.chunks { chunks += 1 }
        XCTAssertEqual(chunks, 2)
        let off = try await session.watchHierarchy(false)
        XCTAssertFalse(off)

        let seen = await events.value
        XCTAssertEqual(seen, [
            .appStateChanged(.active),
            .hierarchyChanged(HierarchyChanged(roots: [3, 4], whole: false)),
            .hierarchyChanged(HierarchyChanged(roots: [], whole: true)),
        ])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    func test_C_CONN_14_anEventOnAOneTwoSessionClosesTheConnection() async throws {
        var steps = try MockScript.fixtures("handshake").serverSpeaking(Version(major: 1, minor: 2)).steps
        steps.append(.send(Frame(
            requestID: 0, body: .hierarchyChanged(HierarchyChanged(roots: [1], whole: false)))))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server)
        let seen = await Harness.events(2, from: session, within: .seconds(5))
        XCTAssertEqual(seen, [.appStateChanged(.active), .closed], "a violation (C-CONN-10)")
        await server.stop()
    }

    func test_C_LIVE_01_aOneTwoSessionSendsNoWatchRequest() async throws {
        let server = try await MockServer.start(
            script: try MockScript.fixtures("handshake").serverSpeaking(Version(major: 1, minor: 2)))
        let session = try await Harness.readySession(for: server)
        do {
            _ = try await session.watchHierarchy(true)
            XCTFail("sent")
        } catch {
            XCTAssertEqual(error as? RequestError, .unsupported)
        }
        let watches = await server.receivedFrames.filter {
            if case .watchHierarchy = $0.body { return true }
            return false
        }
        XCTAssertEqual(watches, [])
        await session.close()
        await server.stop()
    }
}
