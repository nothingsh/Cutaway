import Combine
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-DET-12 and C-DET-13: requests give the digests of the images held, and an image the app
/// answers as unchanged is kept as it is. The `MockResponder` answers unchanged whenever a
/// request gives the digest of the image it would send (P-IMG-05). In the fully expanded
/// `hierarchy` fixture, layer 3 and 8 are leaves asked for their group, layer 4 has sublayers
/// and is asked for its solo.
final class ImageReuseTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    private static func server(_ responder: MockResponder) async throws -> MockServer {
        let steps = try MockScript.fixtures("handshake").steps
        return try await MockServer.start(script: MockScript(steps: steps + [.respond(responder)]))
    }

    private static func session(
        to server: MockServer, version: Version = ProtocolVersion.current
    ) async throws -> Session {
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: client, protocolVersion: version,
            requestTimeout: .seconds(5))
        _ = try await session.handshake()
        return session
    }

    /// Every request item for an image, in the order sent.
    private static func imageRequests(_ server: MockServer) async -> [LayerDetailRequest] {
        await server.receivedFrames.flatMap { frame -> [LayerDetailRequest] in
            guard case .getLayerDetails(let request) = frame.body else { return [] }
            return request.requests.filter { $0.wantSolo || $0.wantGroup }
        }
    }

    private static func digest(of request: LayerDetailRequest) -> Data? {
        request.knownSoloDigest ?? request.knownGroupDigest
    }

    /// Counts the images decompressed.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func add() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    /// An inspection of the responder's app, every node expanded, with its first round done.
    @MainActor
    private func inspect(
        _ responder: MockResponder, version: Version = ProtocolVersion.current,
        decoded: Counter = Counter()
    ) async throws -> (InspectionStore, MockServer, Session) {
        let server = try await Self.server(responder)
        let session = try await Self.session(to: server, version: version)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .zero
        model.decodeImage = { image in
            decoded.add()
            return try image.decoded()
        }
        model.enter()
        let done = await roundDone(model)
        XCTAssertTrue(done)
        let capabilities = await Wait.until { await MainActor.run { model.canRefreshSubtrees } }
        XCTAssertTrue(capabilities)
        return (model, server, session)
    }

    @MainActor
    private func roundDone(_ model: InspectionStore) async -> Bool {
        await Wait.until {
            await MainActor.run {
                model.loadState == .loaded && model.detailProgress.total > 0
                    && model.detailProgress.completed == model.detailProgress.total
            }
        }
    }

    /// ⌘R, then waits for the round's requests to go out and come back.
    @MainActor
    private func refresh(_ model: InspectionStore, _ server: MockServer) async -> [LayerDetailRequest] {
        let before = await Self.imageRequests(server).count
        model.refresh()
        let asked = await Wait.until { await Self.imageRequests(server).count > before }
        XCTAssertTrue(asked)
        let done = await roundDone(model)
        XCTAssertTrue(done)
        return Array(await Self.imageRequests(server).dropFirst(before))
    }

    private static func image(_ bgra: UInt32, digest: Data) -> EncodedImage {
        var image = EncodedImage.solid(pixelWidth: 4, pixelHeight: 4, bgra: bgra)
        image.digest = digest
        return image
    }

    // MARK: - C-DET-12

    @MainActor
    func test_C_DET_12_theFirstRequestsGiveNoDigestsAndARefreshGivesThoseReceived() async throws {
        let (model, server, session) = try await inspect(try MockResponder.demo())
        let first = await Self.imageRequests(server)
        XCTAssertFalse(first.isEmpty)
        XCTAssertTrue(first.allSatisfy { Self.digest(of: $0) == nil })
        let held = model.images

        let second = await refresh(model, server)
        XCTAssertFalse(second.isEmpty)
        for request in second {
            let kind: TextureKey.Kind = request.wantSolo ? .solo : .group
            let expected = held[request.layerID].flatMap { $0[kind]?.image.digest }
            XCTAssertEqual(Self.digest(of: request), expected, "layer \(request.layerID)")
            // Only the kind asked for.
            if kind == .solo { XCTAssertNil(request.knownGroupDigest) } else { XCTAssertNil(request.knownSoloDigest) }
        }
        let given = Set(second.filter { Self.digest(of: $0) != nil }.map(\.layerID))
        XCTAssertEqual(given, [3, 4, 8], "the layers the fixtures have images of")

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_12_aReplacedImageGivesTheNewDigest() async throws {
        let (model, server, session) = try await inspect(try MockResponder.demo())
        let new = Data(repeating: 7, count: 16)
        await model.applyDetails([LayerDetail(
            layerID: 3, status: .ok, solo: nil, group: .full(Self.image(0xFF00_FF00, digest: new)),
            attributeGroups: [])])

        let second = await refresh(model, server)
        XCTAssertEqual(second.first { $0.layerID == 3 }?.knownGroupDigest, new)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_12_aSoloRequestGivesTheGroupsDigestWhenOnlyTheGroupIsHeld() async throws {
        let (model, server, session) = try await inspect(try MockResponder.demo())
        // The fixture's solo and group of layer 4 are the same picture (README).
        let group = try XCTUnwrap(model.images[4]?.solo)
        // Layer 4's images go, then only its group comes back.
        await model.applyDetails([LayerDetail(
            layerID: 4, status: .captureFailed, solo: nil, group: nil, attributeGroups: [])])
        await model.applyDetails([LayerDetail(
            layerID: 4, status: .ok, solo: nil, group: .full(group.image), attributeGroups: [])])
        XCTAssertNil(model.images[4]?.solo)
        XCTAssertEqual(model.knownDigest(for: TextureNeed(layerID: 4, kind: .solo)), group.image.digest)

        let second = await refresh(model, server)
        let solo = try XCTUnwrap(second.first { $0.layerID == 4 })
        XCTAssertTrue(solo.wantSolo)
        XCTAssertEqual(solo.knownSoloDigest, group.image.digest)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_12_aSessionAtOneTwoGivesNone() async throws {
        let (model, server, session) = try await inspect(
            try MockResponder.demo(), version: Version(major: 1, minor: 2))
        let negotiated = await session.negotiatedVersion
        XCTAssertEqual(negotiated, Version(major: 1, minor: 2))
        let second = await refresh(model, server)
        XCTAssertFalse(second.isEmpty)
        XCTAssertTrue(second.allSatisfy { Self.digest(of: $0) == nil })

        await session.close()
        await server.stop()
    }

    // MARK: - C-DET-13

    @MainActor
    func test_C_DET_13_aRefreshWhereNothingChangedDecompressesAndRedrawsNothing() async throws {
        let decoded = Counter()
        let (model, server, session) = try await inspect(try MockResponder.demo(), decoded: decoded)
        let held = model.images
        let revision = model.nextImageRevision
        let decodedBefore = decoded.count
        XCTAssertGreaterThan(decodedBefore, 0)
        var arriving = 0, changed = 0
        let subscriptions = [
            model.arrivingPixels.sink { _ in arriving += 1 },
            model.imagesChanged.sink { _ in changed += 1 },
        ]

        _ = await refresh(model, server)
        XCTAssertEqual(decoded.count, decodedBefore, "nothing decompressed")
        XCTAssertEqual(arriving, 0, "no new textures")
        XCTAssertEqual(changed, 0, "nothing drawn again")
        XCTAssertEqual(model.nextImageRevision, revision)
        XCTAssertEqual(model.images, held)
        for id: UInt64 in [3, 4, 8] {
            XCTAssertEqual(model.images[id]?.solo?.image, held[id]?.solo?.image)
            XCTAssertEqual(model.images[id]?.group?.image, held[id]?.group?.image)
        }
        XCTAssertNil(model.notice)
        subscriptions.forEach { $0.cancel() }

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_13_onlyTheRedrawnImageIsReplaced() async throws {
        let decoded = Counter()
        let (model, server, session) = try await inspect(try MockResponder.demo(), decoded: decoded)
        // Held under another digest: the app's own image counts as redrawn.
        let green = try XCTUnwrap(model.images[4]?.solo?.image)
        var other = green
        other.digest = Data(repeating: 9, count: 16)
        await model.applyDetails([LayerDetail(
            layerID: 4, status: .ok, solo: .full(other), group: nil, attributeGroups: [])])
        let held = model.images
        let decodedBefore = decoded.count
        var changed: [UInt64] = []
        let subscription = model.imagesChanged.sink { changed += $0 }

        _ = await refresh(model, server)
        XCTAssertEqual(decoded.count, decodedBefore + 1)
        XCTAssertEqual(changed, [4])
        XCTAssertNotEqual(model.images[4]?.solo, held[4]?.solo)
        XCTAssertEqual(model.images[4]?.solo?.image.digest, green.digest)
        XCTAssertEqual(model.images[3], held[3])
        XCTAssertEqual(model.images[8], held[8])
        subscription.cancel()

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_13_anUnchangedImageThatNoLongerMatchesIsAskedForNextRound() async throws {
        let gate = MockGate()
        var responder = try MockResponder.demo()
        // Holds the refresh's batch that gives layer 3's digest.
        responder.holdBeforeDetails = ({ request in
            request.requests.contains { $0.layerID == 3 && $0.knownGroupDigest != nil }
        }, gate)
        let (model, server, session) = try await inspect(responder)
        let red = try XCTUnwrap(model.images[3]?.group?.image.digest)

        let before = await Self.imageRequests(server).count
        model.refresh()
        let asked = await Wait.until { await Self.imageRequests(server).count > before }
        XCTAssertTrue(asked)
        // Meanwhile the image held is replaced: the answer will name the old one.
        let new = Data(repeating: 5, count: 16)
        await model.applyDetails([LayerDetail(
            layerID: 3, status: .ok, solo: nil, group: .full(Self.image(0xFF00_FF00, digest: new)),
            attributeGroups: [])])
        await gate.open()
        let done = await roundDone(model)
        XCTAssertTrue(done)
        XCTAssertEqual(model.images[3]?.group?.image.digest, new, "the image held stays")
        XCTAssertNil(model.notice)
        XCTAssertEqual(model.loadState, .loaded)
        let held = await Self.imageRequests(server).dropFirst(before).first { $0.layerID == 3 }
        XCTAssertEqual(held?.knownGroupDigest, red)

        let next = await refresh(model, server)
        XCTAssertEqual(next.first { $0.layerID == 3 }?.knownGroupDigest, new)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_13_aLeafsUnchangedGroupKeepsItsSoloAndIsNotAskedForAgain() async throws {
        let (model, server, session) = try await inspect(try MockResponder.demo())
        let group = try XCTUnwrap(model.images[3]?.group)
        // A solo held too, as from an archive or an export.
        await model.applyDetails([LayerDetail(
            layerID: 3, status: .ok, solo: .full(group.image), group: nil, attributeGroups: [])])
        let held = try XCTUnwrap(model.images[3])
        XCTAssertNotNil(held.solo)

        let second = await refresh(model, server)
        XCTAssertEqual(model.images[3], held)
        XCTAssertEqual(second.filter { $0.layerID == 3 }.count, 1)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_13_aSoloGivenTheGroupsDigestIsThatImage() async throws {
        let decoded = Counter()
        let (model, server, session) = try await inspect(try MockResponder.demo(), decoded: decoded)
        let group = try XCTUnwrap(model.images[4]?.solo)
        await model.applyDetails([LayerDetail(
            layerID: 4, status: .captureFailed, solo: nil, group: nil, attributeGroups: [])])
        await model.applyDetails([LayerDetail(
            layerID: 4, status: .ok, solo: nil, group: .full(group.image), attributeGroups: [])])
        let heldGroup = try XCTUnwrap(model.images[4]?.group)
        let decodedBefore = decoded.count

        _ = await refresh(model, server)
        let solo = try XCTUnwrap(model.images[4]?.solo, "the solo is the group's picture")
        XCTAssertEqual(solo.image, heldGroup.image)
        XCTAssertNotEqual(solo.revision, heldGroup.revision, "a key of its own")
        XCTAssertEqual(model.images[4]?.group, heldGroup)
        XCTAssertEqual(decoded.count, decodedBefore)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_13_anUnchangedSoloWhoseDigestDiffersIsNotTakenFromTheGroup() async throws {
        var responder = try MockResponder.demo()
        // An app that answers layer 4's solo as unchanged under a digest of its own.
        responder.details[4]?.solo = .unchanged(digest: Data(repeating: 3, count: 16))
        let (model, server, session) = try await inspect(responder)
        XCTAssertNil(model.images[4]?.solo)
        let group = Self.image(0xFF00_FF00, digest: Data(repeating: 4, count: 16))
        await model.applyDetails([LayerDetail(
            layerID: 4, status: .ok, solo: nil, group: .full(group), attributeGroups: [])])

        let second = await refresh(model, server)
        XCTAssertEqual(second.first { $0.layerID == 4 }?.knownSoloDigest, group.digest)
        XCTAssertNil(model.images[4]?.solo, "not the group's picture: the digests differ")
        XCTAssertEqual(model.images[4]?.group?.image, group)
        XCTAssertNil(model.notice)

        await session.close()
        await server.stop()
    }
}
