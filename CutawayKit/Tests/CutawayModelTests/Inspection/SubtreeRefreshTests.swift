import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// Refreshing one subtree (C-DET-07): `GetSubtree`, the subtree put in place (C-HIER-08),
/// and only its screenshots and its ancestors' group images asked for again.
final class SubtreeRefreshTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.4.0")

    private static func session(
        to server: MockServer, protocolVersion: Version = ProtocolVersion.current,
        requestTimeout: Duration = .seconds(10)
    ) async throws -> Session {
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(
            channel: channel, client: Self.client, protocolVersion: protocolVersion,
            requestTimeout: requestTimeout)
        _ = try await session.handshake()
        return session
    }

    /// An inspection that is entered and can refresh subtrees.
    @MainActor
    private static func model(
        _ session: Session, rowsWait: Duration = .zero
    ) async -> InspectionStore {
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = rowsWait
        model.enter()
        let loaded = await Wait.until {
            await MainActor.run { model.loadState == .loaded && model.canRefreshSubtrees }
        }
        XCTAssertTrue(loaded)
        return model
    }

    private static func kinds(_ server: MockServer) async -> [MessageKind] {
        await server.receivedFrames.map { MessageKind($0.body) }
    }

    private static func count(_ kind: MessageKind, _ server: MockServer) async -> Int {
        await kinds(server).filter { $0 == kind }.count
    }

    /// The answer to `GetSubtree(4)` in the `subtree` scenario.
    private static func subtreeSteps() throws -> [MockScript.Step] {
        Array(try MockScript.fixtures("subtree").steps.prefix(2))
    }

    /// An empty answer to the attributes a selection asks for: enough where they do not
    /// matter.
    private static func attributesSteps(_ requestID: UInt32) -> [MockScript.Step] {
        [
            .expect(.getLayerDetails, as: requestID),
            .send(Frame(requestID: requestID, body: .streamEnd(StreamEnd(
                status: .completed, chunkCount: 0, error: nil)))),
        ]
    }

    private static func answer(_ requestID: UInt32, _ body: Body) -> [MockScript.Step] {
        [.expect(.getSubtree, as: requestID), .send(Frame(requestID: requestID, body: body))]
    }

    // MARK: - What is asked for

    @MainActor
    func test_C_DET_07_aSubtreeIsAskedForAndOnlyItsScreenshotsAgain() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps += try Self.subtreeSteps()
        steps.append(.expect(.getLayerDetails, as: 70))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session)
        let settled = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 7, total: 7)
        }
        XCTAssertTrue(settled)

        model.refreshSubtree(of: 4)
        let asked = await Wait.until {
            await InspectionStoreDetailsTests.detailRequests(server).count == 2
        }
        XCTAssertTrue(asked)
        let frames = await server.receivedFrames
        XCTAssertTrue(frames.contains { $0.body == .getSubtree(GetSubtree(rootID: 4)) })
        // Layer 4 is expanded and draws its solo; its virtual nodes 10 to 12 have no images
        // (C-DET-11); 5 is hidden and needs nothing; the ancestors 1 and 2 are expanded, so
        // their group images are not drawn.
        let requests = await InspectionStoreDetailsTests.detailRequests(server)
        XCTAssertEqual(
            requests.last?.requests,
            [InspectionStoreDetailsTests.request(4, .solo)])
        XCTAssertEqual(model.detailProgress, DetailProgress(completed: 6, total: 7))
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_07_anAncestorsGroupIsDueAgain() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps += Self.attributesSteps(61)  // layer 2's group, asked for when it collapses
        steps += try Self.subtreeSteps()
        steps.append(.expect(.getLayerDetails, as: 70))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session)
        let settled = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 7, total: 7)
        }
        XCTAssertTrue(settled)
        model.setExpanded(2, false)
        let collapsed = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 2, total: 2)
        }
        XCTAssertTrue(collapsed, "layer 2's group was asked for and settled")

        // Layer 4 is inside the collapsed layer 2, which draws its group: that is due again.
        model.refreshSubtree(of: 4)
        let asked = await Wait.until {
            await InspectionStoreDetailsTests.detailRequests(server).count == 3
        }
        XCTAssertTrue(asked)
        let requests = await InspectionStoreDetailsTests.detailRequests(server)
        XCTAssertEqual(requests.last?.requests, [InspectionStoreDetailsTests.request(2, .group)])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_07_theSubtreesDescendantsAreDueAgain() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps += try Self.subtreeSteps()
        steps.append(.expect(.getLayerDetails, as: 70))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .zero
        // Layer 5, hidden, is drawn too.
        model.setShowsHiddenLayers(true)
        model.enter()
        let settled = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 8, total: 8)
        }
        XCTAssertTrue(settled)
        let ready = await Wait.until { await model.canRefreshSubtrees }
        XCTAssertTrue(ready)

        model.refreshSubtree(of: 4)
        let asked = await Wait.until {
            await InspectionStoreDetailsTests.detailRequests(server).count == 2
        }
        XCTAssertTrue(asked)
        let requests = await InspectionStoreDetailsTests.detailRequests(server)
        XCTAssertEqual(
            requests.last?.requests,
            [InspectionStoreDetailsTests.request(4, .solo),
             InspectionStoreDetailsTests.request(5, .group)])

        await session.close()
        await server.stop()
    }

    /// Found in review: a batch that ended while the subtree was on its way asked for nothing
    /// after it, and a subtree that then failed left the round where it was.
    @MainActor
    func test_C_DET_07_screenshotsGoOnAfterASubtreeThatFailed() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += [
            .expect(.getLayerDetails, as: 50),
            .hold(gate),
            // Ended by the server without being asked: due again (C-DET-01).
            .send(Frame(requestID: 50, body: .streamEnd(StreamEnd(
                status: .cancelled, chunkCount: 0, error: nil)))),
        ]
        steps += Self.answer(1, .error(ServerError(code: .layerNotFound, message: "gone")))
        steps.append(.expect(.getLayerDetails, as: 51))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session)
        let first = await Wait.until {
            await InspectionStoreDetailsTests.detailRequests(server).count == 1
        }
        XCTAssertTrue(first)

        model.refreshSubtree(of: 4)
        await gate.open()
        let said = await Wait.until { await model.notice == .layerGone }
        XCTAssertTrue(said)
        let again = await Wait.until {
            await InspectionStoreDetailsTests.detailRequests(server).count == 2
        }
        XCTAssertTrue(again, "the round goes on")

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_07_aSubtreeIsNotPutIntoATreeTheWholeLoadRefused() async throws {
        let gate = MockGate()
        let tree = try LayerTree(try Fixtures.hierarchy())
        let one = try XCTUnwrap(tree.node(1))
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += [
            .expect(.getHierarchy, as: 2),
            .hold(gate),
            // Not a tree: layer 1 twice.
            .send(Frame(requestID: 2, body: .hierarchy(Hierarchy(nodes: [one, one], keyWindowID: 1)))),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session, rowsWait: .seconds(30))

        model.refresh()
        let reloading = await Wait.until { await Self.count(.getHierarchy, server) == 2 }
        XCTAssertTrue(reloading)
        model.refreshSubtree(of: 4)
        XCTAssertEqual(model.queuedSubtrees, [4])
        await gate.open()
        let refused = await Wait.until {
            await model.loadState == .failed(.invalidHierarchy("the ID 1 appears more than once"))
        }
        XCTAssertTrue(refused)
        XCTAssertEqual(model.queuedSubtrees, [])
        try await Task.sleep(for: .milliseconds(200))
        let subtrees = await Self.count(.getSubtree, server)
        XCTAssertEqual(subtrees, 0)
        model.refreshSubtree(of: 4)
        XCTAssertFalse(model.isLoading, "only a whole load can bring the tree back")

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_07_theStateInsideAndOutsideTheSubtreeIsKept() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps += Self.attributesSteps(60)
        var subtree = try Self.subtreeSteps()
        subtree.insert(.hold(gate), at: 1)
        steps += subtree
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session)
        let shown = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 7, total: 7)
        }
        XCTAssertTrue(shown)
        XCTAssertNotNil(model.images[3])
        // A leaf outside the subtree, collapsed: it draws its group either way, so nothing
        // more is asked for.
        model.setExpanded(8, false)
        model.select(4)
        let selected = await Wait.until { await model.attributes.state == .failed }
        XCTAssertTrue(selected)
        let tree = model.tree

        model.refreshSubtree(of: 4)
        let asked = await Wait.until { await Self.count(.getSubtree, server) == 1 }
        XCTAssertTrue(asked)
        XCTAssertTrue(model.isLoading)
        await gate.open()
        let done = await Wait.until { await !model.isLoading }
        XCTAssertTrue(done)

        // The fixture's answer is the subtree as it was.
        XCTAssertEqual(model.tree, tree)
        XCTAssertEqual(model.selectedLayerID, 4)
        XCTAssertFalse(model.isExpanded(8))
        XCTAssertTrue(model.isExpanded(4))
        // Images stay until new ones arrive, inside the subtree and out.
        XCTAssertNotNil(model.images[3])
        XCTAssertNotNil(model.images[4])
        XCTAssertNil(model.notice)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_07_layersThatAreGoneTakeTheSelectionAndFocusWithThem() async throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        let four = try XCTUnwrap(tree.node(4))
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += Self.attributesSteps(60)
        // Layer 4 without layer 5.
        steps += Self.answer(1, .hierarchy(Hierarchy(nodes: [four], keyWindowID: 1)))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session, rowsWait: .seconds(30))
        model.setShowsHiddenLayers(true)
        model.select(5)
        model.focus(on: 5)
        XCTAssertEqual(model.focusedLayerID, 5)
        let selected = await Wait.until { await model.attributes.state == .failed }
        XCTAssertTrue(selected)

        model.refreshSubtree(of: 4)
        let gone = await Wait.until { await !model.tree.contains(5) }
        XCTAssertTrue(gone)
        XCTAssertNil(model.selectedLayerID)
        XCTAssertNil(model.focusedLayerID)
        XCTAssertNil(model.images[5])
        XCTAssertEqual(model.tree.children(of: 4), [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_07_theSelectedLayersAttributesAreAskedForAgain() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += Self.attributesSteps(60)
        steps += try Self.subtreeSteps()
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session, rowsWait: .seconds(30))
        model.select(4)
        let first = await Wait.until { await model.attributes.state == .failed }
        XCTAssertTrue(first)

        model.refreshSubtree(of: 4)
        let again = await Wait.until {
            await InspectionStoreDetailsTests.detailRequests(server)
                .filter { $0.requests.contains { $0.wantAttributes } }.count == 2
        }
        XCTAssertTrue(again, "the selected layer's attributes were asked for again")

        await session.close()
        await server.stop()
    }

    // MARK: - Queueing

    @MainActor
    func test_C_DET_07_aSubtreeWaitsForTheLoadUnderWayAndIsAskedForOnce() async throws {
        let gate = MockGate()
        let subtreeGate = MockGate()
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        var held = try MockScript.fixtures("hierarchy").steps
        held.insert(.hold(gate), at: 1)
        var subtree = try Self.subtreeSteps()
        subtree.insert(.hold(subtreeGate), at: 1)
        steps += held + subtree
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        // No screenshots: a new tree's first batch waits for rows that never come.
        let model = await Self.model(session, rowsWait: .seconds(30))

        model.refresh()
        let reloading = await Wait.until { await Self.count(.getHierarchy, server) == 2 }
        XCTAssertTrue(reloading)
        model.refreshSubtree(of: 4)
        model.refreshSubtree(of: 4)
        XCTAssertEqual(model.queuedSubtrees, [4])
        let early = await Self.count(.getSubtree, server)
        XCTAssertEqual(early, 0, "not before the hierarchy under way is answered")

        await gate.open()
        let asked = await Wait.until { await Self.count(.getSubtree, server) == 1 }
        XCTAssertTrue(asked)
        // While it is on its way, asking again for the same subtree adds nothing.
        model.refreshSubtree(of: 4)
        XCTAssertEqual(model.queuedSubtrees, [])
        await subtreeGate.open()
        let done = await Wait.until { await !model.isLoading }
        XCTAssertTrue(done)
        try await Task.sleep(for: .milliseconds(200))
        let kinds = await Self.kinds(server)
        XCTAssertEqual(kinds, [.hello, .getHierarchy, .getHierarchy, .getSubtree])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_07_aWholeReloadTakesThePlaceOfWaitingSubtrees() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        var subtree = try Self.subtreeSteps()
        subtree.insert(.hold(gate), at: 1)
        steps += subtree + (try MockScript.fixtures("hierarchy").steps)
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session, rowsWait: .seconds(30))

        model.refreshSubtree(of: 4)
        let asked = await Wait.until { await Self.count(.getSubtree, server) == 1 }
        XCTAssertTrue(asked)
        model.refreshSubtree(of: 6)
        XCTAssertEqual(model.queuedSubtrees, [6])
        model.refresh()
        XCTAssertEqual(model.queuedSubtrees, [])
        // A subtree asked for while a whole reload waits is in it already.
        model.refreshSubtree(of: 6)
        XCTAssertEqual(model.queuedSubtrees, [])

        await gate.open()
        let reloaded = await Wait.until { await Self.count(.getHierarchy, server) == 2 }
        XCTAssertTrue(reloaded)
        let done = await Wait.until { await !model.isLoading }
        XCTAssertTrue(done)
        try await Task.sleep(for: .milliseconds(200))
        let kinds = await Self.kinds(server)
        XCTAssertEqual(kinds, [.hello, .getHierarchy, .getSubtree, .getHierarchy])

        await session.close()
        await server.stop()
    }

    // MARK: - Failures

    @MainActor
    func test_C_DET_07_aLayerThatIsGoneKeepsTheTreeAndSaysSo() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += Self.answer(1, .error(ServerError(code: .layerNotFound, message: "gone")))
        steps += try Self.subtreeSteps()
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session, rowsWait: .seconds(30))
        let tree = model.tree

        model.refreshSubtree(of: 4)
        let said = await Wait.until { await model.notice == .layerGone }
        XCTAssertTrue(said)
        XCTAssertEqual(model.tree, tree)
        XCTAssertFalse(model.isLoading)

        // The next load that succeeds clears it.
        model.refreshSubtree(of: 4)
        let cleared = await Wait.until {
            await MainActor.run { model.notice == nil && !model.isLoading }
        }
        XCTAssertTrue(cleared)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_07_aSubtreeThatMovedLoadsTheWholeTree() async throws {
        let tree = try LayerTree(try Fixtures.hierarchy())
        var four = try XCTUnwrap(tree.node(4))
        four.parentID = 6
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += Self.answer(1, .hierarchy(Hierarchy(nodes: [four], keyWindowID: 1)))
        steps += try MockScript.fixtures("hierarchy").steps
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session, rowsWait: .seconds(30))

        model.refreshSubtree(of: 4)
        let reloaded = await Wait.until { await Self.count(.getHierarchy, server) == 2 }
        XCTAssertTrue(reloaded, "the whole tree was asked for")
        let done = await Wait.until { await !model.isLoading }
        XCTAssertTrue(done)
        XCTAssertNil(model.notice)
        XCTAssertEqual(model.tree.parent(of: 4), 2)

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_07_anAppThatIsNotActiveStopsLoadingAsForTheWholeTree() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += Self.answer(1, .error(ServerError(code: .appNotActive, message: nil)))
        steps += try MockScript.fixtures("hierarchy").steps
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session, rowsWait: .seconds(30))

        model.refreshSubtree(of: 4)
        let said = await Wait.until { await model.notice == .appNotActive }
        XCTAssertTrue(said)
        // Screenshots stop: rows in view would ask for a batch otherwise.
        model.setVisibleLayers([1])
        try await Task.sleep(for: .milliseconds(100))
        let batches = await Self.count(.getLayerDetails, server)
        XCTAssertEqual(batches, 0)

        // The app coming back loads the whole tree again (C-DET-04).
        model.appStateDidChange(.active)
        let reloaded = await Wait.until { await Self.count(.getHierarchy, server) == 2 }
        XCTAssertTrue(reloaded)
        let cleared = await Wait.until { await model.notice == nil }
        XCTAssertTrue(cleared)

        await session.close()
        await server.stop()
    }

    /// The app coming back while a subtree is on its way still loads
    /// the whole tree once the subtree is in; the subtree renews only itself.
    @MainActor
    func test_C_DET_04_comingBackDuringASubtreeLoadsTheWholeTreeAfterIt() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += Self.answer(1, .error(ServerError(code: .appNotActive, message: nil)))
        var subtree = try Self.subtreeSteps()
        subtree.insert(.hold(gate), at: 1)  // the second subtree's answer waits
        steps += subtree
        steps += try MockScript.fixtures("hierarchy").steps
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session, rowsWait: .seconds(30))
        model.refreshSubtree(of: 4)
        let said = await Wait.until { await model.notice == .appNotActive }
        XCTAssertTrue(said)

        model.refreshSubtree(of: 4)
        let asked = await Wait.until { await Self.count(.getSubtree, server) == 2 }
        XCTAssertTrue(asked)
        model.appStateDidChange(.active)
        await gate.open()

        let reloaded = await Wait.until { await Self.count(.getHierarchy, server) == 2 }
        XCTAssertTrue(reloaded, "the rest of the tree is loaded again too")

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_07_aSubtreeThatDoesNotComeSaysTheLayersFailed() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps.append(.expect(.getSubtree, as: 1))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server, requestTimeout: .milliseconds(300))
        let model = await Self.model(session, rowsWait: .seconds(30))
        let tree = model.tree

        model.refreshSubtree(of: 4)
        let said = await Wait.until { await model.notice == .layersFailed }
        XCTAssertTrue(said)
        XCTAssertEqual(model.tree, tree)

        await session.close()
        await server.stop()
    }
}
