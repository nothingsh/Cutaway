import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-WIRE-12: what an inspection may ask for follows the negotiated minor version as well as
/// whether the source is an app.
final class InspectionCapabilitiesTests: XCTestCase {
    private func capabilities(_ script: MockScript) async throws -> InspectionCapabilities? {
        let server = try await MockServer.start(script: script)
        let session = try await AttributesStoreTests.session(to: server)
        let capabilities = await session.capabilities
        await session.close()
        await server.stop()
        return capabilities
    }

    func test_C_WIRE_12_capabilitiesFollowTheNegotiatedMinor() async throws {
        let current = try await capabilities(try .fixtures("handshake"))
        XCTAssertEqual(
            current,
            InspectionCapabilities(
                canRefreshSubtrees: true, canEditAttributes: true, canOverrideEnvironment: true))

        let older = try await capabilities(try MockScript.fixtures("handshake").asProtocol11())
        XCTAssertEqual(
            older, InspectionCapabilities(canRefreshSubtrees: true, canEditAttributes: true),
            "a 1.1 server has no environment")

        let archive = ArchiveSource(decoder: try ArchiveDecoder(try Fixtures.archive(chunkSize: 2)))
        let negotiated = await archive.negotiatedVersion
        XCTAssertEqual(negotiated, ProtocolVersion.current)
        let offline = await archive.capabilities
        XCTAssertEqual(
            offline, InspectionCapabilities(canRefreshSubtrees: false, canEditAttributes: false),
            "an archive can only be looked at, whatever its version")
    }
}
