import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// C-WIRE-12: getting and overriding the app's trait environment (protocol 1.2), and sending
/// nothing of it to a peer below 1.2.
final class SessionEnvironmentTests: XCTestCase {
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

    /// The fixture's frames of one direction, decoded, in file order.
    private func frames(_ scenario: String, _ direction: FixtureFrame.Direction) throws -> [Frame] {
        try Fixtures.frames(scenario: scenario)
            .filter { $0.direction == direction }
            .map { try FrameCodec.decode($0.payload) }
    }

    private func environments(_ scenario: String) throws -> [Environment] {
        try frames(scenario, .serverToClient).compactMap { frame in
            guard case .environment(let environment) = frame.body else { return nil }
            return environment
        }
    }

    func test_C_WIRE_12_theEnvironmentIsAskedForAndOverridden() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake", "environment"))
        let session = try await Harness.readySession(for: server)
        let expected = try environments("environment")
        XCTAssertEqual(expected.count, 4)

        let first = try await session.environment()
        let second = try await session.setEnvironment(Traits(
            userInterfaceStyle: .dark, contentSizeCategory: .accessibilityLarge,
            layoutDirection: .rightToLeft))
        let third = try await session.setEnvironment(Traits(userInterfaceStyle: .dark))
        let fourth = try await session.setEnvironment(.unspecified)
        XCTAssertEqual([first, second, third, fourth], expected)

        // What the client sent is what the fixture's client sent.
        let received = await server.receivedFrames
        XCTAssertEqual(
            received.dropFirst().map(\.body), try frames("environment", .clientToServer).map(\.body))
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    func test_C_WIRE_12_refusalsAreToldApartAndTheSessionStaysUsable() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "environment-rejected"))
        let session = try await Harness.readySession(for: server)
        let unchanged = try XCTUnwrap(try environments("environment-rejected").first)

        let before = try await session.environment()
        XCTAssertEqual(before, unchanged)
        await assertThrows(
            .notSupported(message: "the layout direction cannot be overridden on this device")
        ) {
            _ = try await session.setEnvironment(Traits(
                userInterfaceStyle: .dark, layoutDirection: .rightToLeft))
        }
        let after = try await session.environment()
        XCTAssertEqual(after, unchanged)
        // The app goes to the background here (P-APP-01).
        await assertThrows(.appNotActive(message: "the app is not active")) {
            _ = try await session.setEnvironment(Traits(userInterfaceStyle: .dark))
        }
        let inTheBackground = try await session.environment()
        XCTAssertEqual(inTheBackground, unchanged)

        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
        await session.close()
        await server.stop()
    }

    func test_C_WIRE_12_aServerBelowOnePointTwoIsSentNothingOfTheEnvironment() async throws {
        let server = try await MockServer.start(
            script: try MockScript.fixtures("handshake").asProtocol11())
        let session = try await Harness.readySession(for: server)
        let negotiated = await session.negotiatedVersion
        XCTAssertEqual(negotiated, Version(major: 1, minor: 1))

        await assertThrows(.unsupported) { _ = try await session.environment() }
        await assertThrows(.unsupported) {
            _ = try await session.setEnvironment(Traits(userInterfaceStyle: .dark))
        }

        let received = await server.receivedFrames
        XCTAssertEqual(received.map { MessageKind($0.body) }, [.hello])
        await session.close()
        await server.stop()
    }
}
