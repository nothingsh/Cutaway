import Combine
import CutawayModel
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

/// The app list's state: C-LIST-01 to C-LIST-03, and the model side of C-CONN-07 and C-CONN-08.
final class AppListStoreTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")

    private static let demo = AppInfo(
        name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.4.0")

    private static let simulator = AppLocation.simulator(port: 48160)

    /// A session that is good only as a value: it has no connection behind it.
    private func session() -> Session {
        Session(channel: InertChannel(), client: Self.client)
    }

    // MARK: - C-LIST-01

    @MainActor
    func test_C_LIST_01_aFoundAppIsListedWithItsInfo() {
        let model = AppListStore()
        XCTAssertEqual(model.entries, [])

        model.apply(.found(Self.simulator, Self.demo, session()))

        XCTAssertEqual(model.entries, [
            AppEntry(id: Self.simulator, info: Self.demo, status: .ready(.active), icon: nil),
        ])
        XCTAssertNotNil(model.session(at: Self.simulator))
    }

    @MainActor
    func test_C_LIST_01_inspectingAnAppRecordsItAndLeavingClearsIt() {
        let model = AppListStore()
        model.apply(.found(Self.simulator, Self.demo, session()))
        XCTAssertNil(model.inspectedApp)

        model.inspect(Self.simulator)
        XCTAssertEqual(model.inspectedApp, Self.simulator)

        model.leaveInspection()
        XCTAssertNil(model.inspectedApp)

        // An app that is not in the list cannot be inspected.
        model.inspect(.simulator(port: 48167))
        XCTAssertNil(model.inspectedApp)
    }

    func test_C_LIST_01_theIconArrivesThroughTheWholeChain() async throws {
        // MockServer → Discovery → AppListStore, over a real connection.
        let server = try await MockServer.start(script: try .fixtures("handshake", "app-icon"))
        let location = AppLocation.simulator(port: server.port)
        let discovery = Discovery(configuration: DiscoveryConfiguration(
            client: Self.client, simulatorPorts: [server.port], devicePorts: [],
            usbmuxdSocketPath: nil, scanInterval: .milliseconds(50)))
        let model = await AppListStore()
        await model.follow(discovery.events)
        await discovery.start()

        let loaded = await Wait.until { await model.entries.first?.icon != nil }
        XCTAssertTrue(loaded)
        let entry = await model.entries.first
        XCTAssertEqual(entry?.id, location)
        XCTAssertEqual(entry?.info, Self.demo)
        XCTAssertEqual(entry?.status, .ready(.active))
        XCTAssertEqual(entry?.icon?.pixelWidth, 2)
        XCTAssertEqual(entry?.icon?.pixelHeight, 2)
        XCTAssertEqual(
            entry?.icon.map { [UInt8]($0.pixels) },
            [
                0x00, 0x00, 0xFF, 0xFF, 0x00, 0xFF, 0x00, 0xFF,
                0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00,
            ])

        await discovery.stop()
        await server.stop()
    }

    func test_C_LIST_01_anIconThatDoesNotDecodeLeavesTheEntryWithoutOne() async throws {
        var icon = try FrameCodec.decode(
            try Fixtures.data(scenario: "app-icon", file: "02-s2c-app-icon.bin"))
        icon.body = .appIcon(AppIcon(image: EncodedImage(
            encoding: .bgra8PremultipliedLzfse, pixelWidth: 2, pixelHeight: 2, bytesPerRow: 8,
            scale: 1, data: Data([0xDE, 0xAD, 0xBE, 0xEF]))))
        var steps = try MockScript.fixtures("handshake").steps
        steps += [.expect(.getAppIcon, as: 1), .send(icon)]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let discovery = Discovery(configuration: DiscoveryConfiguration(
            client: Self.client, simulatorPorts: [server.port], devicePorts: [],
            usbmuxdSocketPath: nil, scanInterval: .milliseconds(50)))
        let model = await AppListStore()
        await model.follow(discovery.events)
        await discovery.start()

        // The icon was asked for and answered…
        let answered = await Wait.until { await server.receivedFrames.count == 2 }
        XCTAssertTrue(answered)
        try await Task.sleep(for: .milliseconds(100))
        // …and the entry is there, without an icon.
        let entries = await model.entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries.first?.icon)

        await discovery.stop()
        await server.stop()
    }

    func test_C_LIST_01_anIconForAnAppThatIsGoneIsDropped() async throws {
        // The icon is answered 200 ms after it was asked for; by then the app has been lost
        // and another one has been found at the same location.
        var steps = try MockScript.fixtures("handshake").steps
        steps += [
            .expect(.getAppIcon, as: 1),
            .pause(.milliseconds(200)),
            .send(try FrameCodec.decode(
                try Fixtures.data(scenario: "app-icon", file: "02-s2c-app-icon.bin"))),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let first = Session(channel: channel, client: Self.client)
        _ = try await first.handshake()

        let model = await AppListStore()
        await model.apply(.found(Self.simulator, Self.demo, first))
        let asked = await Wait.until { await server.receivedFrames.count == 2 }
        XCTAssertTrue(asked)

        // Lost, and something else found in its place, before the icon arrives.
        var other = Self.demo
        other.name = "Other"
        await model.apply(.lost(Self.simulator))
        await model.apply(.found(Self.simulator, other, session()))

        try await Task.sleep(for: .milliseconds(400))
        let entries = await model.entries
        XCTAssertEqual(entries.map(\.info?.name), ["Other"])
        XCTAssertNil(entries.first?.icon, "the first app's icon landed on the second app")

        await first.close()
        await server.stop()
    }

    func test_C_LIST_01_eventsOfAStreamAreApplied() async {
        let (events, continuation) = AsyncStream.makeStream(of: DiscoveryEvent.self)
        let model = await AppListStore()
        await model.follow(events)

        continuation.yield(.found(Self.simulator, Self.demo, session()))
        let listed = await Wait.until { await model.entries.count == 1 }
        XCTAssertTrue(listed)

        continuation.yield(.lost(Self.simulator))
        let gone = await Wait.until { await model.entries.isEmpty }
        XCTAssertTrue(gone)
        continuation.finish()
    }

    // MARK: - C-CONN-08, C-LIST-03

    @MainActor
    func test_C_CONN_08_stateChangesForUnknownOrIncompatibleAppsAreIgnored() {
        let model = AppListStore()
        model.apply(.stateChanged(Self.simulator, .background))
        XCTAssertEqual(model.entries, [])

        let incompatible = AppEntry.Status.incompatible(
            local: Version(major: 1, minor: 0), remote: Version(major: 0, minor: 1))
        model.apply(.incompatible(
            Self.simulator, Self.demo, local: Version(major: 1, minor: 0),
            remote: Version(major: 0, minor: 1)))
        model.apply(.stateChanged(Self.simulator, .background))
        XCTAssertEqual(model.entries.first?.status, incompatible)
    }

    // MARK: - C-CONN-07

    @MainActor
    func test_C_CONN_07_aLostAppLeavesTheListAndTheInspection() {
        let model = AppListStore()
        let other = AppLocation.simulator(port: 48161)
        model.apply(.found(Self.simulator, Self.demo, session()))
        model.apply(.found(other, Self.demo, session()))
        model.inspect(Self.simulator)

        model.apply(.lost(Self.simulator))

        XCTAssertEqual(model.entries.map(\.id), [other])
        XCTAssertNil(model.inspectedApp)
        XCTAssertNil(model.session(at: Self.simulator))

        // Losing an app that is not the inspected one leaves the inspection alone.
        model.inspect(other)
        model.apply(.lost(.simulator(port: 48165)))
        XCTAssertEqual(model.inspectedApp, other)
    }

    // MARK: - C-LIST-02

    @MainActor
    func test_C_LIST_02_anIncompatibleAppIsListedWithBothVersions() {
        let model = AppListStore()
        let local = Version(major: 1, minor: 0)
        let remote = Version(major: 0, minor: 1)

        model.apply(.incompatible(Self.simulator, Self.demo, local: local, remote: remote))

        XCTAssertEqual(model.entries, [
            AppEntry(
                id: Self.simulator, info: Self.demo,
                status: .incompatible(local: local, remote: remote), icon: nil),
        ])
        XCTAssertFalse(model.entries[0].isInspectable)

        // It cannot be inspected.
        model.inspect(Self.simulator)
        XCTAssertNil(model.inspectedApp)
    }

    @MainActor
    func test_C_LIST_02_aRepeatedIncompatibleReportDoesNotPublish() {
        let model = AppListStore()
        let local = Version(major: 1, minor: 0)
        let remote = Version(major: 0, minor: 1)
        var publishes = 0
        let subscription = model.$entries.dropFirst().sink { _ in publishes += 1 }

        // Discovery repeats this every round.
        for _ in 0..<5 {
            model.apply(.incompatible(Self.simulator, Self.demo, local: local, remote: remote))
        }
        XCTAssertEqual(publishes, 1, "an unchanged entry must not publish again")

        // A report that differs does publish.
        model.apply(.incompatible(
            Self.simulator, Self.demo, local: local, remote: Version(major: 2, minor: 0)))
        XCTAssertEqual(publishes, 2)
        subscription.cancel()
    }

    @MainActor
    func test_C_LIST_02_anAppThatBecomesIncompatibleLeavesTheInspection() {
        let model = AppListStore()
        model.apply(.found(Self.simulator, Self.demo, session()))
        model.inspect(Self.simulator)

        model.apply(.incompatible(
            Self.simulator, Self.demo, local: Version(major: 0, minor: 1),
            remote: Version(major: 1, minor: 0)))

        XCTAssertNil(model.inspectedApp)
        XCTAssertNil(model.session(at: Self.simulator))
        XCTAssertFalse(model.entries[0].isInspectable)
    }

    @MainActor
    func test_C_LIST_02_anAppThatBecomesCompatibleReplacesItsEntry() {
        let model = AppListStore()
        model.apply(.incompatible(
            Self.simulator, nil, local: Version(major: 0, minor: 1),
            remote: Version(major: 1, minor: 0)))
        XCTAssertNil(model.entries.first?.info)

        model.apply(.found(Self.simulator, Self.demo, session()))

        XCTAssertEqual(model.entries.count, 1)
        XCTAssertEqual(model.entries.first?.status, .ready(.active))
        XCTAssertEqual(model.entries.first?.info, Self.demo)
    }

    // MARK: - C-HIER-02, C-CONN-09: the inspection's state

    @MainActor
    func test_C_HIER_02_theInspectionStateLivesAsLongAsTheConnection() {
        let model = AppListStore()
        XCTAssertNil(model.inspection(at: Self.simulator))
        model.apply(.found(Self.simulator, Self.demo, session()))
        // Not before the app is inspected.
        XCTAssertNil(model.inspection(at: Self.simulator))

        model.inspect(Self.simulator)
        let first = model.inspection(at: Self.simulator)
        XCTAssertNotNil(first)

        // Leaving and coming back finds the same state.
        model.leaveInspection()
        XCTAssertTrue(model.inspection(at: Self.simulator) === first)
        model.inspect(Self.simulator)
        XCTAssertTrue(model.inspection(at: Self.simulator) === first)

        // It goes with the connection.
        model.apply(.lost(Self.simulator))
        XCTAssertNil(model.inspection(at: Self.simulator))

        // A new connection at the same place starts afresh.
        model.apply(.found(Self.simulator, Self.demo, session()))
        model.inspect(Self.simulator)
        let second = model.inspection(at: Self.simulator)
        XCTAssertNotNil(second)
        XCTAssertFalse(second === first)

        // So does one that replaces a connection without a loss in between; the window
        // must not stay on an inspection whose state is gone.
        model.apply(.found(Self.simulator, Self.demo, session()))
        XCTAssertNil(model.inspection(at: Self.simulator))
        XCTAssertNil(model.inspectedApp)

        // An app that turns out to be incompatible has none.
        model.inspect(Self.simulator)
        XCTAssertNotNil(model.inspection(at: Self.simulator))
        model.apply(.incompatible(
            Self.simulator, Self.demo, local: Version(major: 0, minor: 1),
            remote: Version(major: 1, minor: 0)))
        XCTAssertNil(model.inspection(at: Self.simulator))
    }

    @MainActor
    func test_C_HIER_02_theInspectionExistsWhenTheInspectedAppIsPublished() {
        let model = AppListStore()
        model.apply(.found(Self.simulator, Self.demo, session()))

        // The window asks for the inspection the moment it hears of the inspected app.
        var found: [Bool] = []
        let subscription = model.$inspectedApp.dropFirst().sink { location in
            found.append(location.flatMap { model.inspection(at: $0) } != nil)
        }
        model.inspect(Self.simulator)
        subscription.cancel()

        XCTAssertEqual(found, [true])
    }

    func test_C_HIER_02_theStateSurvivesLeavingAndComingBackOverOneConnection() async throws {
        // The second answer differs from the first: layer 20 is new.
        var changed = try Fixtures.hierarchy()
        changed.nodes.append(LayerTreeTests.node(20, parent: 2))
        var steps = try MockScript.fixtures(
            "handshake", "app-icon", "hierarchy", "layer-details").steps
        steps += [
            // The attributes of layer 3, never answered; leaving cancels them.
            .expect(.getLayerDetails, as: 40),
            .expect(.cancel, as: 41),
            .expect(.getHierarchy, as: 50),
            .send(Frame(requestID: 50, body: .hierarchy(changed))),
            // The new round's screenshots and layer 3's attributes, in either order.
            .expect(.getLayerDetails, as: 51),
            .expect(.getLayerDetails, as: 52),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client)
        _ = try await session.handshake()

        let model = await AppListStore()
        await model.apply(.found(Self.simulator, Self.demo, session))
        // MockServer answers in the script's order: the icon first.
        let iconArrived = await Wait.until { await model.entries.first?.icon != nil }
        XCTAssertTrue(iconArrived)

        await model.inspect(Self.simulator)
        let inspected = await model.inspection(at: Self.simulator)
        let inspection = try XCTUnwrap(inspected)
        let loaded = await Wait.until { await inspection.loadState == .loaded }
        XCTAssertTrue(loaded)
        let screenshots = await Wait.until {
            let progress = await inspection.detailProgress
            return progress.total > 0 && progress.completed == progress.total
        }
        XCTAssertTrue(screenshots)
        await MainActor.run {
            // Unlike how it started (C-HIER-09). A leaf draws its group image either way, so
            // nothing more is asked for.
            inspection.setExpanded(8, false)
            inspection.select(3)
        }
        // Leave only once the attributes have been asked for, or the frames vary.
        let attributesAsked = await Wait.until {
            await server.receivedFrames.filter {
                MessageKind($0.body) == .getLayerDetails
            }.count == 2
        }
        XCTAssertTrue(attributesAsked)

        await model.leaveInspection()
        await model.inspect(Self.simulator)
        let reloaded = await Wait.until { await inspection.tree.contains(20) }
        XCTAssertTrue(reloaded)

        let state = await MainActor.run {
            (inspection.isExpanded(8), inspection.isExpanded(20), inspection.selectedLayerID)
        }
        XCTAssertEqual(state.0, false)
        XCTAssertEqual(state.1, true)
        XCTAssertEqual(state.2, 3)

        // The list and the inspection used one connection (C-CONN-09): Hello, the icon, and
        // each visit's hierarchy, screenshots and the selected layer's attributes went over it.
        let connections = await server.connectionCount
        XCTAssertEqual(connections, 1)
        let all = await Wait.until { await server.receivedFrames.count == 9 }
        XCTAssertTrue(all)
        let kinds = await server.receivedFrames.map { MessageKind($0.body) }
        XCTAssertEqual(
            kinds,
            [
                .hello, .getAppIcon, .getHierarchy, .getLayerDetails, .getLayerDetails, .cancel,
                .getHierarchy, .getLayerDetails, .getLayerDetails,
            ])
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    func test_C_CONN_07_aHierarchyThatArrivesAfterTheAppIsLostChangesNothing() async throws {
        // The hierarchy is answered only after the app was lost. The window still holds the
        // inspection, as a view would until it goes away.
        let gate = MockGate()
        var steps = try MockScript.fixtures("handshake", "app-icon").steps
        steps += [
            .expect(.getHierarchy, as: 50),
            .hold(gate),
            .send(Frame(requestID: 50, body: .hierarchy(try Fixtures.hierarchy()))),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client)
        _ = try await session.handshake()

        let model = await AppListStore()
        await model.apply(.found(Self.simulator, Self.demo, session))
        let iconArrived = await Wait.until { await model.entries.first?.icon != nil }
        XCTAssertTrue(iconArrived)
        await model.inspect(Self.simulator)
        let held = await MainActor.run { model.inspection(at: Self.simulator) }
        let inspection = try XCTUnwrap(held)
        let asked = await Wait.until { await server.receivedFrames.count == 3 }
        XCTAssertTrue(asked)

        await model.apply(.lost(Self.simulator))
        await gate.open()
        // The late hierarchy was taken in: the frame really arrived.
        let loaded = await Wait.until { await inspection.loadState == .loaded }
        XCTAssertTrue(loaded)
        // Longer than the wait for the rows in view before a first batch (200 ms).
        try await Task.sleep(for: .milliseconds(400))

        let after = await MainActor.run {
            (model.inspectedApp, model.inspection(at: Self.simulator) == nil, model.entries.count)
        }
        XCTAssertNil(after.0)
        XCTAssertTrue(after.1)
        XCTAssertEqual(after.2, 0)
        let kinds = await server.receivedFrames.map { MessageKind($0.body) }
        XCTAssertEqual(kinds, [.hello, .getAppIcon, .getHierarchy], "no screenshots for a lost app")
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])

        await session.close()
        await server.stop()
    }

    // MARK: - Screenshots and the inspection's lifetime

    func test_C_DET_02_leavingTheInspectionCancelsItsScreenshots() async throws {
        let server = try await MockServer.start(script: try .fixtures(
            "handshake", "app-icon", "hierarchy", "layer-details-cancelled"))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client)
        _ = try await session.handshake()
        let model = await AppListStore()
        await model.apply(.found(Self.simulator, Self.demo, session))
        let iconArrived = await Wait.until { await model.entries.first?.icon != nil }
        XCTAssertTrue(iconArrived)

        await model.inspect(Self.simulator)
        let inspected = await model.inspection(at: Self.simulator)
        let inspection = try XCTUnwrap(inspected)
        let first = await Wait.until { await inspection.images[2] != nil }
        XCTAssertTrue(first)

        await model.leaveInspection()
        let cancelled = await Wait.until {
            await server.receivedFrames.last.map { MessageKind($0.body) } == .cancel
        }
        XCTAssertTrue(cancelled)

        await session.close()
        await server.stop()
    }

    func test_C_DET_04_anAppThatBecomesActiveReloadsItsOpenInspection() async throws {
        var steps = try MockScript.fixtures("handshake", "app-icon", "app-not-active").steps
        steps += [
            .expect(.getHierarchy, as: 50),
            .send(Frame(requestID: 50, body: .hierarchy(try Fixtures.hierarchy()))),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client)
        _ = try await session.handshake()
        let model = await AppListStore()
        await model.apply(.found(Self.simulator, Self.demo, session))
        let iconArrived = await Wait.until { await model.entries.first?.icon != nil }
        XCTAssertTrue(iconArrived)

        await model.inspect(Self.simulator)
        let inspected = await model.inspection(at: Self.simulator)
        let inspection = try XCTUnwrap(inspected)
        let failed = await Wait.until { await inspection.loadState == .failed(.appNotActive) }
        XCTAssertTrue(failed)

        await model.apply(.stateChanged(Self.simulator, .active))
        let loaded = await Wait.until { await inspection.loadState == .loaded }
        XCTAssertTrue(loaded)

        await session.close()
        await server.stop()
    }

    func test_C_REND_05_theInspectionAsksWithTheGivenTextureLimit() async throws {
        let server = try await MockServer.start(script: try .fixtures(
            "handshake", "app-icon", "hierarchy", "layer-details"))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client)
        _ = try await session.handshake()
        let model = await AppListStore(maxTextureDimension: 8_192)
        await model.apply(.found(Self.simulator, Self.demo, session))
        let iconArrived = await Wait.until { await model.entries.first?.icon != nil }
        XCTAssertTrue(iconArrived)

        await model.inspect(Self.simulator)
        let asked = await Wait.until {
            await server.receivedFrames.contains { MessageKind($0.body) == .getLayerDetails }
        }
        XCTAssertTrue(asked)
        let request = await server.receivedFrames.compactMap { frame -> GetLayerDetails? in
            guard case .getLayerDetails(let request) = frame.body else { return nil }
            return request
        }.first
        XCTAssertEqual(request?.maxTextureDimension, 8_192)

        await session.close()
        await server.stop()
    }
}
