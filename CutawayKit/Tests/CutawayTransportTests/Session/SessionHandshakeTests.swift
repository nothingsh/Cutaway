import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// C-CONN-03: the handshake.
final class SessionHandshakeTests: XCTestCase {
    func test_C_CONN_03_protocolVersionMatchesThePinnedProtocol() throws {
        let url = Fixtures.repositoryRoot.appendingPathComponent("Protocol/PROTOCOL_VERSION")
        let text = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(
            "\(ProtocolVersion.current.major).\(ProtocolVersion.current.minor)", text)
    }

    func test_C_CONN_03_handshakeYieldsTheAppInfo() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake"))
        let session = try await Harness.session(for: server)

        let outcome = try await session.handshake()
        XCTAssertEqual(
            outcome, .ready(Harness.demoApp, negotiated: Version(major: 1, minor: 2)))

        // What the client sent is exactly the fixture's Hello.
        let received = await server.receivedFrames
        XCTAssertEqual(received, [try Harness.fixture("handshake", "01-c2s-hello.bin")])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    func test_C_CONN_03_aDifferentMajorVersionFailsTheHandshake() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake-version-mismatch", closesWhenDone: true))
        // The fixture's client speaks protocol 1.0 and calls itself 0.1.0; the server answers
        // with 0.5.
        let session = try await Harness.session(
            for: server, protocolVersion: Version(major: 1, minor: 0),
            client: ClientInfo(name: "Cutaway", version: "0.1.0"))

        let outcome = try await session.handshake()
        XCTAssertEqual(
            outcome,
            .incompatible(
                local: Version(major: 1, minor: 0), remote: Version(major: 0, minor: 5),
                app: Harness.demoApp))

        // The client closed the connection and sent nothing but its Hello.
        let events = await Harness.events(1, from: session)
        XCTAssertEqual(events, [.closed])
        let closed = await Harness.eventually(within: .milliseconds(700)) {
            await server.clientCloseCount == 1
        }
        XCTAssertTrue(closed, "the client did not close the connection")
        // Keeps the session alive up to here: releasing it would close the connection too.
        withExtendedLifetime(session) {}
        let received = await server.receivedFrames
        XCTAssertEqual(
            received, [try Harness.fixture("handshake-version-mismatch", "01-c2s-hello.bin")])

        await server.stop()
    }

    func test_C_CONN_03_aLowerMinorVersionIsNegotiatedDown() async throws {
        var hello = try Harness.fixture("handshake", "02-s2c-hello.bin")
        guard case .hello(var body) = hello.body else {
            XCTFail("not a Hello")
            return
        }
        // A 1.0 server, and this client speaks a later 1.x.
        XCTAssertGreaterThan(ProtocolVersion.current.minor, 0)
        body.protocolVersion = Version(major: 1, minor: 0)
        hello.body = .hello(body)
        let server = try await MockServer.start(script: MockScript(steps: [
            .expect(.hello, as: 0), .send(hello),
        ]))
        let session = try await Harness.session(for: server)

        let outcome = try await session.handshake()
        XCTAssertEqual(
            outcome, .ready(Harness.demoApp, negotiated: Version(major: 1, minor: 0)))

        await session.close()
        await server.stop()
    }

    func test_C_CONN_09_aBusyServerIsReportedAsBusy() async throws {
        // The server answers at once and closes while the client's Hello is still on its way.
        // Repeated, because the outcome must not depend on which side is faster.
        for round in 0..<20 {
            let server = try await MockServer.start(
                script: try .fixtures("busy", closesWhenDone: true))
            let session = try await Harness.session(for: server)
            let outcome = try await session.handshake()
            XCTAssertEqual(outcome, .busy, "round \(round)")
            await server.stop()
        }
    }

    func test_C_CONN_03_aSilentServerTimesOut() async throws {
        let server = try await MockServer.start(script: MockScript(steps: [
            .expect(.hello, as: 0),
        ]))
        let session = try await Harness.session(for: server, requestTimeout: .milliseconds(200))

        do {
            _ = try await session.handshake()
            XCTFail("the handshake did not time out")
        } catch {
            XCTAssertEqual(error as? RequestError, .timedOut)
        }
        await server.stop()
    }

    func test_C_CONN_03_aServerThatClosesFailsTheHandshake() async throws {
        let server = try await MockServer.start(script: MockScript(steps: [
            .expect(.hello, as: 0), .close,
        ]))
        let session = try await Harness.session(for: server)

        do {
            _ = try await session.handshake()
            XCTFail("the handshake did not fail")
        } catch {
            XCTAssertEqual(error as? RequestError, .disconnected)
        }
        await server.stop()
    }

    func test_C_CONN_03_anythingButAHelloFailsTheHandshake() async throws {
        let server = try await MockServer.start(script: MockScript(steps: [
            .expect(.hello, as: 0),
            .send(Frame(requestID: 0, body: .appStateChanged(.active))),
        ]))
        let session = try await Harness.session(for: server)

        do {
            _ = try await session.handshake()
            XCTFail("the handshake did not fail")
        } catch {
            guard case .protocolViolation = error as? RequestError else {
                XCTFail("threw \(error)")
                return
            }
        }
        await server.stop()
    }

    // MARK: - An answer that arrives after the session ended

    /// The server's Hello, as bytes on the wire.
    private func helloBytes() throws -> Data {
        FrameCodec.encodeForStream(try Harness.fixture("handshake", "02-s2c-hello.bin"))
    }

    /// Runs a handshake over `channel` until a receive waits, then calls `interrupt`, then
    /// hands over `bytes`. Returns how the handshake ended.
    private func handshake(
        over channel: GatedChannel, requestTimeout: Duration = .seconds(10), delivering bytes: Data,
        after interrupt: (Session) async -> Void
    ) async -> Result<HandshakeOutcome, RequestError> {
        let session = Session(
            channel: channel, client: Harness.client, requestTimeout: requestTimeout)
        let handshake = Task { try await session.handshake() }
        let receiving = await Harness.eventually { await channel.isReceiving }
        XCTAssertTrue(receiving, "the handshake never waited for bytes")
        await interrupt(session)
        await channel.deliver(bytes)
        do {
            return .success(try await handshake.value)
        } catch {
            return .failure(error as? RequestError ?? .protocolViolation("\(error)"))
        }
    }

    func test_C_CONN_03_aHelloThatArrivesAfterCloseDoesNotMakeTheSessionReady() async throws {
        let channel = GatedChannel()
        let result = await handshake(over: channel, delivering: try helloBytes()) { session in
            await session.close()
        }
        XCTAssertEqual(result, .failure(.disconnected))
    }

    func test_C_CONN_03_aHelloThatArrivesAfterTheTimeoutDoesNotMakeTheSessionReady() async throws {
        let channel = GatedChannel()
        let result = await handshake(
            over: channel, requestTimeout: .milliseconds(50), delivering: try helloBytes()
        ) { _ in
            let expired = await Harness.eventually { await channel.closeCount == 1 }
            XCTAssertTrue(expired, "the handshake did not time out")
        }
        XCTAssertEqual(result, .failure(.timedOut))
    }

    func test_C_CONN_03_aBusyAnswerThatArrivesAfterTheTimeoutIsATimeout() async throws {
        let channel = GatedChannel()
        let busy = FrameCodec.encodeForStream(try Harness.fixture("busy", "01-s2c-error.bin"))
        let result = await handshake(
            over: channel, requestTimeout: .milliseconds(50), delivering: busy
        ) { _ in
            let expired = await Harness.eventually { await channel.closeCount == 1 }
            XCTAssertTrue(expired, "the handshake did not time out")
        }
        XCTAssertEqual(result, .failure(.timedOut))
    }
}
