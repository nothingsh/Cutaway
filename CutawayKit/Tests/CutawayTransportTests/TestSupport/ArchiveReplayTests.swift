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

    func test_C_MOCK_04_aReplayAnswersLayersTheArchiveLacksAsNotFound() async throws {
        let scene = SyntheticScene(
            layerCount: 30, shape: .app(AppShape()), imagePixels: .fixed(width: 8, height: 8),
            attributes: true)
        let (server, session, _) = try await replay(try scene.archive { $0 % 2 == 1 })
        let answered = try await Self.chunks(Self.everything([1, 2, 3, 4]), session).flatMap { $0 }
        XCTAssertEqual(answered.map(\.layerID), [1, 2, 3, 4])
        XCTAssertEqual(answered.map(\.status), [.ok, .layerNotFound, .ok, .layerNotFound])
        XCTAssertNil(answered[1].solo)
        XCTAssertEqual(answered[1].attributeGroups, [])
        // Only the parts asked for.
        let trimmed = try await Self.chunks(
            GetLayerDetails(
                requests: [LayerDetailRequest(
                    layerID: 3, wantSolo: false, wantGroup: true, wantAttributes: false,
                    wantConstraints: false)],
                maxTextureDimension: 4096),
            session
        ).flatMap { $0 }
        XCTAssertNil(trimmed.first?.solo)
        XCTAssertNotNil(trimmed.first?.group)
        XCTAssertEqual(trimmed.first?.attributeGroups, [])
        await session.close()
        await server.stop()
    }

    func test_C_MOCK_04_aReplayGivesWhatTheArchiveHoldsWhateverTheSizeAsked() async throws {
        let scene = SyntheticScene(
            layerCount: 5, shape: .deep, imagePixels: .fixed(width: 64, height: 48))
        let (server, session, _) = try await replay(try scene.archive())
        let small = try await Self.chunks(Self.everything([2], longestSide: 16), session)
        let image = try XCTUnwrap(small.first?.first?.group)
        XCTAssertEqual(image, scene.details()[2]?.group, "not scaled down to 16 pixels")
        XCTAssertEqual(image.pixelWidth, 64)
        await session.close()
        await server.stop()
    }

    func test_C_MOCK_04_aReplayRefusesEdits() async throws {
        let scene = SyntheticScene(layerCount: 5, shape: .deep, attributes: true)
        let (server, session, _) = try await replay(try scene.archive())
        do {
            _ = try await session.setAttribute(
                SetAttribute(layerID: 2, attributeID: "layer.opacity", value: .double(0.5)))
            XCTFail("the edit was applied")
        } catch {
            XCTAssertEqual(error as? RequestError, .attributeNotEditable(message: nil))
        }
        await session.close()
        await server.stop()
    }

    func test_C_MOCK_04_aReplayRegroupsChunksWithinSixteenMebibytes() async throws {
        // Eight layers of two 4 MiB images in one stored chunk: 64 MiB, which the app would
        // have sent in four chunks (P-DET-06).
        let scene = SyntheticScene(
            layerCount: 8, shape: .deep, imagePixels: .fixed(width: 1024, height: 1024))
        let archive = try scene.archive(chunkSize: 8)
        XCTAssertEqual(try ArchiveDecoder(archive).chunkCount, 1)
        let (server, session, _) = try await replay(archive)
        let chunks = try await Self.chunks(Self.everything(Array(1...8)), session)
        XCTAssertEqual(chunks.map { $0.map(\.layerID) }, [[1, 2], [3, 4], [5, 6], [7, 8]])
        await session.close()
        await server.stop()
    }
}
