import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-DET-14: from protocol 1.3 on each window's `group` is asked for first, and whether it came
/// composited stays with it. In the `hierarchy` fixture layer 1 is the only window; fully
/// expanded, it is otherwise asked for its solo.
final class WindowGroupTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    private static func compositedDemo() throws -> MockResponder {
        var responder = try MockResponder.demo()
        var image = EncodedImage.solid(pixelWidth: 4, pixelHeight: 4, bgra: 0xFFF2_F2F2)
        image.digest = Data([1, 2, 3, 4])
        image.composited = true
        responder.details[1]?.group = .full(image)
        return responder
    }

    /// An inspection as the app makes it, its first round done.
    @MainActor
    private func inspect(
        _ responder: MockResponder, version: Version = ProtocolVersion.current
    ) async throws -> (InspectionStore, MockServer, Session) {
        let steps = try MockScript.fixtures("handshake").steps
        let server = try await MockServer.start(script: MockScript(steps: steps + [.respond(responder)]))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: Self.client, protocolVersion: version,
            requestTimeout: .seconds(5))
        _ = try await session.handshake()
        let model = InspectionStore(
            session: session, newLayers: .expanded, start: InspectionStart().drawingWindowPictures)
        model.rowsWait = .zero
        model.enter()
        let done = await roundDone(model)
        XCTAssertTrue(done)
        return (model, server, session)
    }

    @MainActor
    private func roundDone(_ model: InspectionStore) async -> Bool {
        await Wait.until {
            await MainActor.run {
                model.loadState == .loaded && !model.loader.isLoading
                    && model.detailProgress.total > 0
                    && model.detailProgress.completed == model.detailProgress.total
            }
        }
    }

    private static func imageRequests(_ server: MockServer) async -> [LayerDetailRequest] {
        await server.receivedFrames.flatMap { frame -> [LayerDetailRequest] in
            guard case .getLayerDetails(let request) = frame.body else { return [] }
            return request.requests.filter { $0.wantSolo || $0.wantGroup }
        }
    }

    @MainActor
    func test_C_DET_14_theWindowsGroupIsAskedForFirstAndCountsInTheProgress() async throws {
        let (model, server, session) = try await inspect(try Self.compositedDemo())
        let requests = await Self.imageRequests(server)
        let window = requests.filter { $0.layerID == 1 }
        XCTAssertEqual(window.filter(\.wantGroup).count, 1)
        XCTAssertEqual(window.filter(\.wantSolo).count, 1, "and its solo, for 3D")
        XCTAssertEqual(model.detailProgress.total, model.layout.neededTextures.count + 1)
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_14_anAppOnOneTwoIsNotAskedForIt() async throws {
        let (_, server, session) = try await inspect(
            try MockResponder.demo(), version: Version(major: 1, minor: 2))
        let window = await Self.imageRequests(server).filter { $0.layerID == 1 }
        XCTAssertFalse(window.contains(where: \.wantGroup))
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_14_anUnchangedGroupKeepsThePicture() async throws {
        let (model, server, session) = try await inspect(try Self.compositedDemo())
        XCTAssertTrue(model.layout.usesWindowPictures)
        let revision = model.images[1]?.group?.revision
        let before = await Self.imageRequests(server).count
        model.refresh()
        let asked = await Wait.until { await Self.imageRequests(server).count > before }
        XCTAssertTrue(asked)
        let done = await roundDone(model)
        XCTAssertTrue(done)
        XCTAssertTrue(model.layout.usesWindowPictures)
        XCTAssertEqual(model.images[1]?.group?.revision, revision)
        await session.close()
        await server.stop()
    }

    func test_C_DET_14_theMarkFollowsTheGroupHeld() {
        var image = EncodedImage.solid(pixelWidth: 4, pixelHeight: 4, bgra: 0xFFFF_FFFF)
        image.composited = true
        var images = LayerImages(group: RevisionedImage(revision: 1, image: image))
        XCTAssertTrue(images.textures(layerID: 1).groupIsComposited)
        image.composited = false
        images.group = RevisionedImage(revision: 2, image: image)
        XCTAssertFalse(images.textures(layerID: 1).groupIsComposited)
    }

    @MainActor
    func test_C_DET_14_aFirstRoundWithAPlainGroupDrawsTheLayers() async throws {
        let (model, server, session) = try await inspect(try MockResponder.demo())
        XCTAssertFalse(model.layout.usesWindowPictures)
        await session.close()
        await server.stop()
    }
}
