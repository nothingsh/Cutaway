import CutawayTestSupport
import CutawayTransport
import CutawayWire
import Foundation
import XCTest

/// Sessions for the transport tests; the helpers shared with the tests of MockServer are in
/// CutawayTestSupport.
extension Harness {
    static func session(
        for server: MockServer, protocolVersion: Version = ProtocolVersion.current,
        client: ClientInfo = client, requestTimeout: Duration = .seconds(2)
    ) async throws -> Session {
        Session(
            channel: try await channel(to: server), client: client,
            protocolVersion: protocolVersion, requestTimeout: requestTimeout)
    }

    /// A session that has completed the handshake.
    static func readySession(
        for server: MockServer, protocolVersion: Version = ProtocolVersion.current,
        requestTimeout: Duration = .seconds(2), file: StaticString = #filePath, line: UInt = #line
    ) async throws -> Session {
        let session = try await session(
            for: server, protocolVersion: protocolVersion, requestTimeout: requestTimeout)
        let outcome = try await session.handshake()
        guard case .ready = outcome else {
            XCTFail("handshake ended as \(outcome)", file: file, line: line)
            throw RequestError.disconnected
        }
        return session
    }
}
