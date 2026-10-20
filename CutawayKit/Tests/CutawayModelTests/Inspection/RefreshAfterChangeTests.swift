import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// What a change of an attribute does to the preview (C-DET-06): the window's subtree is taken
/// again, and only the layers the change can have touched are asked for again.
final class RefreshAfterChangeTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.4.0")
    private static let text = AttributeKey(layerID: 3, attributeID: "label.text")
    private static let lines = AttributeKey(layerID: 3, attributeID: "label.numberOfLines")

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

    /// An inspection that is entered, can edit, and has its first round of screenshots in
    /// (unless `screenshots` is false, which keeps them waiting for rows that never come).
    @MainActor
    private static func model(
        _ session: Session, screenshots: Bool = true
    ) async -> InspectionStore {
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = screenshots ? .zero : .seconds(30)
        model.enter()
        let ready = await Wait.until {
            await MainActor.run { model.loadState == .loaded && model.attributes.canEdit }
        }
        XCTAssertTrue(ready)
        if screenshots {
            let settled = await Wait.until {
                await model.detailProgress == DetailProgress(completed: 10, total: 10)
            }
            XCTAssertTrue(settled)
        }
        return model
    }

    private static func result(_ requestID: UInt32) throws -> [MockScript.Step] {
        let groups = try Fixtures.setAttributeResults()[0].attributeGroups
        return [
            .expect(.setAttribute, as: requestID),
            .send(Frame(requestID: requestID, body: .setAttributeResult(SetAttributeResult(
                layerID: 3, attributeGroups: groups)))),
        ]
    }

    private static func subtree(_ hierarchy: Hierarchy, as requestID: UInt32) -> [MockScript.Step] {
        [
            .expect(.getSubtree, as: requestID),
            .send(Frame(requestID: requestID, body: .hierarchy(hierarchy))),
        ]
    }

    private static func emptyEnd(_ requestID: UInt32, _ status: StreamStatus = .completed)
        -> MockScript.Step
    {
        .send(Frame(requestID: requestID, body: .streamEnd(StreamEnd(
            status: status, chunkCount: 0, error: nil))))
    }

    private static func requests(_ server: MockServer) async -> [GetLayerDetails] {
        await InspectionStoreDetailsTests.detailRequests(server)
    }

    private static func kinds(_ server: MockServer) async -> [MessageKind] {
        await server.receivedFrames.map { MessageKind($0.body) }
    }

    private static func request(_ id: UInt64, _ kind: TextureKey.Kind) -> LayerDetailRequest {
        InspectionStoreDetailsTests.request(id, kind)
    }

    // MARK: - What is asked for

    @MainActor
    func test_C_DET_06_aChangeTakesTheWindowAgainAndAsksOnlyForTheChangedLayer() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps += try Self.result(30)
        steps += Self.subtree(try Fixtures.hierarchy(), as: 31)
        steps.append(.expect(.getLayerDetails, as: 70))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session)

        model.attributes.setRegardlessOfSelection(Self.text, to: .string("Welcome back"), continuous: false)
        let asked = await Wait.until { await Self.requests(server).count == 2 }
        XCTAssertTrue(asked)
        let frames = await server.receivedFrames
        // The window's root (P-HIER-10): the change may have moved anything in it.
        XCTAssertTrue(frames.contains { $0.body == .getSubtree(GetSubtree(rootID: 1)) })
        // Layer 3 is a leaf: its group. Its ancestors are expanded and draw their solo.
        let requests = await Self.requests(server)
        XCTAssertEqual(requests.last?.requests, [Self.request(3, .group)])
        try await Task.sleep(for: .milliseconds(100))
        let all = await Self.requests(server)
        XCTAssertEqual(all.count, 2, "the selected layer's attributes are the answer's; nothing more")
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_06_layersThatMovedOrAppearedAreAskedForTooAndGoneOnesLeave() async throws {
        var hierarchy = try Fixtures.hierarchy()
        // Layer 6 moved; layer 8 is gone; layer 20 is new, where 8 was.
        let six = try XCTUnwrap(hierarchy.nodes.firstIndex { $0.id == 6 })
        hierarchy.nodes[six].position?.y += 20
        let eight = try XCTUnwrap(hierarchy.nodes.firstIndex { $0.id == 8 })
        var twenty = hierarchy.nodes[eight]
        twenty.id = 20
        hierarchy.nodes[eight] = twenty
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps += try Self.result(30)
        steps += Self.subtree(hierarchy, as: 31)
        steps.append(.expect(.getLayerDetails, as: 70))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session)

        model.attributes.setRegardlessOfSelection(Self.text, to: .string("Welcome back"), continuous: false)
        let asked = await Wait.until { await Self.requests(server).count == 2 }
        XCTAssertTrue(asked)
        let requests = await Self.requests(server)
        XCTAssertEqual(
            requests.last?.requests,
            [Self.request(3, .group), Self.request(6, .solo), Self.request(20, .group)])
        XCTAssertFalse(model.tree.contains(8))
        XCTAssertNil(model.images[8])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_06_anAncestorDrawnAsAGroupIsAskedForAgain() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps += [.expect(.getLayerDetails, as: 60), Self.emptyEnd(60)]  // layer 2 collapsed
        steps += try Self.result(30)
        steps += Self.subtree(try Fixtures.hierarchy(), as: 31)
        steps.append(.expect(.getLayerDetails, as: 70))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session)
        model.setExpanded(2, false)
        let collapsed = await Wait.until {
            await model.detailProgress == DetailProgress(completed: 2, total: 2)
        }
        XCTAssertTrue(collapsed)

        model.attributes.setRegardlessOfSelection(Self.text, to: .string("Welcome back"), continuous: false)
        let asked = await Wait.until { await Self.requests(server).count == 3 }
        XCTAssertTrue(asked)
        let requests = await Self.requests(server)
        XCTAssertEqual(requests.last?.requests, [Self.request(2, .group)])

        await session.close()
        await server.stop()
    }

    // MARK: - Order on the wire

    @MainActor
    func test_C_DET_06_screenshotsUnderWayAreCancelledBeforeAChangeGoesOut() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += [
            .expect(.getLayerDetails, as: 50),
            .hold(gate),
            .expect(.cancel, as: 51),
            Self.emptyEnd(50, .cancelled),
        ]
        steps += try Self.result(30)
        steps += Self.subtree(try Fixtures.hierarchy(), as: 31)
        steps.append(.expect(.getLayerDetails, as: 70))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session, screenshots: false)
        model.setVisibleLayers([1])
        let batch = await Wait.until { await Self.requests(server).count == 1 }
        XCTAssertTrue(batch)

        model.attributes.setRegardlessOfSelection(Self.text, to: .string("Welcome back"), continuous: false)
        await gate.open()
        let refreshed = await Wait.until { await Self.requests(server).count == 2 }
        XCTAssertTrue(refreshed, "what the cancelled batch did not bring is asked for again")
        let kinds = await Self.kinds(server)
        XCTAssertEqual(
            Array(kinds.prefix(6)),
            [.hello, .getHierarchy, .getLayerDetails, .cancel, .setAttribute, .getSubtree])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_06_aFailedChangeLetsTheScreenshotsGoOn() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += [
            .expect(.getLayerDetails, as: 50),
            .hold(gate),
            .expect(.cancel, as: 51),
            Self.emptyEnd(50, .cancelled),
            .expect(.setAttribute, as: 30),
            .send(Frame(requestID: 30, body: .error(ServerError(
                code: .invalidAttributeValue, message: nil)))),
            .expect(.getLayerDetails, as: 70),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session, screenshots: false)
        model.setVisibleLayers([1])
        let batch = await Wait.until { await Self.requests(server).count == 1 }
        XCTAssertTrue(batch)

        model.attributes.setRegardlessOfSelection(Self.text, to: .string("x"), continuous: false)
        await gate.open()
        let again = await Wait.until { await Self.requests(server).count == 2 }
        XCTAssertTrue(again)
        let subtrees = await Self.kinds(server).filter { $0 == .getSubtree }.count
        XCTAssertEqual(subtrees, 0, "no refresh after a change that failed")

        await session.close()
        await server.stop()
    }

    // MARK: - Merging

    @MainActor
    func test_C_DET_06_changesDuringARefreshMakeOneMoreAfterIt() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += try Self.result(30)
        steps += [.expect(.getSubtree, as: 31), .hold(gate)]
        // Both changes are answered before the subtree: they succeed while it is on its way.
        // They go out one after the other (each waits for the answer to the one before).
        steps += try Self.result(32) + (try Self.result(33))
        steps.append(.send(Frame(requestID: 31, body: .hierarchy(try Fixtures.hierarchy()))))
        steps += Self.subtree(try Fixtures.hierarchy(), as: 34)
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session, screenshots: false)

        model.attributes.setRegardlessOfSelection(Self.text, to: .string("Welcome back"), continuous: false)
        let first = await Wait.until {
            await Self.kinds(server).filter { $0 == .getSubtree }.count == 1
        }
        XCTAssertTrue(first)
        model.attributes.setRegardlessOfSelection(Self.text, to: .string("Again"), continuous: false)
        model.attributes.setRegardlessOfSelection(Self.lines, to: .integer(2), continuous: false)
        // Both go out now; the server reads them once the gate opens, and answers them before
        // the subtree, so that they succeed while it is on its way.
        await gate.open()
        let second = await Wait.until {
            await Self.kinds(server).filter { $0 == .getSubtree }.count == 2
        }
        XCTAssertTrue(second)
        let done = await Wait.until { await !model.isLoading }
        XCTAssertTrue(done)
        try await Task.sleep(for: .milliseconds(200))
        let subtrees = await Self.kinds(server).filter { $0 == .getSubtree }.count
        XCTAssertEqual(subtrees, 2, "two changes during the first refresh make one more")
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    // MARK: - Failures

    @MainActor
    func test_C_DET_06_aWindowThatIsGoneLoadsTheWholeTree() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += try Self.result(30)
        steps += [
            .expect(.getSubtree, as: 31),
            .send(Frame(requestID: 31, body: .error(ServerError(code: .layerNotFound, message: nil)))),
        ]
        steps += try MockScript.fixtures("hierarchy").steps
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session, screenshots: false)

        model.attributes.setRegardlessOfSelection(Self.text, to: .string("Welcome back"), continuous: false)
        let reloaded = await Wait.until {
            await Self.kinds(server).filter { $0 == .getHierarchy }.count == 2
        }
        XCTAssertTrue(reloaded)
        let done = await Wait.until { await !model.isLoading }
        XCTAssertTrue(done)
        XCTAssertNil(model.notice, "nothing to say: the whole tree came")

        await session.close()
        await server.stop()
    }

    // MARK: - Attributes

    @MainActor
    func test_C_DET_06_otherLayersAttributesAreAskedForAgain() async throws {
        var steps = try MockScript.fixtures("handshake", "layer-details", "layer-details").steps
        steps += try Self.result(30)
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let attributes = AttributesStore(session: session)
        attributes.setOpen(true)
        attributes.setEditingSupported(true)
        attributes.select(4)
        let four = await Wait.until {
            if case .loaded = await attributes.state { return true }
            return false
        }
        XCTAssertTrue(four)
        attributes.select(3)
        let three = await Wait.until {
            if case .loaded = await attributes.state { return true }
            return false
        }
        XCTAssertTrue(three)
        XCTAssertEqual(attributes.heldLayerIDs, [3, 4])

        attributes.setRegardlessOfSelection(Self.text, to: .string("Welcome back"), continuous: false)
        let done = await Wait.until { await attributes.edits.isEmpty }
        XCTAssertTrue(done)
        XCTAssertEqual(attributes.heldLayerIDs, [3], "layer 4's may have changed with it")

        await session.close()
        await server.stop()
    }

    // MARK: - Found in review

    private static func without(_ id: UInt64) throws -> Hierarchy {
        var hierarchy = try Fixtures.hierarchy()
        hierarchy.nodes.removeAll { $0.id == id }
        return hierarchy
    }

    /// A layer that left with one change and came back with the next was never asked for.
    @MainActor
    func test_C_DET_06_aLayerThatComesBackIsAskedForAgain() async throws {
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps += try Self.result(30)
        steps += Self.subtree(try Self.without(8), as: 31)
        steps += [.expect(.getLayerDetails, as: 70), Self.emptyEnd(70)]
        steps += try Self.result(32)
        steps += Self.subtree(try Fixtures.hierarchy(), as: 33)
        steps.append(.expect(.getLayerDetails, as: 71))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session)

        model.attributes.setRegardlessOfSelection(Self.text, to: .string("Welcome back"), continuous: false)
        let gone = await Wait.until {
            let asked = await Self.requests(server).count == 2
            return await MainActor.run { asked && !model.tree.contains(8) }
        }
        XCTAssertTrue(gone)
        try await Task.sleep(for: .milliseconds(200))
        model.attributes.setRegardlessOfSelection(Self.text, to: .string("Hello"), continuous: false)
        let back = await Wait.until { await Self.requests(server).count == 3 }
        XCTAssertTrue(back)
        let requests = await Self.requests(server)
        XCTAssertEqual(requests.last?.requests, [Self.request(3, .group), Self.request(8, .group)])

        await session.close()
        await server.stop()
    }

    /// A layer that moved inside a collapsed node left that node's group image as it was.
    @MainActor
    func test_C_DET_06_aCollapsedAncestorOfALayerThatMovedIsAskedForAgain() async throws {
        var moved = try Fixtures.hierarchy()
        let five = try XCTUnwrap(moved.nodes.firstIndex { $0.id == 5 })
        moved.nodes[five].position?.x += 10
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps += try Self.result(30)
        steps += Self.subtree(moved, as: 31)
        steps.append(.expect(.getLayerDetails, as: 70))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session)
        // Layer 4's group came in the first round: collapsed, it is drawn with nothing asked.
        model.setExpanded(4, false)
        XCTAssertEqual(model.detailProgress, DetailProgress(completed: 7, total: 7))

        model.attributes.setRegardlessOfSelection(Self.text, to: .string("Welcome back"), continuous: false)
        let asked = await Wait.until { await Self.requests(server).count == 2 }
        XCTAssertTrue(asked)
        let requests = await Self.requests(server)
        XCTAssertEqual(requests.last?.requests, [Self.request(3, .group), Self.request(4, .group)])

        await session.close()
        await server.stop()
    }

    /// A change that succeeds while the whole tree is on its way: that answer may be older
    /// than the change, so the window is taken again after it.
    @MainActor
    func test_C_DET_06_aChangeDuringAWholeReloadIsRefreshedAfterIt() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += [.expect(.getHierarchy, as: 2), .hold(gate)]
        steps += try Self.result(30)
        steps.append(.send(Frame(requestID: 2, body: .hierarchy(try Fixtures.hierarchy()))))
        steps += Self.subtree(try Fixtures.hierarchy(), as: 31)
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session, screenshots: false)

        model.refresh()
        let reloading = await Wait.until {
            await Self.kinds(server).filter { $0 == .getHierarchy }.count == 2
        }
        XCTAssertTrue(reloading)
        model.attributes.setRegardlessOfSelection(Self.text, to: .string("Welcome back"), continuous: false)
        await gate.open()
        let refreshed = await Wait.until {
            await Self.kinds(server).filter { $0 == .getSubtree }.count == 1
        }
        XCTAssertTrue(refreshed)
        let kinds = await Self.kinds(server)
        XCTAssertEqual(Array(kinds.suffix(3)), [.getHierarchy, .setAttribute, .getSubtree])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_DET_06_anAnswerThatIsNotTheWindowsSubtreeLoadsTheWholeTree() async throws {
        let tree = try Fixtures.hierarchy()
        var stray = tree.nodes[2]
        stray.id = 21
        stray.parentID = 99
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += try Self.result(30)
        steps += Self.subtree(Hierarchy(nodes: [tree.nodes[0], stray], keyWindowID: 1), as: 31)
        steps += try MockScript.fixtures("hierarchy").steps
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session, screenshots: false)

        model.attributes.setRegardlessOfSelection(Self.text, to: .string("Welcome back"), continuous: false)
        let reloaded = await Wait.until {
            await Self.kinds(server).filter { $0 == .getHierarchy }.count == 2
        }
        XCTAssertTrue(reloaded)
        let done = await Wait.until { await !model.isLoading }
        XCTAssertTrue(done)
        XCTAssertEqual(model.tree.count, 14)

        await session.close()
        await server.stop()
    }

    /// The selected layer is not the changed one: its attributes stay shown while they are
    /// asked for again, rather than the panel saying it is loading.
    @MainActor
    func test_C_DET_06_theSelectedLayersAttributesStayShownWhileAskedForAgain() async throws {
        var steps = try MockScript.fixtures("handshake", "layer-details").steps
        steps += try Self.result(30)
        steps.append(.expect(.getLayerDetails, as: 40))
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let attributes = AttributesStore(session: session)
        attributes.setOpen(true)
        attributes.setEditingSupported(true)
        attributes.select(4)
        let loaded = await Wait.until {
            if case .loaded = await attributes.state { return true }
            return false
        }
        XCTAssertTrue(loaded)
        let before = attributes.state
        var states: [AttributesStore.State] = []
        let watch = attributes.$state.sink { states.append($0) }

        attributes.setRegardlessOfSelection(Self.text, to: .string("Welcome back"), continuous: false)
        let asked = await Wait.until { await Self.requests(server).count == 2 }
        XCTAssertTrue(asked, "layer 4's attributes are asked for again")
        watch.cancel()
        XCTAssertFalse(states.contains(.loading), "\(states)")
        XCTAssertEqual(attributes.state, before)

        await session.close()
        await server.stop()
    }

    // MARK: - Stale answers, subtrees and hidden layers

    /// The window's subtree came back "not active" from before the app was back: the change
    /// is refreshed again, not lost.
    @MainActor
    func test_C_DET_06_aStaleNotActiveRefreshesTheChangeAgain() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += try Self.result(30)
        steps += [
            .expect(.getSubtree, as: 31),
            .hold(gate),
            .send(Frame(requestID: 31, body: .error(ServerError(code: .appNotActive, message: nil)))),
        ]
        steps += Self.subtree(try Fixtures.hierarchy(), as: 32)
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session, screenshots: false)

        model.attributes.setRegardlessOfSelection(Self.text, to: .string("Welcome back"), continuous: false)
        let first = await Wait.until {
            await Self.kinds(server).filter { $0 == .getSubtree }.count == 1
        }
        XCTAssertTrue(first)
        model.appStateDidChange(.active)
        await gate.open()
        let again = await Wait.until {
            await Self.kinds(server).filter { $0 == .getSubtree }.count == 2
        }
        XCTAssertTrue(again)
        XCTAssertNil(model.notice)
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    /// The user asks for the window's subtree while the refresh after a change takes that same
    /// root: it is asked for again after it, not taken as the same request.
    @MainActor
    func test_C_DET_07_aSubtreeAskedForDuringARefreshAfterAChangeIsItsOwn() async throws {
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake", "hierarchy").steps
        steps += try Self.result(30)
        var held = Self.subtree(try Fixtures.hierarchy(), as: 31)
        held.insert(.hold(gate), at: 1)
        steps += held + Self.subtree(try Fixtures.hierarchy(), as: 32)
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session, screenshots: false)

        model.attributes.setRegardlessOfSelection(Self.text, to: .string("Welcome back"), continuous: false)
        let first = await Wait.until {
            await Self.kinds(server).filter { $0 == .getSubtree }.count == 1
        }
        XCTAssertTrue(first)
        model.refreshSubtree(of: 1)
        XCTAssertEqual(model.queuedSubtrees, [1])
        await gate.open()
        let second = await Wait.until {
            await Self.kinds(server).filter { $0 == .getSubtree }.count == 2
        }
        XCTAssertTrue(second)

        await session.close()
        await server.stop()
    }

    /// A change that hides its layer: the layer is not drawn, so nothing is asked for it
    /// (C-SCENE-03).
    @MainActor
    func test_C_DET_06_aLayerHiddenByAChangeIsNotAskedFor() async throws {
        var hidden = try Fixtures.hierarchy()
        let three = try XCTUnwrap(hidden.nodes.firstIndex { $0.id == 3 })
        hidden.nodes[three].isHidden = true
        var steps = try MockScript.fixtures("handshake", "hierarchy", "layer-details").steps
        steps += try Self.result(30)
        steps += Self.subtree(hidden, as: 31)
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session)

        model.attributes.setRegardlessOfSelection(Self.text, to: .string("Welcome back"), continuous: false)
        let refreshed = await Wait.until { await model.tree.node(3)?.isHidden == true }
        XCTAssertTrue(refreshed)
        try await Task.sleep(for: .milliseconds(200))
        let requests = await Self.requests(server)
        XCTAssertEqual(requests.count, 1, "only the first round: layer 3 is not drawn now")
        XCTAssertNil(model.layout.texture(of: 3))
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }
}
