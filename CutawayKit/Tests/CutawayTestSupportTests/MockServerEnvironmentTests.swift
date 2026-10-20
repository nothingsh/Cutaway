import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// C-MOCK-01: how MockServer answers the environment requests of protocol 1.2.
final class MockServerEnvironmentTests: XCTestCase {
    private func handshake(_ client: inout FrameClient) async throws {
        try await client.send(try Harness.fixture("handshake", "01-c2s-hello.bin"))
        _ = try await client.next()
        _ = try await client.next()
    }

    func test_C_MOCK_01_aGetEnvironmentTheScriptLeavesOutIsAnsweredAsOverridingNothing() async throws {
        let hierarchy = try Fixtures.hierarchy()
        var steps = try MockScript.fixtures("handshake").steps
        steps += [
            .expect(.getHierarchy, as: 7),
            .send(Frame(requestID: 7, body: .hierarchy(hierarchy))),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        var client = FrameClient(channel: try await Harness.channel(to: server))
        try await handshake(&client)

        try await client.send(Frame(requestID: 2, body: .getEnvironment))
        let environment = try await client.next()
        XCTAssertEqual(environment?.requestID, 2)
        XCTAssertEqual(environment?.body, .environment(MockScript.unscriptedEnvironment))
        try await client.send(Frame(requestID: 3, body: .getHierarchy))
        let tree = try await client.next()
        XCTAssertEqual(tree?.body, .hierarchy(hierarchy))

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
        let unscripted = await server.unscriptedEnvironmentRequests
        XCTAssertEqual(unscripted, 1)
        let received = await server.receivedFrames.map { MessageKind($0.body) }
        XCTAssertFalse(received.contains(.getEnvironment))
        client.channel.close()
        await server.stop()
    }

    func test_C_MOCK_01_aResponderOverridesAsTheEnvironmentFixturesSay() async throws {
        var responder = try MockResponder.demo()
        responder.environment = .iPhone(overridable: [.userInterfaceStyle])
        let server = try await MockServer.start(
            script: MockScript(steps: try MockScript.fixtures("handshake").steps + [.respond(responder)]))
        var client = FrameClient(channel: try await Harness.channel(to: server))
        try await handshake(&client)

        let dark = Traits(userInterfaceStyle: .dark)
        try await client.send(Frame(requestID: 2, body: .setEnvironment(SetEnvironment(overrides: dark))))
        guard case .environment(let changed) = try await client.next()?.body else {
            XCTFail("no Environment")
            return
        }
        XCTAssertEqual(changed.overrides, dark)
        XCTAssertEqual(changed.current.userInterfaceStyle, .dark)
        XCTAssertEqual(changed.current.contentSizeCategory, .large)

        // The layout direction cannot be overridden: nothing changes (P-ENV-04).
        var both = dark
        both.layoutDirection = .rightToLeft
        try await client.send(Frame(requestID: 3, body: .setEnvironment(SetEnvironment(overrides: both))))
        guard case .error(let error) = try await client.next()?.body else {
            XCTFail("no Error")
            return
        }
        XCTAssertEqual(error.code, .notSupported)
        try await client.send(Frame(requestID: 4, body: .getEnvironment))
        guard case .environment(let after) = try await client.next()?.body else {
            XCTFail("no Environment")
            return
        }
        XCTAssertEqual(after.overrides, dark)

        client.channel.close()
        await server.stop()
    }
}
