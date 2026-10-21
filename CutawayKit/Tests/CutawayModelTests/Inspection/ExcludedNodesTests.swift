import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-DET-11, the part about nodes the app excludes from images (P-DET-10): no images are
/// asked for them, the progress leaves them out, and an `Excluded` answer is neither retried
/// nor a failure. In the `hierarchy` fixture nodes 13 and 14 are excluded.
final class ExcludedNodesTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    private static func server(_ responder: MockResponder) async throws -> MockServer {
        let steps = try MockScript.fixtures("handshake").steps
        return try await MockServer.start(script: MockScript(steps: steps + [.respond(responder)]))
    }

    private static func session(to server: MockServer) async throws -> Session {
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: client, requestTimeout: .seconds(5))
        _ = try await session.handshake()
        return session
    }

    /// Every layer the server was asked images of, a layer once per request.
    private static func imageRequests(_ server: MockServer) async -> [UInt64] {
        await server.receivedFrames.flatMap { frame -> [UInt64] in
            guard case .getLayerDetails(let request) = frame.body else { return [] }
            return request.requests.filter { $0.wantSolo || $0.wantGroup }.map(\.layerID)
        }
    }

    /// An inspection of the responder's app, every node expanded, with its first round done.
    @MainActor
    private static func inspect(
        _ responder: MockResponder
    ) async throws -> (InspectionStore, MockServer, Session) {
        let server = try await server(responder)
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
    func test_C_DET_11_excludedNodesAreNotAskedForImages() async throws {
        let (model, server, session) = try await Self.inspect(try MockResponder.demo())
        let asked = await Self.imageRequests(server)
        XCTAssertFalse(asked.isEmpty)
        XCTAssertFalse(asked.contains(13))
        XCTAssertFalse(asked.contains(14))
        XCTAssertFalse(model.layout.neededTextures.contains { [13, 14].contains($0.layerID) })
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_11_progressLeavesExcludedNodesOut() async throws {
        let (model, server, session) = try await Self.inspect(try MockResponder.demo())
        // The same tree without the flags: 13 and 14 are drawn, so they would count.
        var hierarchy = try Fixtures.hierarchy()
        for index in hierarchy.nodes.indices { hierarchy.nodes[index].isCaptureExcluded = false }
        let unmarked = try LayerTree(hierarchy)
        let all = SceneLayout(
            layers: unmarked.sceneLayers(), expanded: Set(unmarked.ids), focus: nil,
            showsHidden: false)
        XCTAssertEqual(all.neededTextures.filter { [13, 14].contains($0.layerID) }.count, 2)
        XCTAssertEqual(model.detailProgress.total, all.neededTextures.count - 2)
        XCTAssertEqual(model.detailProgress.completed, model.detailProgress.total)
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_11_selectingAnExcludedNodeStillGetsItsAttributes() async throws {
        let (model, server, session) = try await Self.inspect(try MockResponder.demo())
        model.select(13)
        let loaded = await Wait.until {
            await MainActor.run {
                guard case .loaded(let groups, _) = model.attributes.state else { return false }
                return groups.flatMap(\.attributes).contains { $0.id == "view.isHidden" }
            }
        }
        XCTAssertTrue(loaded)
        await session.close()
        await server.stop()
    }

    /// The app excluded node 6 after the hierarchy was taken: it says so when asked.
    private static func excludingSix() throws -> MockResponder {
        var responder = try MockResponder.demo()
        responder.details[6]?.status = .excluded
        responder.details[6]?.solo = nil
        responder.details[6]?.group = nil
        return responder
    }

    @MainActor
    func test_C_DET_11_anExcludedAnswerIsNotRetriedNorAFailure() async throws {
        let (model, server, session) = try await Self.inspect(try Self.excludingSix())
        XCTAssertEqual(model.tree.node(6)?.isCaptureExcluded, true)
        XCTAssertEqual(model.tree.node(7)?.isCaptureExcluded, true, "what is below it too")
        XCTAssertNil(model.images[6])
        XCTAssertNil(model.notice)
        XCTAssertFalse(model.layout.neededTextures.contains { [6, 7].contains($0.layerID) })

        try await Task.sleep(for: .milliseconds(300))
        let asked = await Self.imageRequests(server)
        XCTAssertEqual(asked.filter { $0 == 6 }.count, 1, "not asked again")
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_11_aNewHierarchyDecidesAgain() async throws {
        let (model, server, session) = try await Self.inspect(try Self.excludingSix())
        XCTAssertEqual(model.tree.node(6)?.isCaptureExcluded, true)
        model.refresh()
        // The new hierarchy does not exclude 6: it is asked for again, and excluded again.
        let askedAgain = await Wait.until {
            await Self.imageRequests(server).filter { $0 == 6 }.count == 2
        }
        XCTAssertTrue(askedAgain)
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_11_anExcludedNodeCannotBeExported() async throws {
        let (model, server, session) = try await Self.inspect(try MockResponder.demo())
        XCTAssertFalse(model.canExportImage(of: 13, kind: .group))
        XCTAssertFalse(model.canExportImage(of: 14, kind: .solo))
        XCTAssertTrue(model.canExportImage(of: 3, kind: .group))
        await session.close()
        await server.stop()
    }

    func test_C_DET_11_theExportFailureNamesTheApp() async throws {
        var responder = try MockResponder.demo()
        responder.details[3]?.status = .excluded
        let server = try await Self.server(responder)
        let session = try await Self.session(to: server)
        do {
            _ = try await ScreenshotExporter.image(
                of: 3, kind: .group, held: nil, from: session,
                maxTextureDimension: 0, decode: { _ in throw CocoaError(.fileReadCorruptFile) })
            XCTFail("exported")
        } catch {
            XCTAssertEqual(error, .excluded)
        }
        await session.close()
        await server.stop()
    }

    func test_C_DET_11_archivingDoesNotAskForExcludedImages() async throws {
        let server = try await Self.server(try MockResponder.demo())
        let session = try await Self.session(to: server)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExcludedNodesTests-\(UUID().uuidString).cutaway")
        defer { try? FileManager.default.removeItem(at: destination) }
        try await ArchiveCapture.run(
            from: session, to: destination,
            stamp: ArchiveCapture.Stamp(cutawayVersion: "0.1.0", savedAt: Date(), state: ArchiveState()),
            maxTextureDimension: 4096, progress: { _, _ in })

        let requests = await server.receivedFrames.flatMap { frame -> [LayerDetailRequest] in
            guard case .getLayerDetails(let request) = frame.body else { return [] }
            return request.requests
        }
        XCTAssertEqual(requests.count, 14)
        // Virtual nodes 10 to 12 have no images either (C-ARCH-07).
        for request in requests {
            let noImages = [10, 11, 12, 13, 14].contains(request.layerID)
            XCTAssertEqual(request.wantSolo, !noImages, "layer \(request.layerID)")
            XCTAssertEqual(request.wantGroup, !noImages, "layer \(request.layerID)")
            XCTAssertTrue(request.wantAttributes, "layer \(request.layerID)")
        }
        XCTAssertTrue(requests.filter { [13, 14].contains($0.layerID) }.allSatisfy(\.wantConstraints))
        await session.close()
        await server.stop()
    }
}
