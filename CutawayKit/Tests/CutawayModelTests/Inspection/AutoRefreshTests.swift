import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-LIVE-01 to C-LIVE-04: the inspection turns hierarchy change notifications on and off with
/// its switch, and refreshes what an event names, merged and held back as it has to be. In the
/// `hierarchy` fixture, 3, 4, 6, 8, 9 and 13 are siblings under 2; 5 lies under 4.
final class AutoRefreshTests: XCTestCase {
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

    /// An inspection of the responder's app, its first round of screenshots done.
    @MainActor
    private func inspect(
        _ responder: MockResponder, version: Version = ProtocolVersion.current,
        start: InspectionStart = InspectionStart()
    ) async throws -> (InspectionStore, MockServer, Session) {
        let server = try await Self.server(responder)
        let session = try await Self.session(to: server, version: version)
        let model = InspectionStore(session: session, newLayers: .expanded, start: start)
        // What AppListStore does with the events Discovery forwards.
        Task { @MainActor [weak model] in
            for await event in session.events {
                if case .hierarchyChanged(let change) = event { model?.hierarchyDidChange(change) }
            }
        }
        model.rowsWait = .zero
        model.environmentSettleDelay = .zero
        model.enter()
        let done = await settled(model)
        XCTAssertTrue(done)
        return (model, server, session)
    }

    @MainActor
    private func settled(_ model: InspectionStore) async -> Bool {
        await Wait.until {
            await MainActor.run {
                model.loadState == .loaded && !model.loader.isLoading
                    && model.detailProgress.total > 0
                    && model.detailProgress.completed == model.detailProgress.total
            }
        }
    }

    private static func watching(_ server: MockServer) async -> Bool {
        await Wait.until { await server.isWatching }
    }

    private static func kinds(_ server: MockServer) async -> [Body] {
        await server.receivedFrames.compactMap(\.body)
    }

    /// The tree requests the server received, in order: nil for `GetHierarchy`, the root for
    /// `GetSubtree`.
    private static func treeRequests(_ server: MockServer) async -> [UInt64?] {
        await server.receivedFrames.compactMap { frame in
            switch frame.body {
            case .getHierarchy: return .some(nil)
            case .getSubtree(let request): return .some(request.rootID)
            default: return nil
            }
        }
    }

    private static func watchRequests(_ server: MockServer) async -> [Bool] {
        await server.receivedFrames.compactMap { frame in
            guard case .watchHierarchy(let request) = frame.body else { return nil }
            return request.enabled
        }
    }

    /// Sends an event, and waits for the tree requests it brings to come and be answered.
    @MainActor
    private func event(
        _ change: HierarchyChanged, to model: InspectionStore, from server: MockServer,
        bringing count: Int
    ) async -> [UInt64?] {
        let before = await Self.treeRequests(server).count
        try? await server.sendEvent(change)
        let came = await Wait.until { await Self.treeRequests(server).count >= before + count }
        let brought = await Self.treeRequests(server).dropFirst(before)
        XCTAssertTrue(came, "\(brought)")
        let done = await settled(model)
        XCTAssertTrue(done)
        // Nothing more follows.
        try? await Task.sleep(for: .milliseconds(100))
        return Array(await Self.treeRequests(server).dropFirst(before))
    }

    /// How many `GetLayerDetails` asked for attributes.
    private static func attributeRequests(_ server: MockServer) async -> Int {
        await server.receivedFrames.filter {
            guard case .getLayerDetails(let request) = $0.body else { return false }
            return request.requests.contains(where: \.wantAttributes)
        }.count
    }

    private static func roots(_ roots: UInt64...) -> HierarchyChanged {
        HierarchyChanged(roots: roots, whole: false)
    }

    // MARK: - C-LIVE-01

    @MainActor
    func test_C_LIVE_01_notificationsGoOnAfterTheFirstTreeAndFollowTheSwitch() async throws {
        let (model, server, session) = try await inspect(try MockResponder.demo())
        XCTAssertTrue(model.canAutoRefresh)
        XCTAssertTrue(model.autoRefresh, "on by default (C-PREF-02)")
        let on = await Self.watching(server)
        XCTAssertTrue(on)
        let kinds = await Self.kinds(server)
        let tree = try XCTUnwrap(kinds.firstIndex { $0 == .getHierarchy })
        let watch = try XCTUnwrap(kinds.firstIndex { if case .watchHierarchy = $0 { true } else { false } })
        XCTAssertLessThan(tree, watch, "after the first tree")

        model.setAutoRefresh(false)
        let off = await Wait.until { await !server.isWatching }
        XCTAssertTrue(off)
        model.setAutoRefresh(true)
        let again = await Self.watching(server)
        XCTAssertTrue(again)
        let requests = await Self.watchRequests(server)
        XCTAssertEqual(requests, [true, false, true])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LIVE_01_aSwitchThatStartsOffAsksNothing() async throws {
        var start = InspectionStart()
        start.autoRefresh = false
        let (model, server, session) = try await inspect(try MockResponder.demo(), start: start)
        XCTAssertFalse(model.autoRefresh)
        try await Task.sleep(for: .milliseconds(100))
        let requests = await Self.watchRequests(server)
        XCTAssertEqual(requests, [])
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LIVE_01_aOneTwoSessionAndAnArchiveCannotRefreshAutomatically() async throws {
        let (model, server, session) = try await inspect(
            try MockResponder.demo(), version: Version(major: 1, minor: 2))
        XCTAssertFalse(model.canAutoRefresh)
        model.setAutoRefresh(false)
        model.setAutoRefresh(true)
        try await Task.sleep(for: .milliseconds(100))
        let requests = await Self.watchRequests(server)
        XCTAssertEqual(requests, [])
        await session.close()
        await server.stop()

        let archive = ArchiveSource(decoder: try ArchiveDecoder(try Fixtures.archive(chunkSize: 2)))
        let offline = InspectionStore(source: archive, newLayers: .expanded)
        offline.rowsWait = .zero
        offline.enter()
        let loaded = await Wait.until { await MainActor.run { offline.loadState == .loaded } }
        XCTAssertTrue(loaded)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(offline.canAutoRefresh)
    }

    @MainActor
    func test_C_LIVE_01_aFailedRequestLeavesTheSwitchOnAndSaysNothing() async throws {
        var responder = try MockResponder.demo()
        responder.watchFailure = .internalError
        let (model, server, session) = try await inspect(responder)
        let asked = await Wait.until { await Self.watchRequests(server) == [true] }
        XCTAssertTrue(asked)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(model.autoRefresh)
        XCTAssertNil(model.notice)
        // ⌘R still works.
        let before = await Self.treeRequests(server).count
        model.refresh()
        let refreshed = await Wait.until { await Self.treeRequests(server).count > before }
        XCTAssertTrue(refreshed)
        await session.close()
        await server.stop()
    }

    // MARK: - C-LIVE-02

    @MainActor
    func test_C_LIVE_02_eachRootIsAskedForOnceAndOnlyTheOutermost() async throws {
        let (model, server, session) = try await inspect(try MockResponder.demo())
        _ = await Self.watching(server)
        let two = await event(Self.roots(3, 6), to: model, from: server, bringing: 2)
        XCTAssertEqual(Set(two), [3, 6])
        XCTAssertEqual(two.count, 2)
        // 5 lies under 4: only 4. (The protocol never sends both; the client takes care anyway.)
        let nested = await event(Self.roots(5, 4), to: model, from: server, bringing: 1)
        XCTAssertEqual(nested, [4])
        XCTAssertNil(model.notice)
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LIVE_02_wholeOrAnUnknownRootTakesTheWholeTree() async throws {
        let (model, server, session) = try await inspect(try MockResponder.demo())
        _ = await Self.watching(server)
        let whole = await event(
            HierarchyChanged(roots: [], whole: true), to: model, from: server, bringing: 1)
        XCTAssertEqual(whole, [nil])
        let unknown = await event(Self.roots(3, 77), to: model, from: server, bringing: 1)
        XCTAssertEqual(unknown, [nil])
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LIVE_02_aRootThatIsGoneIsTakenFromItsParentAndThenTheWholeTree() async throws {
        let (model, server, session) = try await inspect(try MockResponder.demo())
        _ = await Self.watching(server)
        // 50 and 51 below it are in the model's tree only: the app has neither any more.
        var hierarchy = try Fixtures.hierarchy()
        var fifty = try XCTUnwrap(hierarchy.nodes.first { $0.id == 5 })
        fifty.id = 50
        fifty.parentID = 4
        var fiftyOne = fifty
        fiftyOne.id = 51
        fiftyOne.parentID = 50
        hierarchy.nodes += [fifty, fiftyOne]
        model.apply(hierarchy)
        XCTAssertTrue(model.tree.contains(51))

        let parent = await event(Self.roots(50), to: model, from: server, bringing: 2)
        XCTAssertEqual(parent, [50, 4], "its parent, without a notice")
        XCTAssertNil(model.notice)
        XCTAssertFalse(model.tree.contains(50))

        model.apply(hierarchy)
        let whole = await event(Self.roots(51), to: model, from: server, bringing: 3)
        XCTAssertEqual(whole, [51, 50, nil])
        XCTAssertNil(model.notice)
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LIVE_02_aRefreshKeepsTheStateAndTheAttributesOfAnUntouchedSelection() async throws {
        let (model, server, session) = try await inspect(try MockResponder.demo())
        _ = await Self.watching(server)
        model.select(3)
        model.setExpanded(4, false)
        let loaded = await Wait.until {
            await MainActor.run { if case .loaded = model.attributes.state { true } else { false } }
        }
        XCTAssertTrue(loaded)
        let before = await Self.attributeRequests(server)

        _ = await event(Self.roots(6), to: model, from: server, bringing: 1)
        XCTAssertEqual(model.selectedLayerID, 3)
        XCTAssertFalse(model.isExpanded(4))
        let untouched = await Self.attributeRequests(server)
        XCTAssertEqual(untouched, before, "3 is not in 6's subtree")

        _ = await event(Self.roots(3), to: model, from: server, bringing: 1)
        let renewed = await Wait.until { await Self.attributeRequests(server) > before }
        XCTAssertTrue(renewed, "3's subtree: its attributes again")
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LIVE_02_eventsAfterTheSwitchWentOffAreDropped() async throws {
        let (model, server, session) = try await inspect(try MockResponder.demo())
        _ = await Self.watching(server)
        model.setAutoRefresh(false)
        let off = await Wait.until { await !server.isWatching }
        XCTAssertTrue(off)
        try await Task.sleep(for: .milliseconds(50))
        let before = await Self.treeRequests(server).count
        try await server.sendEvent(Self.roots(3))
        try await Task.sleep(for: .milliseconds(150))
        let after = await Self.treeRequests(server).count
        XCTAssertEqual(after, before)
        await session.close()
        await server.stop()
    }

    // MARK: - C-LIVE-03

    @MainActor
    func test_C_LIVE_03_eventsWhileARefreshIsOnItsWayMakeOneRefreshAfterIt() async throws {
        let gate = MockGate()
        var responder = try MockResponder.demo()
        // The first tree request after the first tree: the event's subtree.
        responder.holdBeforeTreeRequest = (2, gate)
        let (model, server, session) = try await inspect(responder)
        _ = await Self.watching(server)
        try await server.sendEvent(Self.roots(3))
        let held = await Wait.until { await Self.treeRequests(server).count == 2 }
        XCTAssertTrue(held)
        for change in [Self.roots(4), Self.roots(8), Self.roots(4, 6)] {
            try await server.sendEvent(change)
        }
        try await Task.sleep(for: .milliseconds(100))
        let waiting = await Self.treeRequests(server).count
        XCTAssertEqual(waiting, 2, "nothing more while one is on its way")
        await gate.open()
        let came = await Wait.until { await Self.treeRequests(server).count == 5 }
        XCTAssertTrue(came)
        let done = await settled(model)
        XCTAssertTrue(done)
        try await Task.sleep(for: .milliseconds(100))
        let after = await Self.treeRequests(server).dropFirst(2)
        XCTAssertEqual(Set(after), [4, 8, 6])
        XCTAssertEqual(after.count, 3)
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LIVE_03_eventsDuringATransitionMakeOneRefreshAfterIt() async throws {
        let (model, server, session) = try await inspect(try MockResponder.demo())
        _ = await Self.watching(server)
        let before = await Self.treeRequests(server).count
        model.setInTransition(true)
        try await server.sendEvent(Self.roots(3))
        try await server.sendEvent(Self.roots(6))
        try await Task.sleep(for: .milliseconds(150))
        let count = await Self.treeRequests(server).count
        XCTAssertEqual(count, before, "held")
        model.setInTransition(false)
        let came = await Wait.until { await Self.treeRequests(server).count == before + 2 }
        XCTAssertTrue(came)
        let after = await Self.treeRequests(server).dropFirst(before)
        XCTAssertEqual(Set(after), [3, 6])
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LIVE_03_anEventWhileAnArchiveIsSavedComesAfterIt() async throws {
        let gate = MockGate()
        var responder = try MockResponder.demo()
        responder.holdBeforeDetails = (MockResponder.isArchiveBatch, gate)
        let (model, server, session) = try await inspect(responder)
        _ = await Self.watching(server)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoRefreshTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Demo.cutaway")
        model.saveArchive(to: destination, cutawayVersion: "1.3.0")
        let capturing = await Wait.until {
            await server.receivedFrames.contains {
                if case .getLayerDetails(let request) = $0.body { MockResponder.isArchiveBatch(request) } else { false }
            }
        }
        XCTAssertTrue(capturing)
        let before = await Self.treeRequests(server).count
        try await server.sendEvent(Self.roots(3))
        try await Task.sleep(for: .milliseconds(150))
        let during = await Self.treeRequests(server).count
        XCTAssertEqual(during, before)
        await gate.open()
        let saved = await Wait.until { await MainActor.run { model.archiveSave == .saved(destination) } }
        XCTAssertTrue(saved)
        let came = await Wait.until { await Self.treeRequests(server).count == before + 1 }
        XCTAssertTrue(came)
        let after = await Self.treeRequests(server).last
        XCTAssertEqual(after, 3)
        await session.close()
        await server.stop()
    }

    // MARK: - C-LIVE-04

    @MainActor
    func test_C_LIVE_04_anEventDuringTheRefreshAfterAChangeTakesItsSubtreeOnceMore() async throws {
        let gate = MockGate()
        var responder = try MockResponder.demo()
        responder.editing = .apply
        // The refresh after the change: the window's subtree.
        responder.holdBeforeTreeRequest = (2, gate)
        let (model, server, session) = try await inspect(responder)
        _ = await Self.watching(server)
        model.select(3)
        let editable = await Wait.until { await MainActor.run { model.attributes.canEdit } }
        XCTAssertTrue(editable)
        model.attributes.setRegardlessOfSelection(
            AttributeKey(layerID: 3, attributeID: "label.text"), to: .string("Welcome back"),
            continuous: false)
        let held = await Wait.until { await Self.treeRequests(server).count == 2 }
        XCTAssertTrue(held)
        let window = await Self.treeRequests(server).last
        XCTAssertEqual(window, 1)
        // Sent before the event: its answer may be older than the check (P-WATCH-04).
        try await server.sendEvent(Self.roots(3))
        try await server.sendEvent(Self.roots(3))
        try await Task.sleep(for: .milliseconds(50))
        await gate.open()
        let came = await Wait.until { await Self.treeRequests(server).count == 3 }
        XCTAssertTrue(came)
        let done = await settled(model)
        XCTAssertTrue(done)
        try await Task.sleep(for: .milliseconds(100))
        let after = await Self.treeRequests(server).dropFirst(2)
        XCTAssertEqual(Array(after), [3], "once more, once")
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LIVE_04_aWholeRefreshSentAfterAnEventCoversIt() async throws {
        let gate = MockGate()
        var responder = try MockResponder.demo()
        responder.holdBeforeTreeRequest = (2, gate)
        let (model, server, session) = try await inspect(responder)
        _ = await Self.watching(server)
        try await server.sendEvent(Self.roots(3))
        let held = await Wait.until { await Self.treeRequests(server).count == 2 }
        XCTAssertTrue(held)
        try await server.sendEvent(Self.roots(6))
        try await Task.sleep(for: .milliseconds(50))
        // ⌘R goes after the subtree on its way, and after the event: it holds 6's change.
        model.refresh()
        await gate.open()
        let came = await Wait.until { await Self.treeRequests(server).count == 3 }
        XCTAssertTrue(came)
        let done = await settled(model)
        XCTAssertTrue(done)
        try await Task.sleep(for: .milliseconds(100))
        let after = await Self.treeRequests(server).dropFirst(2)
        XCTAssertEqual(Array(after), [nil])
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_LIVE_04_withNotificationsOnTheEnvironmentsRefreshStillWaitsForTheAppToRedraw() async throws {
        var responder = try MockResponder.demo()
        responder.environment = MockEnvironment.iPhone()
        let (model, server, session) = try await inspect(responder)
        _ = await Self.watching(server)
        model.environmentSettleDelay = .milliseconds(500)
        let before = await Self.treeRequests(server).count
        model.setEnvironment(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        // A change of what layers draw alone comes as no event (P-WATCH-07, P-WATCH-09).
        try await Task.sleep(for: .milliseconds(200))
        let early = await Self.treeRequests(server).count
        XCTAssertEqual(early, before, "the app has not redrawn yet")
        let came = await Wait.until(within: .seconds(2)) { await Self.treeRequests(server).count > before }
        XCTAssertTrue(came)
        let after = await Self.treeRequests(server).last
        XCTAssertEqual(after, .some(nil), "the whole tree")
        await session.close()
        await server.stop()
    }
}
