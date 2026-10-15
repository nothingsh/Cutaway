import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// The scenes the test support library makes up (C-MOCK-03).
final class SyntheticSceneTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    private static let tenThousand = SyntheticScene(
        layerCount: 10_000, shape: .app(AppShape()), imagePixels: .fixed(width: 32, height: 32),
        attributes: true, constraints: true)

    /// Whether the nodes form a tree as P-HIER-01 and P-HIER-03 have it: IDs that are not 0
    /// and appear once, each parent before its children.
    private func assertIsTree(
        _ hierarchy: Hierarchy, file: StaticString = #filePath, line: UInt = #line
    ) {
        var seen = Set<UInt64>()
        for node in hierarchy.nodes {
            XCTAssertNotEqual(node.id, 0, file: file, line: line)
            XCTAssertTrue(seen.insert(node.id).inserted, "\(node.id) twice", file: file, line: line)
            if node.parentID != 0 {
                XCTAssertTrue(
                    seen.contains(node.parentID), "\(node.id) before its parent", file: file,
                    line: line)
            }
        }
    }

    func test_C_MOCK_03_tenThousandLayersMakeATreeAndEveryLayerHasDetails() async throws {
        let scene = Self.tenThousand
        let hierarchy = scene.hierarchy()
        XCTAssertEqual(hierarchy.nodes.count, 10_000)
        assertIsTree(hierarchy)
        XCTAssertEqual(hierarchy.keyWindowID, hierarchy.nodes[0].id)

        let details = scene.details()
        XCTAssertEqual(Set(details.keys), Set(hierarchy.nodes.map(\.id)))
        XCTAssertTrue(details.values.allSatisfy { $0.status == .ok && $0.solo != nil && $0.group != nil })
        XCTAssertTrue(details.values.allSatisfy { !$0.attributeGroups.isEmpty })
        XCTAssertTrue(details.values.contains { !$0.constraints.isEmpty })

        // Asked for every layer over a connection, as the preview asks: in batches of eight.
        let server = try await MockServer.start(
            script: MockScript(
                steps: try MockScript.fixtures("handshake").steps + [.respond(scene.responder())]),
            records: false)
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client, requestTimeout: .seconds(10))
        _ = try await session.handshake()
        let answered0 = try await session.hierarchy()
        XCTAssertEqual(answered0, hierarchy)
        var answered = Set<UInt64>()
        let ids = hierarchy.nodes.map(\.id)
        for start in stride(from: 0, to: ids.count, by: 8) {
            let request = GetLayerDetails(
                requests: ids[start..<min(start + 8, ids.count)].map {
                    LayerDetailRequest(
                        layerID: $0, wantSolo: true, wantGroup: true, wantAttributes: true,
                        wantConstraints: true)
                },
                maxTextureDimension: 4096)
            for try await chunk in await session.layerDetails(request).chunks {
                for detail in chunk where detail.status == .ok { answered.insert(detail.layerID) }
            }
        }
        XCTAssertEqual(answered.count, 10_000)
        await session.close()
        await server.stop()
    }

    /// The hierarchy, then one chunk of every eight layers' details, encoded.
    private static func frames(of scene: SyntheticScene) -> [Data] {
        let hierarchy = scene.hierarchy()
        let details = scene.details()
        var frames = [FrameCodec.encode(Frame(requestID: 1, body: .hierarchy(hierarchy)))]
        let ids = hierarchy.nodes.map(\.id)
        for start in stride(from: 0, to: ids.count, by: 8) {
            let chunk = LayerDetailsChunk(
                sequence: 0, details: ids[start..<min(start + 8, ids.count)].compactMap { details[$0] })
            frames.append(FrameCodec.encode(Frame(requestID: 2, body: .layerDetailsChunk(chunk))))
        }
        return frames
    }
}
