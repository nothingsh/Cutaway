import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// C-MOCK-01: a local service that replays fixture scenarios over the real protocol.
final class MockServerTests: XCTestCase {
    private func clientHello() throws -> Frame {
        try Harness.fixture("handshake", "01-c2s-hello.bin")
    }

    func test_C_MOCK_01_replaysAScenarioAndUsesTheClientsRequestIDs() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake", "app-icon"))
        var client = FrameClient(channel: try await Harness.channel(to: server))

        try await client.send(try clientHello())
        let hello = try await client.next()
        XCTAssertEqual(hello, try Harness.fixture("handshake", "02-s2c-hello.bin"))
        let state = try await client.next()
        XCTAssertEqual(state, Frame(requestID: 0, body: .appStateChanged(.active)))

        // The fixture uses request ID 1; this client uses 41.
        try await client.send(Frame(requestID: 41, body: .getAppIcon))
        let icon = try await client.next()
        XCTAssertEqual(icon?.requestID, 41)
        XCTAssertEqual(icon?.body, try Harness.fixture("app-icon", "02-s2c-app-icon.bin").body)

        client.channel.close()
        await server.stop()
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
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

    func test_C_MOCK_01_everyConnectionStartsFromTheBeginning() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake"))
        for _ in 0..<2 {
            var client = FrameClient(channel: try await Harness.channel(to: server))
            try await client.send(try clientHello())
            let hello = try await client.next()
            XCTAssertEqual(hello, try Harness.fixture("handshake", "02-s2c-hello.bin"))
            client.channel.close()
        }
        let reached = await Harness.eventually { await server.connectionCount == 2 }
        XCTAssertTrue(reached)
        await server.stop()
    }

    func test_C_MOCK_01_staysConnectedAfterTheScriptAndRecordsFurtherFrames() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake"))
        var client = FrameClient(channel: try await Harness.channel(to: server))
        try await client.send(try clientHello())
        _ = try await client.next()
        _ = try await client.next()

        // The script is over. The connection stays open and further frames are recorded.
        try await client.send(Frame(requestID: 1, body: .getAppIcon))
        let recorded = await Harness.eventually { await server.receivedFrames.count == 2 }
        XCTAssertTrue(recorded)
        let frames = await server.receivedFrames
        XCTAssertEqual(frames.last, Frame(requestID: 1, body: .getAppIcon))

        client.channel.close()
        await server.stop()
    }

    func test_C_MOCK_01_closesAfterTheScriptWhenAskedTo() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("busy", closesWhenDone: true))
        var client = FrameClient(channel: try await Harness.channel(to: server))

        let error = try await client.next()
        XCTAssertEqual(error, try Harness.fixture("busy", "01-s2c-error.bin"))
        let end = try await client.next()
        XCTAssertNil(end)

        client.channel.close()
        await server.stop()
    }

    func test_C_MOCK_01_listensOnTheRequestedPort() async throws {
        // Port 0 asks for any free port.
        let first = try await MockServer.start(script: MockScript(steps: []))
        let port = first.port
        XCTAssertNotEqual(port, 0)
        await first.stop()

        // The same port, now asked for by number.
        let second = try await MockServer.start(port: port, script: try .fixtures("handshake"))
        XCTAssertEqual(second.port, port)
        var client = FrameClient(channel: try await Harness.channel(to: second))
        try await client.send(try clientHello())
        let hello = try await client.next()
        XCTAssertNotNil(hello)
        client.channel.close()
        await second.stop()
    }

    func test_C_MOCK_01_aStoppedServersPortIsFreeAtOnce() async throws {
        let first = try await MockServer.start(script: MockScript(steps: []))
        let port = first.port
        await first.stop()
        // Stop and start again on the same port, many times, with nothing in between.
        for round in 0..<200 {
            do {
                let server = try await MockServer.start(port: port, script: MockScript(steps: []))
                await server.stop()
            } catch {
                XCTFail("round \(round): \(error)")
                return
            }
        }
    }

    func test_C_MOCK_01_reportsWhenAClientCloses() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake"))
        var client = FrameClient(channel: try await Harness.channel(to: server))
        try await client.send(try clientHello())
        _ = try await client.next()
        let before = await server.clientCloseCount
        XCTAssertEqual(before, 0)

        client.channel.close()

        let seen = await Harness.eventually { await server.clientCloseCount == 1 }
        XCTAssertTrue(seen)
        await server.stop()
    }

    func test_C_MOCK_01_scriptsCanSendRawBytesAndPause() async throws {
        let server = try await MockServer.start(script: MockScript(steps: [
            .pause(.milliseconds(20)),
            .sendBytes(Data([0x01, 0x02, 0x03])),
            .close,
        ]))
        let channel = try await Harness.channel(to: server)
        let bytes = try await channel.receive()
        XCTAssertEqual(bytes, Data([0x01, 0x02, 0x03]))
        let end = try await channel.receive()
        XCTAssertNil(end)
        channel.close()
        await server.stop()
    }

    func test_C_MOCK_01_aHoldStepWaitsForItsGate() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake").steps
        steps.insert(.hold(gate), at: 2)  // between the Hello and the app state
        let server = try await MockServer.start(script: MockScript(steps: steps))
        var client = FrameClient(channel: try await Harness.channel(to: server))

        try await client.send(try clientHello())
        let hello = try await client.next()
        XCTAssertEqual(hello, try Harness.fixture("handshake", "02-s2c-hello.bin"))

        let started = ContinuousClock.now
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await gate.open()
        }
        let state = try await client.next()
        XCTAssertEqual(state, Frame(requestID: 0, body: .appStateChanged(.active)))
        XCTAssertGreaterThanOrEqual(ContinuousClock.now - started, .milliseconds(300))

        client.channel.close()
        await server.stop()
    }

    func test_C_MOCK_01_aGateOpenedEarlyDoesNotHold() async throws {
        let gate = MockGate()
        await gate.open()
        var steps = try MockScript.fixtures("handshake").steps
        steps.insert(.hold(gate), at: 2)
        let server = try await MockServer.start(script: MockScript(steps: steps))
        var client = FrameClient(channel: try await Harness.channel(to: server))

        try await client.send(try clientHello())
        _ = try await client.next()
        let state = try await client.next()
        XCTAssertEqual(state, Frame(requestID: 0, body: .appStateChanged(.active)))

        client.channel.close()
        await server.stop()
    }

    // MARK: - Answering by content

    private func respondingServer(_ responder: MockResponder) async throws -> MockServer {
        try await MockServer.start(
            script: MockScript(steps: try Harness.handshakeSteps() + [.respond(responder)]))
    }

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

    func test_C_MOCK_01_aResponderAnswersDetailsByContent() async throws {
        let responder = try MockResponder.demo()
        let server = try await respondingServer(responder)
        var client = FrameClient(channel: try await Harness.channel(to: server))
        try await handshake(&client)

        let icon = try await answer(to: Frame(requestID: 7, body: .getAppIcon), client: &client)
        XCTAssertEqual(icon.map(\.requestID), [7])
        XCTAssertEqual(icon.first?.body, .appIcon(responder.icon))

        let tree = try await answer(to: Frame(requestID: 8, body: .getHierarchy), client: &client)
        XCTAssertEqual(tree.first?.body, .hierarchy(try Fixtures.hierarchy()))

        // Any layers, in any order, with only what was asked for; an unknown layer is gone.
        let request = GetLayerDetails(
            requests: [
                LayerDetailRequest(layerID: 4, wantSolo: true, wantGroup: false, wantAttributes: false),
                LayerDetailRequest(
                    layerID: 3, wantSolo: false, wantGroup: true, wantAttributes: true,
                    wantConstraints: true),
                LayerDetailRequest(layerID: 77, wantSolo: true, wantGroup: true, wantAttributes: true),
            ],
            maxTextureDimension: 0)
        let frames = try await answer(
            to: Frame(requestID: 9, body: .getLayerDetails(request)), client: &client)
        XCTAssertEqual(frames.map(\.requestID), [9, 9])
        guard case .layerDetailsChunk(let chunk) = frames.first?.body else {
            XCTFail("no chunk")
            return
        }
        XCTAssertEqual(chunk.details.map(\.layerID), [4, 3, 77])
        let full4 = try XCTUnwrap(responder.details[4])
        let full3 = try XCTUnwrap(responder.details[3])
        XCTAssertEqual(chunk.details[0].solo, full4.solo)
        XCTAssertNotNil(chunk.details[0].solo)
        XCTAssertNil(chunk.details[0].group)
        XCTAssertEqual(chunk.details[0].attributeGroups, [])
        XCTAssertNil(chunk.details[1].solo)
        XCTAssertEqual(chunk.details[1].group, full3.group)
        XCTAssertEqual(chunk.details[1].attributeGroups, full3.attributeGroups)
        XCTAssertEqual(chunk.details[1].constraints, try Fixtures.constraints(of: 3))
        XCTAssertEqual(chunk.details[2].status, .layerNotFound)
        XCTAssertEqual(
            frames.last?.body, .streamEnd(StreamEnd(status: .completed, chunkCount: 1, error: nil)))

        let received = await server.receivedFrames
        XCTAssertEqual(received.count, 4)
        client.channel.close()
        await server.stop()
    }

    func test_C_MOCK_01_aResponderCanHoldBeforeARequest() async throws {
        let gate = MockGate()
        var responder = try MockResponder.demo()
        responder.holdBeforeDetailsRequest = (2, gate)
        let server = try await respondingServer(responder)
        var client = FrameClient(channel: try await Harness.channel(to: server))
        try await handshake(&client)

        let request = GetLayerDetails(
            requests: [LayerDetailRequest(layerID: 3, wantSolo: true, wantGroup: false, wantAttributes: false)],
            maxTextureDimension: 0)
        let first = try await answer(
            to: Frame(requestID: 1, body: .getLayerDetails(request)), client: &client)
        XCTAssertEqual(first.count, 2)

        try await client.send(Frame(requestID: 2, body: .getLayerDetails(request)))
        let held = Task { [client] in
            var client = client
            return try await client.next()
        }
        try await Task.sleep(for: .milliseconds(100))
        let receivedWhileHeld = await server.receivedFrames.count
        XCTAssertEqual(receivedWhileHeld, 3, "Hello and two requests")
        await gate.open()
        let afterGate = try await held.value
        XCTAssertEqual(afterGate?.requestID, 2)

        client.channel.close()
        await server.stop()
    }

    func test_C_MOCK_01_aResponderCanFailARequest() async throws {
        var responder = try MockResponder.demo()
        responder.failDetailsRequest = (1, .appNotActive)
        let server = try await respondingServer(responder)
        var client = FrameClient(channel: try await Harness.channel(to: server))
        try await handshake(&client)

        let request = GetLayerDetails(
            requests: [LayerDetailRequest(layerID: 3, wantSolo: true, wantGroup: false, wantAttributes: false)],
            maxTextureDimension: 0)
        let frames = try await answer(
            to: Frame(requestID: 5, body: .getLayerDetails(request)), client: &client)
        guard case .streamEnd(let end) = frames.last?.body else {
            XCTFail("no end")
            return
        }
        XCTAssertEqual(end.status, .failed)
        XCTAssertEqual(end.error?.code, .appNotActive)

        client.channel.close()
        await server.stop()

        var closing = try MockResponder.demo()
        closing.failDetailsRequest = (1, .disconnect)
        let closer = try await respondingServer(closing)
        var other = FrameClient(channel: try await Harness.channel(to: closer))
        try await handshake(&other)
        try await other.send(Frame(requestID: 1, body: .getLayerDetails(request)))
        let reply = try await other.next()
        XCTAssertNil(reply, "the server closes the connection")
        other.channel.close()
        await closer.stop()
    }
}
