import Combine
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// Screenshots over the connection: what is asked for and in what order, how chunks become
/// images, and how failures settle (C-DET-01, C-DET-03, C-REND-05).
final class InspectionStoreDetailsTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    private static func session(
        to server: MockServer, requestTimeout: Duration = .seconds(10)
    ) async throws -> Session {
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: Self.client, requestTimeout: requestTimeout)
        _ = try await session.handshake()
        return session
    }

    /// The `GetLayerDetails` requests the server received, in order.
    static func detailRequests(_ server: MockServer) async -> [GetLayerDetails] {
        await server.receivedFrames.compactMap { frame in
            guard case .getLayerDetails(let request) = frame.body else { return nil }
            return request
        }
    }

    static func request(_ id: UInt64, _ kind: TextureKey.Kind) -> LayerDetailRequest {
        LayerDetailRequest(
            layerID: id, wantSolo: kind == .solo, wantGroup: kind == .group, wantAttributes: false)
    }

    /// The `hierarchy` fixture fully expanded, in tree order (SceneLayoutTests). The virtual
    /// nodes 10 to 12 are asked for as layers until a later change; 13 and 14 are excluded from
    /// images (C-DET-11).
    static let fixtureRequests: [LayerDetailRequest] = [
        request(1, .solo), request(2, .solo), request(3, .group), request(4, .solo),
        request(10, .solo), request(11, .group), request(12, .group),
        request(6, .solo), request(7, .group), request(8, .group),
    ]

    /// handshake, hierarchy, then layer-details held after its first chunk.
    private static func heldServer(_ gate: MockGate) async throws -> MockServer {
        var details = try MockScript.fixtures("layer-details").steps
        details.insert(.hold(gate), at: 2)  // after the request and chunk 0 (layer 3)
        let steps = try MockScript.fixtures("handshake", "hierarchy").steps + details
        return try await MockServer.start(script: MockScript(steps: steps))
    }

    // MARK: - C-DET-01

    @MainActor
    func test_C_DET_01_theTreeComesFirstThenTheScreenshotsChunkByChunk() async throws {
        let gate = MockGate()
        let server = try await Self.heldServer(gate)
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        var layerThreeHadATexture: [Bool] = []
        let subscription = model.$layout.dropFirst().sink {
            layerThreeHadATexture.append($0.texture(of: 3) != nil)
        }

        model.enter()
        let first = await Wait.until { await model.images[3] != nil }
        XCTAssertTrue(first)
        XCTAssertEqual(layerThreeHadATexture.first, false, "the tree is laid out without images")
        XCTAssertNil(model.images[4], "the second chunk is held back")
        XCTAssertNotNil(model.layout.texture(of: 3))

        await gate.open()
        let second = await Wait.until { await model.images[4] != nil }
        XCTAssertTrue(second)
        XCTAssertNotNil(model.layout.texture(of: 4))
        subscription.cancel()

        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.map(\.requests), [Self.fixtureRequests])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_01_rowsInViewAreAskedForFirst() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "hierarchy", "layer-details"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.setVisibleLayers([7, 8])

        model.enter()
        let asked = await Wait.until { await Self.detailRequests(server).count == 1 }
        XCTAssertTrue(asked)
        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.first?.requests.map(\.layerID), [7, 8, 1, 2, 3, 4, 10, 11, 12, 6])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_01_collapsingANodeAsksForItsGroupNext() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps.append(.expect(.getLayerDetails, as: 70))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let settled = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 10, total: 10)
        }
        XCTAssertTrue(settled)

        // Layer 2 got no solo in this round; collapsed, it needs its group, which is due.
        model.setExpanded(2, false)
        XCTAssertEqual(model.detailProgress, DetailProgress(completed: 1, total: 2))
        let asked = await Wait.until { await Self.detailRequests(server).count == 2 }
        XCTAssertTrue(asked)
        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.last?.requests, [Self.request(2, .group)])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_01_nothingIsAskedForUntilTheInspectionIsEntered() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake", "hierarchy"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.reload()
        let loaded = await Wait.until { await model.loadState == .loaded }
        XCTAssertTrue(loaded)
        try await Task.sleep(for: .milliseconds(200))
        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests, [])
        XCTAssertEqual(model.detailProgress, DetailProgress(completed: 0, total: 10))

        await session.close()
        await server.stop()
    }

    /// A StreamEnd the server sends on its own, without having been sent a Cancel.
    private static func cancelledByTheServer(_ requestID: UInt32) -> Frame {
        Frame(requestID: requestID, body: .streamEnd(StreamEnd(
            status: .cancelled, chunkCount: 0, error: nil)))
    }

    @MainActor
    func test_C_DET_01_aStreamTheServerCancelsIsAskedForAgain() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += [.expect(.getLayerDetails, as: 70), .send(Self.cancelledByTheServer(70))]
        steps += try MockScript.fixtures("layer-details").steps
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let settled = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 10, total: 10)
        }
        XCTAssertTrue(settled)
        XCTAssertNil(model.notice)
        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.count, 2)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_01_aSecondStreamTheServerCancelsInARoundStopsLoading() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += [
            .expect(.getLayerDetails, as: 70), .send(Self.cancelledByTheServer(70)),
            .expect(.getLayerDetails, as: 71), .send(Self.cancelledByTheServer(71)),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let stopped = await Wait.until { await model.notice == .screenshotsFailed }
        XCTAssertTrue(stopped)
        try await Task.sleep(for: .milliseconds(200))
        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.count, 2, "asked once more, then stopped")

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_01_theFirstBatchWaitsForTheRowsInView() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "hierarchy", "layer-details"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .seconds(5)

        model.enter()
        let loaded = await Wait.until { await model.loadState == .loaded }
        XCTAssertTrue(loaded)
        try await Task.sleep(for: .milliseconds(100))
        let before = await Self.detailRequests(server)
        XCTAssertEqual(before.count, 0, "asked before the list said what it shows")

        model.setVisibleLayers([6, 7])
        let asked = await Wait.until { await Self.detailRequests(server).count == 1 }
        XCTAssertTrue(asked)
        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.first?.requests.map(\.layerID), [6, 7, 1, 2, 3, 4, 10, 11, 12, 8])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_01_withoutRowsTheFirstBatchGoesAfterAWhile() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "hierarchy", "layer-details"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .milliseconds(300)

        model.enter()
        let loaded = await Wait.until { await model.loadState == .loaded }
        XCTAssertTrue(loaded)
        let early = await Self.detailRequests(server)
        XCTAssertEqual(early.count, 0)
        let asked = await Wait.until { await Self.detailRequests(server).count == 1 }
        XCTAssertTrue(asked)
        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.map(\.requests), [Self.fixtureRequests], "in tree order")

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_01_rowsReportedWhenTheTreeIsPublishedEndTheWait() async throws {
        // The list reports its rows from its subscription to the tree: then `tree` still
        // holds the earlier value.
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "hierarchy", "layer-details"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .seconds(5)
        let subscription = model.$tree.dropFirst().sink { tree in
            if tree.contains(7) { model.setVisibleLayers([7]) }
        }

        model.enter()
        let asked = await Wait.until(within: .seconds(1)) {
            await Self.detailRequests(server).count == 1
        }
        XCTAssertTrue(asked, "the rows reported with the tree did not end the wait")
        subscription.cancel()
        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.first?.requests.first?.layerID, 7)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_01_aTreeWithTheRowsInViewEndsAnEarlierWait() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps.append(.expect(.getLayerDetails, as: 61))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .seconds(5)

        model.enter()
        let loaded = await Wait.until { await model.loadState == .loaded }
        XCTAssertTrue(loaded)
        model.setVisibleLayers([7])
        let settled = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 10, total: 10)
        }
        XCTAssertTrue(settled)

        // A tree without the row in view starts a wait; the next tree has it again.
        model.apply(Hierarchy(nodes: [LayerTreeTests.node(1)], keyWindowID: 0))
        model.apply(try Fixtures.hierarchy())
        let asked = await Wait.until(within: .seconds(1)) {
            await Self.detailRequests(server).count == 2
        }
        XCTAssertTrue(asked, "the first batch still waited for rows it already had")

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_01_leavingWhileWaitingForRowsAsksNothing() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake", "hierarchy"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .milliseconds(300)

        model.enter()
        let loaded = await Wait.until { await model.loadState == .loaded }
        XCTAssertTrue(loaded)
        model.leave()
        try await Task.sleep(for: .milliseconds(600))
        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.count, 0)

        await session.close()
        await server.stop()
    }

    // MARK: - C-DET-02: progress

    @MainActor
    func test_C_DET_02_progressCountsTheLayersThatAreSettled() async throws {
        let gate = MockGate()
        let server = try await Self.heldServer(gate)
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let first = await Wait.until { await model.images[3] != nil }
        XCTAssertTrue(first)
        XCTAssertEqual(model.detailProgress, DetailProgress(completed: 1, total: 10))

        await gate.open()
        // Chunk 1 brings layer 4; the stream completes and the rest of the batch is settled.
        let done = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 10, total: 10)
        }
        XCTAssertTrue(done)

        await session.close()
        await server.stop()
    }

    // MARK: - C-DET-03

    @MainActor
    func test_C_DET_03_layersThatFailAreSettledWithoutAnImageAndNotAskedForAgain() async throws {
        // layer-details-edge: 3 and 8 come with a group, 9 failed to capture, 7 brought
        // nothing though its group was asked for; the others are left out.
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "hierarchy", "layer-details-edge"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let done = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 10, total: 10)
        }
        XCTAssertTrue(done)
        XCTAssertEqual(Set(model.images.keys), [3, 8])
        XCTAssertNil(model.notice, "a layer that fails is not reported")

        try await Task.sleep(for: .milliseconds(200))
        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.count, 1)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    // MARK: - C-REND-05

    @MainActor
    func test_C_REND_05_requestsCarryTheTextureLimit() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "hierarchy", "layer-details"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(
            session: session, maxTextureDimension: 4_096, newLayers: .expanded)

        model.enter()
        let asked = await Wait.until { await Self.detailRequests(server).count == 1 }
        XCTAssertTrue(asked)
        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.first?.maxTextureDimension, 4_096)

        await session.close()
        await server.stop()
    }

    // MARK: - When requests fail

    @MainActor
    func test_C_CONN_04_aScreenshotRequestThatTimesOutStopsLoadingWithANotice() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake", "hierarchy"))
        let session = try await Self.session(to: server, requestTimeout: .milliseconds(300))
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let stopped = await Wait.until { await model.notice == .screenshotsFailed }
        XCTAssertTrue(stopped)
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.tree.count, 14)

        // Not tried again on its own.
        try await Task.sleep(for: .milliseconds(500))
        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.count, 1)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_CONN_07_aClosedConnectionStopsLoadingQuietly() async throws {
        // A session that never shook hands answers every request with `disconnected`.
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        // Not about the wait for rows: the first batch goes at once.
        model.rowsWait = .zero
        model.enter()
        // The hierarchy request fails at once; a tree is then taken in as if one had come.
        try await Task.sleep(for: .milliseconds(100))
        model.apply(try Fixtures.hierarchy())
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(model.batchesStarted, 1, "no second batch after the connection is gone")
        XCTAssertNil(model.notice)

        model.setExpanded(4, false)
        model.setVisibleLayers([3])
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.batchesStarted, 1)
    }

    @MainActor
    func test_C_CONN_07_aClosedConnectionEndsTheHierarchyLoading() async throws {
        var steps = try MockScript.fixtures("handshake").steps
        steps += [.expect(.getHierarchy, as: 2), .close]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        XCTAssertTrue(model.attributes.isTreeLoading)
        let settled = await Wait.until { await !model.isLoading }
        XCTAssertTrue(settled, "the request never ended")
        XCTAssertFalse(model.attributes.isTreeLoading)
        XCTAssertEqual(model.loadState, .loading, "no failure is shown (C-CONN-07)")

        await server.stop()
    }

    // MARK: - C-DET-02: leaving and coming back

    @MainActor
    func test_C_DET_02_leavingCancelsTheScreenshotsAndComingBackAsksAgain() async throws {
        var steps = try MockScript.fixtures(
            "handshake", "hierarchy", "layer-details-cancelled").steps
        steps += [
            .expect(.getHierarchy, as: 60),
            .send(Frame(requestID: 60, body: .hierarchy(try Fixtures.hierarchy()))),
            .expect(.getLayerDetails, as: 61),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let first = await Wait.until { await model.images[2] != nil }
        XCTAssertTrue(first)
        model.leave()
        let cancelled = await Wait.until {
            await server.receivedFrames.contains { MessageKind($0.body) == .cancel }
        }
        XCTAssertTrue(cancelled)

        model.enter()
        let again = await Wait.until { await server.receivedFrames.count == 6 }
        XCTAssertTrue(again)
        let frames = await server.receivedFrames
        XCTAssertEqual(
            frames.map { MessageKind($0.body) },
            [.hello, .getHierarchy, .getLayerDetails, .cancel, .getHierarchy, .getLayerDetails])
        XCTAssertEqual(frames[3].body, .cancel(Cancel(targetRequestID: frames[2].requestID)))
        // What arrived went on leaving, and is asked for again (C-DET-10).
        XCTAssertNil(model.images[2], "what arrived outlived the visit")
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_02_aBatchCancelledBeforeItIsSentSendsNothing() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "hierarchy", "layer-details"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let settled = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 10, total: 10)
        }
        XCTAssertTrue(settled)

        // In one turn of the main actor: collapsing 2 starts a batch for its group, and
        // leaving cancels it before its task ran.
        model.setExpanded(2, false)
        model.leave()
        try await Task.sleep(for: .milliseconds(200))

        let kinds = await server.receivedFrames.map { MessageKind($0.body) }
        XCTAssertEqual(kinds, [.hello, .getHierarchy, .getLayerDetails])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_02_aNewRoundDoesNotShowTheEarlierRoundsProgress() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += [
            .expect(.getLayerDetails, as: 3),
            .send(try FrameCodec.decode(
                try Fixtures.data(scenario: "layer-details", file: "02-s2c-chunk-0.bin"))),
            .send(Frame(requestID: 3, body: .streamEnd(StreamEnd(
                status: .failed, chunkCount: 1,
                error: ServerError(code: .appNotActive, message: nil))))),
            .expect(.getHierarchy, as: 50),
            .send(Frame(requestID: 50, body: .hierarchy(try Fixtures.hierarchy()))),
            .expect(.getLayerDetails, as: 51),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        // What the top bar would show, each time either value changes. @Published sends
        // before the value is stored, so the other value is read from the model.
        var shown: [(notice: InspectionStore.Notice?, progress: DetailProgress)] = []
        let notices = model.$notice.dropFirst().sink { shown.append(($0, model.detailProgress)) }
        let progress = model.$detailProgress.dropFirst().sink { shown.append((model.notice, $0)) }

        model.enter()
        let paused = await Wait.until { await model.notice == .appNotActive }
        XCTAssertTrue(paused)
        XCTAssertEqual(model.detailProgress, DetailProgress(completed: 1, total: 10))

        model.appStateDidChange(.active)
        let again = await Wait.until { await Self.detailRequests(server).count == 2 }
        XCTAssertTrue(again)
        notices.cancel()
        progress.cancel()

        let afterNotice = shown.drop { $0.notice != .appNotActive }
        XCTAssertFalse(
            afterNotice.contains {
                $0.notice == nil && $0.progress == DetailProgress(completed: 1, total: 10)
            },
            "the earlier round's progress was shown again: \(afterNotice)")

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_02_leavingDropsTheQueuedReload() async throws {
        let gate = MockGate()
        var hierarchy = try MockScript.fixtures("hierarchy").steps
        hierarchy.insert(.hold(gate), at: 1)  // between the request and its answer
        let server = try await MockServer.start(
            script: MockScript(steps: try MockScript.fixtures("handshake").steps + hierarchy))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let asked = await Wait.until { await server.receivedFrames.count == 2 }
        XCTAssertTrue(asked)
        model.reload()  // queued behind the one under way
        model.leave()
        await gate.open()

        let loaded = await Wait.until { await model.loadState == .loaded }
        XCTAssertTrue(loaded)
        try await Task.sleep(for: .milliseconds(200))
        let kinds = await server.receivedFrames.map { MessageKind($0.body) }
        XCTAssertEqual(kinds, [.hello, .getHierarchy])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    // MARK: - C-DET-04

    @MainActor
    func test_C_DET_04_theTreeLoadsWhenTheAppBecomesActive() async throws {
        var steps = try MockScript.fixtures("handshake", "app-not-active").steps
        steps += [
            .expect(.getHierarchy, as: 50),
            .send(Frame(requestID: 50, body: .hierarchy(try Fixtures.hierarchy()))),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let failed = await Wait.until { await model.loadState == .failed(.appNotActive) }
        XCTAssertTrue(failed)
        model.appStateDidChange(.inactive)
        model.appStateDidChange(.active)
        let loaded = await Wait.until { await model.loadState == .loaded }
        XCTAssertTrue(loaded)
        XCTAssertEqual(model.tree.count, 14)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_04_screenshotsStopWhileTheAppIsNotActiveAndGoOnAfter() async throws {
        var steps = try MockScript.fixtures(
            "handshake", "hierarchy", "layer-details-failed").steps
        steps += [
            .expect(.getHierarchy, as: 50),
            .send(Frame(requestID: 50, body: .hierarchy(try Fixtures.hierarchy()))),
            .expect(.getLayerDetails, as: 51),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let paused = await Wait.until { await model.notice == .appNotActive }
        XCTAssertTrue(paused)
        XCTAssertEqual(model.loadState, .loaded, "the tree stays")
        XCTAssertEqual(model.tree.count, 14)

        model.appStateDidChange(.active)
        let resumed = await Wait.until { await Self.detailRequests(server).count == 2 }
        XCTAssertTrue(resumed)
        XCTAssertNil(model.notice)
        let kinds = await server.receivedFrames.map { MessageKind($0.body) }
        XCTAssertEqual(
            kinds, [.hello, .getHierarchy, .getLayerDetails, .getHierarchy, .getLayerDetails])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_04_aTreeThatIsShownStaysWhenTheAppIsNotActive() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "hierarchy", "app-not-active"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.reload()
        let loaded = await Wait.until { await model.loadState == .loaded }
        XCTAssertTrue(loaded)
        model.reload()
        let noticed = await Wait.until { await model.notice == .appNotActive }
        XCTAssertTrue(noticed)
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.tree.count, 14)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_04_anAppActiveAgainBeforeItsFailureArrivesLoadsAgain() async throws {
        let gate = MockGate()
        var notActive = try MockScript.fixtures("app-not-active").steps
        notActive.insert(.hold(gate), at: 2)  // after the request, before the Error
        var steps = try MockScript.fixtures("handshake").steps + notActive
        steps += [
            .expect(.getHierarchy, as: 50),
            .send(Frame(requestID: 50, body: .hierarchy(try Fixtures.hierarchy()))),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let asked = await Wait.until { await server.receivedFrames.count == 2 }
        XCTAssertTrue(asked)
        // The app is active again before the failure of the request made while it was not.
        model.appStateDidChange(.active)
        await gate.open()

        let loaded = await Wait.until { await model.loadState == .loaded }
        XCTAssertTrue(loaded, "stayed \(model.loadState)")

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_04_screenshotsGoOnWhenTheAppIsActiveBeforeTheirFailureArrives() async throws {
        let gate = MockGate()
        var failed = try MockScript.fixtures("layer-details-failed").steps
        failed.insert(.hold(gate), at: 2)  // after the AppStateChanged, before the StreamEnd
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps + failed
        steps += [
            .expect(.getHierarchy, as: 50),
            .send(Frame(requestID: 50, body: .hierarchy(try Fixtures.hierarchy()))),
            .expect(.getLayerDetails, as: 51),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .zero

        model.enter()
        let asked = await Wait.until { await Self.detailRequests(server).count == 1 }
        XCTAssertTrue(asked)
        model.appStateDidChange(.active)
        await gate.open()

        let resumed = await Wait.until { await Self.detailRequests(server).count == 2 }
        XCTAssertTrue(resumed)
        XCTAssertNil(model.notice)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_04_aFailureFromTheCurrentActivePeriodIsShown() async throws {
        // active, then the request, then its failure: the failure is current and is shown.
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "app-not-active"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.appStateDidChange(.active)
        model.enter()
        let failed = await Wait.until { await model.loadState == .failed(.appNotActive) }
        XCTAssertTrue(failed)
        try await Task.sleep(for: .milliseconds(200))
        let kinds = await server.receivedFrames.map { MessageKind($0.body) }
        XCTAssertEqual(kinds, [.hello, .getHierarchy], "not asked again")

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_04_aClosedInspectionDoesNotReloadWhenTheAppBecomesActive() async throws {
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "app-not-active"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let failed = await Wait.until { await model.loadState == .failed(.appNotActive) }
        XCTAssertTrue(failed)
        model.leave()
        model.appStateDidChange(.active)
        try await Task.sleep(for: .milliseconds(200))
        let count = await server.receivedFrames.count
        XCTAssertEqual(count, 2, "Hello and the one GetHierarchy")

        await session.close()
        await server.stop()
    }

    // MARK: - Review findings

    @MainActor
    func test_C_DET_01_whoeverFollowsTheTreeFindsTheNewTreesNeeds() async throws {
        // A subscriber to the tree that reports the visible rows asks for a batch at once; it
        // must be made of the new tree's needs: 8 is gone (and 20, new, has no area).
        let steps = try MockScript.fixtures("handshake").steps + [
            .expect(.getHierarchy, as: 50),
            .send(Frame(requestID: 50, body: .hierarchy(try InspectionStoreTests.changed()))),
            .expect(.getLayerDetails, as: 51),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        let subscription = model.$tree.dropFirst().sink { tree in
            if tree.contains(20) { model.setVisibleLayers([7]) }
        }

        model.enter()
        let asked = await Wait.until { await Self.detailRequests(server).count == 1 }
        XCTAssertTrue(asked)
        subscription.cancel()
        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.first?.requests.map(\.layerID), [7, 1, 2, 3, 4, 10, 11, 12, 6])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_01_collapsingANodeWhileItsSoloIsOnTheWayAsksForItsGroupNext() async throws {
        // Layer 6's solo is asked for and never comes; 6 is collapsed while the batch is held.
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        var details = try MockScript.fixtures("layer-details").steps
        details.insert(.hold(gate), at: 2)
        steps += details + [.expect(.getLayerDetails, as: 70)]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let first = await Wait.until { await model.images[3] != nil }
        XCTAssertTrue(first)
        model.setExpanded(6, false)
        await gate.open()

        let asked = await Wait.until { await Self.detailRequests(server).count == 2 }
        XCTAssertTrue(asked)
        let requests = await Self.detailRequests(server)
        XCTAssertEqual(requests.last?.requests, [Self.request(6, .group)])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_02_aBatchFromAnEarlierRoundAddsNothing() async throws {
        // A new hierarchy arrives while the first batch is held after its first chunk: the
        // rest of that batch (layer 4) is not taken in, and the new round counts from zero.
        let gate = MockGate()
        let server = try await Self.heldServer(gate)
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let first = await Wait.until { await model.images[3] != nil }
        XCTAssertTrue(first)
        model.apply(try Fixtures.hierarchy())
        await gate.open()

        let cancelled = await Wait.until {
            await server.receivedFrames.contains { MessageKind($0.body) == .cancel }
        }
        XCTAssertTrue(cancelled)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(model.images[4])
        XCTAssertEqual(model.detailProgress, DetailProgress(completed: 0, total: 10))

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_02_comingBackAsksForTheTreeBeforeAnyScreenshot() async throws {
        // A new list reports its rows as soon as it is built, before the hierarchy it asked
        // for has arrived. No screenshots of the old tree are asked for in between.
        var steps = try MockScript.fixtures(
            "handshake", "hierarchy", "layer-details-cancelled").steps
        steps += [
            .expect(.getHierarchy, as: 60),
            .pause(.milliseconds(100)),
            .send(Frame(requestID: 60, body: .hierarchy(try Fixtures.hierarchy()))),
            .expect(.getLayerDetails, as: 61),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)

        model.enter()
        let first = await Wait.until { await model.images[2] != nil }
        XCTAssertTrue(first)
        model.leave()
        let cancelled = await Wait.until {
            await server.receivedFrames.contains { MessageKind($0.body) == .cancel }
        }
        XCTAssertTrue(cancelled)

        model.enter()
        model.setVisibleLayers([])  // what a new list reports before it has rows
        let again = await Wait.until { await Self.detailRequests(server).count >= 2 }
        XCTAssertTrue(again)
        try await Task.sleep(for: .milliseconds(200))
        let kinds = await server.receivedFrames.map { MessageKind($0.body) }
        XCTAssertEqual(
            kinds,
            [.hello, .getHierarchy, .getLayerDetails, .cancel, .getHierarchy, .getLayerDetails])

        await session.close()
        await server.stop()
    }
}
