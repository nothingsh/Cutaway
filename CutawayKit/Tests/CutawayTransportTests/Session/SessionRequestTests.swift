import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// C-CONN-04, C-CONN-07, C-CONN-08 and C-CONN-10 at the level of one session.
final class SessionRequestTests: XCTestCase {
    private func assertThrows(
        _ expected: RequestError, file: StaticString = #filePath, line: UInt = #line,
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("did not throw", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? RequestError, expected, file: file, line: line)
        }
    }

    // MARK: - C-CONN-04

    func test_C_CONN_04_requestIDsStartAtOneAndIncrease() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "app-icon", "hierarchy"))
        let session = try await Harness.readySession(for: server)

        let icon = try await session.appIcon()
        XCTAssertEqual(icon?.pixelWidth, 2)
        let hierarchy = try await session.hierarchy()
        XCTAssertEqual(hierarchy.nodes.count, 14)

        let ids = await server.receivedFrames.map(\.requestID)
        XCTAssertEqual(ids, [0, 1, 2])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    func test_C_CONN_04_concurrentRequestsKeepTheirIDsInWireOrder() async throws {
        // Many requests issued at once: whatever order they are sent in, the IDs on the wire
        // must be 1, 2, 3, … in the order the frames arrive.
        let count = 50
        var steps = try Harness.handshakeSteps()
        let icon = try Harness.fixture("app-icon", "02-s2c-app-icon.bin")
        for index in 1...count {
            steps.append(.expect(.getAppIcon, as: UInt32(index)))
        }
        for index in 1...count {
            steps.append(.send(Frame(requestID: UInt32(index), body: icon.body)))
        }
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<count {
                group.addTask { _ = try await session.appIcon() }
            }
            try await group.waitForAll()
        }

        let ids = await server.receivedFrames.map(\.requestID)
        XCTAssertEqual(ids, [0] + (1...UInt32(count)).map { $0 })

        await session.close()
        await server.stop()
    }

    func test_C_CONN_04_responsesInAnyOrderReachTheirRequests() async throws {
        var steps = try Harness.handshakeSteps()
        steps += [
            .expect(.getAppIcon, as: 1),
            .expect(.getHierarchy, as: 2),
            // Answered in the opposite order.
            .send(try Harness.fixture("hierarchy", "02-s2c-hierarchy.bin")),
            .send(try Harness.fixture("app-icon", "02-s2c-app-icon.bin")),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server)

        let iconTask = Task { try await session.appIcon() }
        // Start the second request only once the first is on the wire.
        let firstArrived = await Harness.eventually { await server.receivedFrames.count == 2 }
        XCTAssertTrue(firstArrived)
        let hierarchy = try await session.hierarchy()
        let icon = try await iconTask.value

        XCTAssertEqual(hierarchy.nodes.count, 14)
        XCTAssertEqual(icon?.pixelWidth, 2)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    func test_C_CONN_04_aRequestWithoutAResponseTimesOut() async throws {
        var steps = try Harness.handshakeSteps()
        steps.append(.expect(.getHierarchy, as: 1))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server, requestTimeout: .milliseconds(200))

        let start = ContinuousClock.now
        await assertThrows(.timedOut) { _ = try await session.hierarchy() }
        let elapsed = ContinuousClock.now - start
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(200))
        XCTAssertLessThan(elapsed, .seconds(2))

        await session.close()
        await server.stop()
    }

    func test_C_CONN_04_aLateResponseIsDroppedAndTheSessionStaysUsable() async throws {
        // The server answers the hierarchy only after the next request arrived, which the
        // client sends once the hierarchy timed out. The late answer always lands while the
        // icon request is waiting, whatever the timing.
        var steps = try Harness.handshakeSteps()
        steps += [
            .expect(.getHierarchy, as: 2),
            .expect(.getAppIcon, as: 1),
            .send(try Harness.fixture("hierarchy", "02-s2c-hierarchy.bin")),
            .send(try Harness.fixture("app-icon", "02-s2c-app-icon.bin")),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server, requestTimeout: .milliseconds(400))

        await assertThrows(.timedOut) { _ = try await session.hierarchy() }

        // The late Hierarchy must not be handed to this request, and must not close the
        // connection. The AppIcon that follows is this request's answer.
        let icon = try await session.appIcon()
        XCTAssertEqual(icon?.pixelWidth, 2)
        let ids = await server.receivedFrames.map(\.requestID)
        XCTAssertEqual(ids, [0, 1, 2])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    // MARK: - C-CONN-07

    func test_C_CONN_07_aDisconnectFailsRequestsInFlight() async throws {
        var steps = try Harness.handshakeSteps()
        steps += [.expect(.getHierarchy, as: 1), .close]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server)

        await assertThrows(.disconnected) { _ = try await session.hierarchy() }

        // The handshake scenario sends the current state first; then the connection ends.
        let events = await Harness.events(2, from: session)
        XCTAssertEqual(events, [.appStateChanged(.active), .closed])
        await server.stop()
    }

    func test_C_CONN_07_requestsAfterTheConnectionEndedFailAtOnce() async throws {
        var steps = try Harness.handshakeSteps()
        steps.append(.close)
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server, requestTimeout: .seconds(5))

        let events = await Harness.events(2, from: session)
        XCTAssertEqual(events.last, .closed)

        let start = ContinuousClock.now
        await assertThrows(.disconnected) { _ = try await session.hierarchy() }
        await assertThrows(.disconnected) { _ = try await session.appIcon() }
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(1))
        await server.stop()
    }

    func test_C_CONN_07_closingTheSessionFailsRequestsInFlight() async throws {
        var steps = try Harness.handshakeSteps()
        steps.append(.expect(.getHierarchy, as: 1))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server)

        let request = Task { try await session.hierarchy() }
        let arrived = await Harness.eventually { await server.receivedFrames.count == 2 }
        XCTAssertTrue(arrived)
        await session.close()

        await assertThrows(.disconnected) { _ = try await request.value }
        await server.stop()
    }

    // MARK: - C-CONN-08

    func test_C_CONN_08_appStateChangesArriveAsEvents() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "app-not-active"))
        let session = try await Harness.readySession(for: server)

        // "handshake" reports Active, then "app-not-active" reports Background.
        let events = await Harness.events(2, from: session)
        XCTAssertEqual(events, [.appStateChanged(.active), .appStateChanged(.background)])

        await session.close()
        await server.stop()
    }

    func test_C_CONN_08_appNotActiveIsNotAnOrdinaryFailure() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "app-not-active"))
        let session = try await Harness.readySession(for: server)

        await assertThrows(.appNotActive(message: "the app is not active")) {
            _ = try await session.hierarchy()
        }

        await session.close()
        await server.stop()
    }

    func test_C_CONN_08_otherErrorsStayOrdinaryFailures() async throws {
        var steps = try Harness.handshakeSteps()
        let failure = ServerError(code: .internalError, message: "boom")
        steps += [
            .expect(.getHierarchy, as: 1),
            .send(Frame(requestID: 1, body: .error(failure))),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server)

        await assertThrows(.server(failure)) { _ = try await session.hierarchy() }

        await session.close()
        await server.stop()
    }

    // MARK: - C-CONN-10

    /// Runs a session against a server that sends `unexpected` after the handshake, and
    /// checks that the client closes the connection.
    private func assertClosesAfter(
        _ unexpected: MockScript.Step, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        var steps = try Harness.handshakeSteps()
        steps.append(unexpected)
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server)

        let events = await Harness.events(2, from: session)
        XCTAssertEqual(events, [.appStateChanged(.active), .closed], file: file, line: line)
        await assertThrows(.disconnected, file: file, line: line) {
            _ = try await session.hierarchy()
        }
        // The server sees the connection end: the client closed it, not just gave up on it.
        let left = await Harness.eventually { await server.clientCloseCount == 1 }
        XCTAssertTrue(left, "the client did not close the connection", file: file, line: line)
        // Keeps the session alive up to here: releasing it would close the connection too.
        withExtendedLifetime(session) {}
        await server.stop()
    }

    func test_C_CONN_10_aSecondHelloClosesTheConnection() async throws {
        try await assertClosesAfter(.send(try Harness.fixture("handshake", "02-s2c-hello.bin")))
    }

    func test_C_CONN_10_aFrameWithoutABodyClosesTheConnection() async throws {
        try await assertClosesAfter(.send(Frame(requestID: 0, body: nil)))
    }

    func test_C_CONN_10_aClientOnlyMessageClosesTheConnection() async throws {
        try await assertClosesAfter(.send(Frame(requestID: 5, body: .getHierarchy)))
        try await assertClosesAfter(.send(Frame(requestID: 5, body: .getAppIcon)))
        try await assertClosesAfter(.send(Frame(requestID: 5, body: .cancel(Cancel(targetRequestID: 1)))))
        // Protocol 0.3.
        try await assertClosesAfter(.send(Frame(requestID: 5, body: .getSubtree(GetSubtree(rootID: 1)))))
        try await assertClosesAfter(.send(Frame(requestID: 5, body: .setAttribute(SetAttribute(
            layerID: 3, attributeID: "label.text", value: .string("Hi"))))))
    }

    func test_C_CONN_10_aFrameThatDoesNotVerifyClosesTheConnection() async throws {
        // A length of 8 followed by 8 bytes that are not a FlatBuffer (P-FRAME-03).
        try await assertClosesAfter(.sendBytes(
            Data([0x08, 0x00, 0x00, 0x00]) + Data(repeating: 0xEE, count: 8)))
    }

    func test_C_CONN_10_aLengthOverTheMaximumClosesTheConnection() async throws {
        try await assertClosesAfter(.sendBytes(Data([0xFF, 0xFF, 0xFF, 0xFF])))
    }

    func test_C_CONN_10_aResponseOfTheWrongKindFailsTheRequestAndCloses() async throws {
        var steps = try Harness.handshakeSteps()
        steps += [
            .expect(.getAppIcon, as: 2),
            // A Hierarchy where an AppIcon was due. The fixture's request ID is 2.
            .send(try Harness.fixture("hierarchy", "02-s2c-hierarchy.bin")),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server)

        do {
            _ = try await session.appIcon()
            XCTFail("did not throw")
        } catch {
            guard case .protocolViolation = error as? RequestError else {
                XCTFail("threw \(error)")
                return
            }
        }
        let events = await Harness.events(2, from: session)
        XCTAssertEqual(events.last, .closed)
        await server.stop()
    }
}
