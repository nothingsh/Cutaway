import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// Refreshing an inspection (C-DET-05): the hierarchy and a new round of screenshots are
/// asked for again, what is shown stays until the new arrives, and the state is kept.
final class RefreshTests: XCTestCase {
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

    /// The newest revision among a layer's images.
    @MainActor
    private static func revision(of id: UInt64, in model: InspectionStore) -> UInt64? {
        let images = model.images[id]
        return [images?.solo?.revision, images?.group?.revision].compactMap { $0 }.max()
    }

    private static func count(
        _ kind: MessageKind, _ server: MockServer
    ) async -> Int {
        await server.receivedFrames.filter { MessageKind($0.body) == kind }.count
    }

    @MainActor
    func test_C_DET_05_refreshingAsksForTheHierarchyAndANewRound() async throws {
        let server = try await MockServer.start(
            script: try .fixtures(
                "handshake", "hierarchy", "layer-details", "hierarchy", "layer-details"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .zero
        model.enter()
        let first = await Wait.until { await model.images[4] != nil }
        XCTAssertTrue(first)
        let revision = try XCTUnwrap(Self.revision(of: 4, in: model))

        model.refresh()
        let asked = await Wait.until {
            await Self.count(.getLayerDetails, server) == 2
        }
        XCTAssertTrue(asked)
        let hierarchies = await Self.count(.getHierarchy, server)
        XCTAssertEqual(hierarchies, 2)
        let renewed = await Wait.until { await (Self.revision(of: 4, in: model) ?? 0) > revision }
        XCTAssertTrue(renewed, "the new round brought a new image")
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_05_theImagesStayUntilNewOnesArrive() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures(
            "handshake", "hierarchy", "layer-details", "hierarchy").steps
        // The second round's request comes in, and its answer waits for the gate.
        var second = try MockScript.fixtures("layer-details").steps
        second.insert(.hold(gate), at: 1)
        steps += second
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .zero
        model.enter()
        let first = await Wait.until { await model.images[4] != nil }
        XCTAssertTrue(first)
        let revision = try XCTUnwrap(Self.revision(of: 4, in: model))

        model.refresh()
        let asked = await Wait.until { await Self.count(.getLayerDetails, server) == 2 }
        XCTAssertTrue(asked)
        XCTAssertNotNil(model.images[3], "the old image is still shown")
        XCTAssertNotNil(model.images[4])
        XCTAssertNotNil(model.layout.texture(of: 4))

        await gate.open()
        let replaced = await Wait.until { await (Self.revision(of: 4, in: model) ?? 0) > revision }
        XCTAssertTrue(replaced, "the new round brought new images")

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_05_aRefreshDuringOneIsMadeOnceAfterIt() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake").steps
        var hierarchy = try MockScript.fixtures("hierarchy").steps
        hierarchy.insert(.hold(gate), at: 1)  // the first answer waits
        steps += hierarchy + (try MockScript.fixtures("hierarchy").steps)
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.enter()
        let asked = await Wait.until { await Self.count(.getHierarchy, server) == 1 }
        XCTAssertTrue(asked)

        model.refresh()
        model.refresh()
        model.refresh()
        await gate.open()
        let again = await Wait.until { await Self.count(.getHierarchy, server) == 2 }
        XCTAssertTrue(again)
        try await Task.sleep(for: .milliseconds(300))
        let total = await Self.count(.getHierarchy, server)
        XCTAssertEqual(total, 2, "three refreshes under way made one more request")

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_05_theStateIsKeptThroughARefresh() async throws {
        // A session without a connection: requests fail at once, and are still counted.
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        model.enter()
        let settled = await Wait.until { await !model.isLoading }
        XCTAssertTrue(settled)
        model.apply(try Fixtures.hierarchy())
        model.focus(on: 2)
        model.setExpanded(6, false)
        model.select(4)
        model.pan(by: 12, 3)
        let camera = model.camera

        model.refresh()
        XCTAssertTrue(model.isLoading, "the hierarchy is asked for again")
        let answered = await Wait.until { await !model.isLoading }
        XCTAssertTrue(answered)
        // Counted from here: on this session the selection's request fails as disconnected,
        // which leaves nothing to stop it being asked again once no hierarchy is on its way,
        // and whether that comes before this point depends on which request ends first.
        let attributeRequests = model.attributes.requestsStarted
        model.apply(try Fixtures.hierarchy())  // what the app answers

        XCTAssertFalse(model.isExpanded(6))
        XCTAssertEqual(model.selectedLayerID, 4)
        XCTAssertEqual(model.focusedLayerID, 2)
        XCTAssertEqual(model.camera, camera)
        XCTAssertEqual(
            model.attributes.requestsStarted, attributeRequests + 1,
            "the selected layer's attributes are asked for again")
    }

    @MainActor
    func test_C_DET_05_aRefreshThatFailsKeepsTheLayersShown() async throws {
        // The refresh's request for the hierarchy gets no answer and times out.
        let steps =
            try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
                + [.expect(.getHierarchy, as: 60)]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server, requestTimeout: .milliseconds(300))
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .zero
        model.enter()
        let first = await Wait.until { await model.images[4] != nil }
        XCTAssertTrue(first)

        model.refresh()
        let failed = await Wait.until { await model.notice == .layersFailed }
        XCTAssertTrue(failed)
        XCTAssertEqual(model.loadState, .loaded, "what is shown stays")
        XCTAssertEqual(model.tree.count, 14)
        XCTAssertNotNil(model.images[4])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_05_aClosedInspectionDoesNotRefresh() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake", "hierarchy"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.refresh()
        XCTAssertFalse(model.isLoading)
        try await Task.sleep(for: .milliseconds(200))
        let asked = await Self.count(.getHierarchy, server)
        XCTAssertEqual(asked, 0)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_05_refreshingStartsScreenshotsThatStoppedOnAFailure() async throws {
        // The first round's request gets no answer and times out; the refresh is answered.
        let steps =
            try MockScript.fixtures("handshake", "hierarchy").steps
                + [.expect(.getLayerDetails, as: 50)]
                + (try MockScript.fixtures("hierarchy", "layer-details").steps)
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server, requestTimeout: .milliseconds(300))
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .zero
        model.enter()
        let stopped = await Wait.until { await model.notice == .screenshotsFailed }
        XCTAssertTrue(stopped)

        model.refresh()
        let loaded = await Wait.until { await model.images[4] != nil }
        XCTAssertTrue(loaded)
        XCTAssertNil(model.notice)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    // MARK: - Reloads, rounds of screenshots and entering again

    @MainActor
    func test_C_DET_04_aReloadThatFindsTheAppInactiveStopsAskingForScreenshots() async throws {
        // The first load completes; then the app goes to the background and the refresh's
        // request for the hierarchy is refused.
        let server = try await MockServer.start(
            script: try .fixtures("handshake", "hierarchy", "layer-details", "app-not-active"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .zero
        model.enter()
        let first = await Wait.until { await model.images[4] != nil }
        XCTAssertTrue(first)

        model.refresh()
        let refused = await Wait.until { await model.notice == .appNotActive }
        XCTAssertTrue(refused)
        XCTAssertEqual(model.loadState, .loaded, "the tree shown stays")

        // Collapsing needs a new screenshot; nothing is asked for while the app is inactive.
        let before = await Self.count(.getLayerDetails, server)
        model.setExpanded(2, false)
        try await Task.sleep(for: .milliseconds(200))
        let after = await Self.count(.getLayerDetails, server)
        XCTAssertEqual(after, before, "a request that could only fail")

        // Back in the foreground: loading starts over, and screenshots with it.
        model.appStateDidChange(.active)
        XCTAssertTrue(model.isLoading)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_01_enteringAgainAsksForTheRowsInViewFirst() async throws {
        let server = try await MockServer.start(
            script: try .fixtures(
                "handshake", "hierarchy", "layer-details", "hierarchy", "layer-details"))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .seconds(5)
        model.enter()
        let loaded = await Wait.until { await model.loadState == .loaded }
        XCTAssertTrue(loaded)
        model.setVisibleLayers([7, 8])
        let first = await Wait.until { await Self.count(.getLayerDetails, server) == 1 }
        XCTAssertTrue(first)
        model.leave()

        model.enter()
        let second = await Wait.until { await Self.count(.getLayerDetails, server) == 2 }
        XCTAssertTrue(second, "the rows reported before are in the new tree: no wait")
        let requests = await server.receivedFrames.compactMap { frame -> GetLayerDetails? in
            guard case .getLayerDetails(let request) = frame.body else { return nil }
            return request
        }
        XCTAssertEqual(
            requests.last?.requests.prefix(2).map(\.layerID), [7, 8],
            "the rows in view come first again")

        await session.close()
        await server.stop()
    }

    /// A batch that ended as "not active" from before the app came back, while a refresh was
    /// on its way, used to make one more reload after it.
    @MainActor
    func test_C_DET_04_aStaleNotActiveDuringARefreshAddsNoReload() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += [
            .expect(.getLayerDetails, as: 50),
            .hold(gate),
            .expect(.getHierarchy, as: 2),
            .send(Frame(requestID: 50, body: .streamEnd(StreamEnd(
                status: .failed, chunkCount: 0,
                error: ServerError(code: .appNotActive, message: nil))))),
            .send(Frame(requestID: 2, body: .hierarchy(try Fixtures.hierarchy()))),
            .expect(.getLayerDetails, as: 51),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .zero
        model.enter()
        let batch = await Wait.until { await Self.count(.getLayerDetails, server) == 1 }
        XCTAssertTrue(batch)

        model.refresh()
        // The app came back after the batch went out: its "not active" is out of date.
        model.appStateDidChange(.active)
        await gate.open()
        let next = await Wait.until { await Self.count(.getLayerDetails, server) == 2 }
        XCTAssertTrue(next, "the refresh's round of screenshots")
        try await Task.sleep(for: .milliseconds(200))
        let hierarchies = await Self.count(.getHierarchy, server)
        XCTAssertEqual(hierarchies, 2, "the refresh under way is the reload it needed")
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    /// The app coming back twice in quick succession, while the reload the
    /// first time started is on its way, makes no second reload after it.
    @MainActor
    func test_C_DET_04_comingBackTwiceDuringTheReloadReloadsOnce() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures(
            "handshake", "hierarchy", "layer-details", "app-not-active").steps
        var hierarchy = try MockScript.fixtures("hierarchy").steps
        hierarchy.insert(.hold(gate), at: 1)  // the reload's answer waits
        steps += hierarchy
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .zero
        model.enter()
        let first = await Wait.until { await model.images[4] != nil }
        XCTAssertTrue(first)
        model.refresh()
        let refused = await Wait.until { await model.notice == .appNotActive }
        XCTAssertTrue(refused)

        model.appStateDidChange(.active)
        let reloading = await Wait.until { await Self.count(.getHierarchy, server) == 3 }
        XCTAssertTrue(reloading)
        model.appStateDidChange(.inactive)
        model.appStateDidChange(.active)
        await gate.open()
        let shown = await Wait.until { await model.notice == nil }
        XCTAssertTrue(shown)
        try await Task.sleep(for: .milliseconds(300))
        let hierarchies = await Self.count(.getHierarchy, server)
        XCTAssertEqual(hierarchies, 3, "the reload under way already follows the app back")

        await session.close()
        await server.stop()
    }
}
