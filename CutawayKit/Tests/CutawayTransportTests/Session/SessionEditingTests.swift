import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// C-CONN-11: changing an attribute and asking for a subtree (protocol 0.3).
final class SessionEditingTests: XCTestCase {
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

    private func assertViolation(
        file: StaticString = #filePath, line: UInt = #line, _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("did not throw", file: file, line: line)
        } catch {
            guard case .protocolViolation = error as? RequestError else {
                XCTFail("threw \(error)", file: file, line: line)
                return
            }
        }
    }

    /// The fixture's frames of one direction, decoded, in file order.
    private func frames(
        _ scenario: String, _ direction: FixtureFrame.Direction
    ) throws -> [Frame] {
        try Fixtures.frames(scenario: scenario)
            .filter { $0.direction == direction }
            .map { try FrameCodec.decode($0.payload) }
    }

    func test_C_CONN_11_setAttributeAnswersWithTheLayersAttributes() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "set-attribute"))
        let session = try await Harness.readySession(for: server)

        let requests = try frames("set-attribute", .clientToServer)
        let answers = try frames("set-attribute", .serverToClient)
        XCTAssertEqual(requests.count, 5)
        for (request, answer) in zip(requests, answers) {
            guard case .setAttribute(let body) = request.body,
                  case .setAttributeResult(let expected) = answer.body
            else {
                XCTFail("not a SetAttribute and its result")
                return
            }
            let result = try await session.setAttribute(body)
            XCTAssertEqual(result, expected)
        }

        // What the client sent is what the fixture's client sent.
        let received = await server.receivedFrames
        XCTAssertEqual(received.dropFirst().map(\.body), requests.map(\.body))
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    func test_C_CONN_11_rejectionsAreToldApartAndTheSessionStaysUsable() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "set-attribute-rejected", "hierarchy"))
        let session = try await Harness.readySession(for: server)

        let requests = try frames("set-attribute-rejected", .clientToServer).map { frame in
            guard case .setAttribute(let body) = frame.body else { throw RequestError.disconnected }
            return body
        }
        let expected: [RequestError] = [
            .layerNotFound(message: "no layer with id 99"),
            .attributeNotEditable(message: "layer.frame is read-only"),
            .invalidAttributeValue(message: "layer.opacity takes a DoubleValue"),
            .invalidAttributeValue(message: "label.numberOfLines cannot be nil"),
        ]
        for (request, error) in zip(requests, expected) {
            await assertThrows(error) { _ = try await session.setAttribute(request) }
        }

        let hierarchy = try await session.hierarchy()
        XCTAssertEqual(hierarchy.nodes.count, 9)

        await session.close()
        await server.stop()
    }

    func test_C_CONN_11_subtree() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake", "subtree"))
        let session = try await Harness.readySession(for: server)
        let negotiated = await session.negotiatedVersion
        XCTAssertEqual(negotiated, Version(major: 1, minor: 0))

        let subtree = try await session.subtree(of: 4)
        XCTAssertEqual(subtree.nodes.map(\.id), [4, 5])
        XCTAssertEqual(subtree.nodes[0].parentID, 2)
        XCTAssertEqual(subtree.keyWindowID, 1)

        await assertThrows(.layerNotFound(message: "no layer with id 99")) {
            _ = try await session.subtree(of: 99)
        }

        let received = await server.receivedFrames.map(\.body)
        XCTAssertEqual(
            received.dropFirst(),
            [.getSubtree(GetSubtree(rootID: 4)), .getSubtree(GetSubtree(rootID: 99))])

        await session.close()
        await server.stop()
    }

    func test_C_CONN_11_appNotActiveIsNotAnOrdinaryFailure() async throws {
        var steps = try Harness.handshakeSteps()
        let notActive = ServerError(code: .appNotActive, message: "the app is not active")
        steps += [
            .expect(.setAttribute, as: 1),
            .send(Frame(requestID: 1, body: .error(notActive))),
            .expect(.getSubtree, as: 2),
            .send(Frame(requestID: 2, body: .error(notActive))),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server)

        await assertThrows(.appNotActive(message: "the app is not active")) {
            _ = try await session.setAttribute(SetAttribute(
                layerID: 3, attributeID: "label.text", value: .string("Hi")))
        }
        await assertThrows(.appNotActive(message: "the app is not active")) {
            _ = try await session.subtree(of: 1)
        }

        await session.close()
        await server.stop()
    }

    func test_C_CONN_11_requestsWithoutAnAnswerTimeOut() async throws {
        var steps = try Harness.handshakeSteps()
        steps += [.expect(.setAttribute, as: 1), .expect(.getSubtree, as: 2)]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server, requestTimeout: .milliseconds(200))

        let start = ContinuousClock.now
        await assertThrows(.timedOut) {
            _ = try await session.setAttribute(SetAttribute(
                layerID: 3, attributeID: "layer.opacity", value: .double(0.5)))
        }
        await assertThrows(.timedOut) { _ = try await session.subtree(of: 4) }
        let elapsed = ContinuousClock.now - start
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(400))
        XCTAssertLessThan(elapsed, .seconds(2))

        await session.close()
        await server.stop()
    }

    func test_C_CONN_11_anOlderServerIsNeverSentEither() async throws {
        // The server speaks 0.2: P-HELLO-04 keeps 0.3's messages off the wire.
        var steps = try Harness.handshakeSteps()
        guard case .send(var hello) = steps[1], case .hello(var body) = hello.body else {
            XCTFail("the handshake script changed shape")
            return
        }
        body.protocolVersion = Version(major: 0, minor: 2)
        hello.body = .hello(body)
        steps[1] = .send(hello)
        steps += try MockScript.fixtures("hierarchy").steps
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.session(for: server, protocolVersion: Fixtures.zeroMajorProtocol)
        let before = await session.negotiatedVersion
        XCTAssertNil(before)
        let outcome = try await session.handshake()
        guard case .ready(_, let negotiated) = outcome else {
            XCTFail("\(outcome)")
            return
        }
        XCTAssertEqual(negotiated, Version(major: 0, minor: 2))
        // Kept for whoever asks later, such as an inspection (C-DET-07).
        let kept = await session.negotiatedVersion
        XCTAssertEqual(kept, Version(major: 0, minor: 2))

        await assertThrows(.unsupported) {
            _ = try await session.setAttribute(SetAttribute(
                layerID: 3, attributeID: "label.text", value: .string("Hi")))
        }
        await assertThrows(.unsupported) { _ = try await session.subtree(of: 4) }

        // Neither took a request ID: the next request is still number 1.
        _ = try await session.hierarchy()
        let received = await server.receivedFrames
        XCTAssertEqual(received.map(\.requestID), [0, 1])
        XCTAssertEqual(received.last?.body, .getHierarchy)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        // Once the connection ended, they fail as any request does.
        await session.close()
        await assertThrows(.disconnected) { _ = try await session.subtree(of: 4) }
        await server.stop()
    }

    func test_C_CONN_11_aResultForAnotherLayerFailsOnlyThatRequest() async throws {
        var steps = try Harness.handshakeSteps()
        steps += [
            .expect(.setAttribute, as: 1),
            .send(Frame(requestID: 1, body: .setAttributeResult(SetAttributeResult(
                layerID: 7, attributeGroups: [])))),
        ]
        steps += try MockScript.fixtures("hierarchy").steps
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server)

        await assertViolation {
            _ = try await session.setAttribute(SetAttribute(
                layerID: 3, attributeID: "label.text", value: .string("Hi")))
        }
        // The connection is kept: the frame itself was well formed and answered the request.
        let hierarchy = try await session.hierarchy()
        XCTAssertEqual(hierarchy.nodes.count, 9)

        await session.close()
        await server.stop()
    }

    func test_C_CONN_11_aSubtreeThatDoesNotStartAtTheLayerFailsOnlyThatRequest() async throws {
        let whole = try Harness.fixture("hierarchy", "02-s2c-hierarchy.bin")
        guard case .hierarchy(let tree) = whole.body else {
            XCTFail("not a Hierarchy")
            return
        }
        var steps = try Harness.handshakeSteps()
        steps += [
            // The whole tree where node 4's subtree was asked for.
            .expect(.getSubtree, as: 1),
            .send(Frame(requestID: 1, body: .hierarchy(tree))),
            // No nodes at all.
            .expect(.getSubtree, as: 2),
            .send(Frame(requestID: 2, body: .hierarchy(Hierarchy(nodes: [], keyWindowID: 1)))),
        ]
        steps += try MockScript.fixtures("subtree").steps
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Harness.readySession(for: server)

        await assertViolation { _ = try await session.subtree(of: 4) }
        await assertViolation { _ = try await session.subtree(of: 4) }
        let subtree = try await session.subtree(of: 4)
        XCTAssertEqual(subtree.nodes.map(\.id), [4, 5])

        await session.close()
        await server.stop()
    }

    /// Pairing is as for the other requests (C-CONN-04, C-CONN-10): an answer of the wrong
    /// kind fails the request and closes the connection.
    func test_C_CONN_11_anAnswerOfTheWrongKindClosesTheConnection() async throws {
        let wrongAnswers: [(MessageKind, Body)] = [
            (.setAttribute, .hierarchy(Hierarchy(nodes: [], keyWindowID: 0))),
            (.getSubtree, .setAttributeResult(SetAttributeResult(layerID: 4, attributeGroups: []))),
            (.getHierarchy, .setAttributeResult(SetAttributeResult(layerID: 4, attributeGroups: []))),
        ]
        for (request, answer) in wrongAnswers {
            var steps = try Harness.handshakeSteps()
            steps += [.expect(request, as: 1), .send(Frame(requestID: 1, body: answer))]
            let server = try await MockServer.start(script: MockScript(steps: steps))
            let session = try await Harness.readySession(for: server)

            await assertViolation {
                switch request {
                case .setAttribute:
                    _ = try await session.setAttribute(SetAttribute(
                        layerID: 4, attributeID: "view.alpha", value: .double(0.5)))
                case .getSubtree:
                    _ = try await session.subtree(of: 4)
                default:
                    _ = try await session.hierarchy()
                }
            }
            let events = await Harness.events(2, from: session)
            XCTAssertEqual(events.last, .closed, "\(request)")
            await server.stop()
        }
    }
}
