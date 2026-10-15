import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// MockServer replaying an archive as its scene (C-MOCK-04).
final class ArchiveReplayTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    private static func everything(_ ids: [UInt64], longestSide: UInt32 = 4096) -> GetLayerDetails {
        GetLayerDetails(
            requests: ids.map {
                LayerDetailRequest(
                    layerID: $0, wantSolo: true, wantGroup: true, wantAttributes: true,
                    wantConstraints: true)
            },
            maxTextureDimension: longestSide)
    }

    private func replay(_ archive: Data) async throws -> (MockServer, Session, HandshakeOutcome) {
        let server = try await MockServer.start(script: try MockScript.replaying(archive: archive))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client, requestTimeout: .seconds(10))
        let outcome = try await session.handshake()
        return (server, session, outcome)
    }

    private static func chunks(
        _ request: GetLayerDetails, _ session: Session
    ) async throws -> [[LayerDetail]] {
        var chunks: [[LayerDetail]] = []
        for try await chunk in await session.layerDetails(request).chunks { chunks.append(chunk) }
        return chunks
    }

    func test_C_MOCK_04_aReplayAnswersAsTheArchivedAppDid() async throws {
        let archive = try Fixtures.archive()
        let decoder = try ArchiveDecoder(archive)
        let (server, session, outcome) = try await replay(archive)
        guard case .ready(let app, _) = outcome else {
            XCTFail("\(outcome)")
            return
        }
        XCTAssertEqual(app, decoder.hello.app)
        let icon = try await session.appIcon()
        XCTAssertEqual(icon, decoder.appIcon.image)
        let hierarchy = try await session.hierarchy()
        XCTAssertEqual(hierarchy, decoder.hierarchy)
        let subtree = try await session.subtree(of: 4)
        XCTAssertEqual(subtree.nodes.map(\.id), [4, 5])

        let stored = (0..<decoder.chunkCount).flatMap { (try? decoder.chunk(at: $0).details) ?? [] }
        let answered = try await Self.chunks(Self.everything(hierarchy.nodes.map(\.id)), session)
        XCTAssertEqual(answered.flatMap { $0 }, stored)
        await session.close()
        await server.stop()
    }
}
