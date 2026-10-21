import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-DET-11, the part about virtual nodes (P-DET-09): their look is in their nearest layer
/// ancestor's images, so none are asked for them, the progress leaves them out, selecting
/// one asks for no constraints, and changing or refreshing one renews that layer's images.
/// In the `hierarchy` fixture nodes 10 to 12 are virtual, drawn by node 4.
final class VirtualNodeDetailsTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    private static func server() async throws -> MockServer {
        let steps = try MockScript.fixtures("handshake").steps
        return try await MockServer.start(
            script: MockScript(steps: steps + [.respond(try MockResponder.demo())]))
    }

    private static func session(to server: MockServer) async throws -> Session {
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: client, requestTimeout: .seconds(5))
        _ = try await session.handshake()
        return session
    }

    private static func requests(_ server: MockServer) async -> [LayerDetailRequest] {
        await server.receivedFrames.flatMap { frame -> [LayerDetailRequest] in
            guard case .getLayerDetails(let request) = frame.body else { return [] }
            return request.requests
        }
    }

    /// An inspection of the fixtures' app, every node expanded, with its first round done.
    @MainActor
    private static func inspect() async throws -> (InspectionStore, MockServer, Session) {
        let server = try await server()
        let session = try await session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .zero
        model.enter()
        let done = await Wait.until {
            await MainActor.run {
                model.loadState == .loaded && model.detailProgress.total > 0
                    && model.detailProgress.completed == model.detailProgress.total
            }
        }
        XCTAssertTrue(done)
        return (model, server, session)
    }

    @MainActor
    func test_C_DET_11_virtualNodesAreNotAskedForImages() async throws {
        let (model, server, session) = try await Self.inspect()
        XCTAssertTrue(model.layout.isDisplayed(10), "drawn, with an area")
        let asked = await Self.requests(server).filter { $0.wantSolo || $0.wantGroup }
        XCTAssertFalse(asked.isEmpty)
        XCTAssertFalse(asked.contains { [10, 11, 12].contains($0.layerID) })
        XCTAssertTrue(asked.contains { $0.layerID == 4 }, "the layer that draws them is")
        XCTAssertFalse(model.layout.neededTextures.contains { [10, 11, 12].contains($0.layerID) })
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_11_progressLeavesVirtualNodesOut() async throws {
        let (model, server, session) = try await Self.inspect()
        // Fourteen nodes: 5 is hidden, 9 has no area, 10 to 12 are virtual, 13 and 14 are
        // excluded.
        XCTAssertEqual(model.detailProgress.total, 7)
        XCTAssertEqual(model.detailProgress.completed, 7)
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_11_selectingAVirtualNodeAsksForAttributesWithoutConstraints() async throws {
        let (model, server, session) = try await Self.inspect()
        model.select(10)
        let loaded = await Wait.until {
            await MainActor.run {
                guard case .loaded(let groups, _) = model.attributes.state else { return false }
                return groups.contains { $0.id == "app.row" }
            }
        }
        XCTAssertTrue(loaded)
        model.select(3)
        let asked = await Wait.until {
            await Self.requests(server).contains { $0.layerID == 3 && $0.wantAttributes }
        }
        XCTAssertTrue(asked)
        let requests = await Self.requests(server).filter(\.wantAttributes)
        let ten = try XCTUnwrap(requests.first { $0.layerID == 10 })
        XCTAssertFalse(ten.wantConstraints)
        XCTAssertFalse(ten.wantSolo || ten.wantGroup)
        XCTAssertEqual(requests.first { $0.layerID == 3 }?.wantConstraints, true, "a layer still")
        await session.close()
        await server.stop()
    }

    func test_C_DET_11_changingAVirtualNodeRenewsItsLayerAncestorsImages() throws {
        let tree = try LayerTree(Fixtures.hierarchy())
        let needs = Set(LayerTree.needsAfterChanges([10], in: 1, from: tree, to: tree))
        XCTAssertEqual(
            needs,
            [
                TextureNeed(layerID: 4, kind: .solo), TextureNeed(layerID: 4, kind: .group),
                TextureNeed(layerID: 2, kind: .group), TextureNeed(layerID: 1, kind: .group),
            ])
    }

    func test_C_DET_11_aMovedVirtualNodeRenewsItsLayerAncestorsImages() throws {
        let old = try LayerTree(Fixtures.hierarchy())
        var hierarchy = try Fixtures.hierarchy()
        let index = try XCTUnwrap(hierarchy.nodes.firstIndex { $0.id == 11 })
        hierarchy.nodes[index].position = Point(x: 200, y: 20)
        let new = try LayerTree(hierarchy)
        let needs = Set(LayerTree.needsAfterChanges([], in: 1, from: old, to: new))
        XCTAssertTrue(needs.isSuperset(of: [
            TextureNeed(layerID: 4, kind: .solo), TextureNeed(layerID: 4, kind: .group),
        ]))
        XCTAssertFalse(needs.contains { [10, 11, 12].contains($0.layerID) })
    }

    func test_C_DET_11_refreshingAVirtualSubtreeRenewsItsLayerAncestorsImages() throws {
        let tree = try LayerTree(Fixtures.hierarchy())
        XCTAssertEqual(
            Set(LayerTree.needs(ofSubtree: 11, in: tree)),
            [
                TextureNeed(layerID: 4, kind: .solo), TextureNeed(layerID: 4, kind: .group),
                TextureNeed(layerID: 2, kind: .group), TextureNeed(layerID: 1, kind: .group),
            ])
        // A layer's subtree as before: its virtual nodes ask for nothing of their own.
        XCTAssertTrue(
            LayerTree.needs(ofSubtree: 4, in: tree).contains(TextureNeed(layerID: 5, kind: .solo)))
    }
}
