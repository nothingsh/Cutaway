import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// Waiting for a lost app and inspecting it again when it comes back (C-WIN-04), as the app
/// list model does it, fed with discovery events.
final class ReconnectionTests: XCTestCase {
    private static let demo = AppInfo(
        name: "Demo", bundleID: "dev.cutaway.demo", appVersion: "1.0", deviceName: "iPhone 16",
        deviceKind: .phone, isSimulator: true, osName: "iOS", osVersion: "18.0",
        screenSize: Size(width: 393, height: 852), screenScale: 3, serverVersion: "0.1.0")
    private static let first = AppLocation.simulator(port: 48160)
    private static let other = AppLocation.simulator(port: 48161)
    private static let later = AppLocation.simulator(port: 48163)

    private static var otherApp: AppInfo {
        var info = demo
        info.name = "Other"
        info.bundleID = "dev.cutaway.other"
        return info
    }

    private func session() -> Session {
        Session(channel: InertChannel(), client: ClientInfo(name: "Cutaway", version: "0.1.0"))
    }

    /// A model listing Demo and Other, inspecting Demo.
    @MainActor
    private func inspecting() -> AppListStore {
        let model = AppListStore()
        model.apply(.found(Self.first, Self.demo, session()))
        model.apply(.found(Self.other, Self.otherApp, session()))
        model.inspect(Self.first)
        return model
    }

    // MARK: - Identity

    func test_C_WIN_04_anIdentityIsTheAppOnItsDevice() {
        let demo = AppIdentity(Self.demo)
        XCTAssertNotNil(demo)
        var info = Self.demo
        info.appVersion = "2.0"
        info.name = "Renamed"
        XCTAssertEqual(AppIdentity(info), demo, "the version and the name do not count")
        for change in [
            { (info: inout AppInfo) in info.bundleID = "dev.cutaway.other" },
            { (info: inout AppInfo) in info.deviceName = "iPad" },
            { (info: inout AppInfo) in info.isSimulator = false },
        ] {
            var changed = Self.demo
            change(&changed)
            XCTAssertNotEqual(AppIdentity(changed), demo)
        }
        info.bundleID = nil
        XCTAssertNil(AppIdentity(info))
        info.bundleID = ""
        XCTAssertNil(AppIdentity(info))
    }

    // MARK: - Waiting

    @MainActor
    func test_C_WIN_04_losingTheInspectedAppWaitsForIt() {
        let model = inspecting()
        model.apply(.lost(Self.first))
        XCTAssertNil(model.inspectedApp)
        XCTAssertEqual(model.awaitingReconnection, AppIdentity(Self.demo))
    }

    @MainActor
    func test_C_WIN_04_losingAnAppNotInspectedWaitsForNothing() {
        let model = inspecting()
        model.apply(.lost(Self.other))
        XCTAssertNil(model.awaitingReconnection)
        XCTAssertEqual(model.inspectedApp, Self.first)
    }

    @MainActor
    func test_C_WIN_04_theSameAppOnAnotherPortIsInspectedAgain() throws {
        let model = inspecting()
        model.apply(.lost(Self.first))
        model.apply(.found(Self.later, Self.demo, session()))
        XCTAssertEqual(model.inspectedApp, Self.later)
        XCTAssertNil(model.awaitingReconnection)
        XCTAssertTrue(try XCTUnwrap(model.inspection(at: Self.later)).isOpen)
    }

    @MainActor
    func test_C_WIN_04_theSameAppOnTheSamePortIsInspectedAgain() {
        let model = inspecting()
        model.apply(.lost(Self.first))
        model.apply(.found(Self.first, Self.demo, session()))
        XCTAssertEqual(model.inspectedApp, Self.first)
    }

    @MainActor
    func test_C_WIN_04_anotherAppOnTheSamePortIsNot() {
        let model = inspecting()
        model.apply(.lost(Self.first))
        var stranger = Self.otherApp
        stranger.bundleID = "dev.cutaway.stranger"
        model.apply(.found(Self.first, stranger, session()))
        XCTAssertNil(model.inspectedApp)
        XCTAssertEqual(model.awaitingReconnection, AppIdentity(Self.demo), "still waiting")
    }

    @MainActor
    func test_C_WIN_04_anIncompatibleReturnIsNot() {
        let model = inspecting()
        model.apply(.lost(Self.first))
        model.apply(.incompatible(
            Self.first, Self.demo, local: Version(major: 0, minor: 1),
            remote: Version(major: 1, minor: 0)))
        XCTAssertNil(model.inspectedApp)
        XCTAssertEqual(model.awaitingReconnection, AppIdentity(Self.demo))
    }

    @MainActor
    func test_C_WIN_04_anIncompatibleLossWaitsToo() {
        let model = inspecting()
        model.apply(.incompatible(
            Self.first, Self.demo, local: Version(major: 0, minor: 1),
            remote: Version(major: 1, minor: 0)))
        XCTAssertEqual(model.awaitingReconnection, AppIdentity(Self.demo))
        model.apply(.found(Self.first, Self.demo, session()))
        XCTAssertEqual(model.inspectedApp, Self.first)
    }

    @MainActor
    func test_C_WIN_04_closingTheWindowStopsWaiting() {
        let model = inspecting()
        model.apply(.lost(Self.first))
        model.leaveInspection()
        XCTAssertNil(model.awaitingReconnection)
        model.apply(.found(Self.later, Self.demo, session()))
        XCTAssertNil(model.inspectedApp)
    }

    @MainActor
    func test_C_WIN_04_choosingAnotherAppStopsWaiting() {
        let model = inspecting()
        model.apply(.lost(Self.first))
        model.inspect(Self.other)
        XCTAssertNil(model.awaitingReconnection)
        model.apply(.found(Self.later, Self.demo, session()))
        XCTAssertEqual(model.inspectedApp, Self.other, "Demo coming back takes nothing over")
    }

    @MainActor
    func test_C_WIN_04_anAppWithoutABundleIdentifierIsNotWaitedFor() {
        var nameless = Self.demo
        nameless.bundleID = nil
        let model = AppListStore()
        model.apply(.found(Self.first, nameless, session()))
        model.inspect(Self.first)
        model.apply(.lost(Self.first))
        XCTAssertNil(model.awaitingReconnection)
    }

    // MARK: - What comes back

    @MainActor
    func test_C_WIN_04_theReconnectedInspectionKeepsItsSettingsButNotItsLayers() throws {
        let model = inspecting()
        let old = try XCTUnwrap(model.inspection(at: Self.first))
        old.apply(try Fixtures.hierarchy())
        old.setPreviewMode(.threeD)
        old.rotate(byDragOf: 30, 10)
        old.setShowsHiddenLayers(true)
        old.setBorderStyle(.off)
        old.setSearchText("label")
        old.setExpanded(6, false)
        old.select(4)
        old.focus(on: 2)
        let settings = old.settings

        model.apply(.lost(Self.first))
        model.apply(.found(Self.later, Self.demo, session()))
        let new = try XCTUnwrap(model.inspection(at: Self.later))
        XCTAssertFalse(new === old)
        XCTAssertEqual(new.settings, settings)
        XCTAssertEqual(new.previewMode, .threeD)
        XCTAssertNil(new.focusedLayerID)
        XCTAssertNil(new.selectedLayerID)
        XCTAssertEqual(new.tree, .empty, "the layers are asked for again")
    }

    @MainActor
    func test_C_WIN_04_searchTextThatReachesTheLostInspectionLateCarriesOver() throws {
        let model = inspecting()
        let old = try XCTUnwrap(model.inspection(at: Self.first))
        old.apply(try Fixtures.hierarchy())
        old.setSearchText("lab")

        model.apply(.lost(Self.first))
        // The search field's debounce delivers what was typed before the loss only now.
        old.setSearchText("label")
        model.apply(.found(Self.later, Self.demo, session()))
        let new = try XCTUnwrap(model.inspection(at: Self.later))
        XCTAssertEqual(new.searchText, "label")
        XCTAssertEqual(new.settings, old.settings)
    }

    @MainActor
    func test_C_WIN_04_whatWasShownCarriesOverOnceNothingHoldsTheLostInspection() throws {
        let model = inspecting()
        try XCTUnwrap(model.inspection(at: Self.first)).setBorderStyle(.off)
        model.apply(.lost(Self.first))
        model.apply(.found(Self.later, Self.demo, session()))
        XCTAssertFalse(try XCTUnwrap(model.inspection(at: Self.later)).borders.showsBorders)
    }

    @MainActor
    func test_C_WIN_03_aNewConnectionOnTheSamePortClosesTheOldInspection() throws {
        let model = inspecting()
        let old = try XCTUnwrap(model.inspection(at: Self.first))
        XCTAssertTrue(old.isOpen)
        // Found again without having been lost first.
        model.apply(.found(Self.first, Self.demo, session()))
        XCTAssertTrue(old.connection.isLost)
        XCTAssertFalse(old.isOpen, "it asks nothing more of the old connection")
        XCTAssertFalse(old.mayFetchScreenshots)
    }

    @MainActor
    func test_C_WIN_04_aViewFittedToAFocusIsNotCarriedOverWithoutIt() throws {
        let model = inspecting()
        let old = try XCTUnwrap(model.inspection(at: Self.first))
        old.apply(try Fixtures.hierarchy())
        old.setPreviewMode(.threeD)
        old.focus(on: 6)
        old.rotate(byDragOf: 30, 10)
        old.zoom(by: 4, about: ScenePoint(x: 40, y: 40), in: Viewport(width: 400, height: 400))
        let yaw = old.camera.yaw

        model.apply(.lost(Self.first))
        model.apply(.found(Self.later, Self.demo, session()))
        let new = try XCTUnwrap(model.inspection(at: Self.later))
        XCTAssertNil(new.focusedLayerID)
        XCTAssertEqual(new.camera.zoom, 1, "the zoom was into the focus, which is gone")
        XCTAssertEqual(new.camera.pan, .zero)
        XCTAssertEqual(new.camera.yaw, yaw, "how it was turned stays")
    }

    @MainActor
    func test_C_WIN_04_choosingTheWaitedForAppByHandCarriesItsSettingsOver() throws {
        // Two entries of the same app (two simulators with the same name): the window waits
        // for the first, and the user chooses the second.
        let model = inspecting()
        let twin = AppLocation.simulator(port: 48162)
        model.apply(.found(twin, Self.demo, session()))
        XCTAssertEqual(
            model.inspectedApp, Self.first, "a twin found while inspecting is just listed")
        try XCTUnwrap(model.inspection(at: Self.first)).setBorderStyle(.off)
        model.apply(.lost(Self.first))
        model.inspect(twin)
        XCTAssertNil(model.awaitingReconnection)
        XCTAssertFalse(try XCTUnwrap(model.inspection(at: twin)).borders.showsBorders)
    }

    @MainActor
    func test_C_WIN_04_choosingAnotherAppByHandWhileWaitingCarriesNothingOver() throws {
        let model = inspecting()
        let old = try XCTUnwrap(model.inspection(at: Self.first))
        old.setBorderStyle(.off)
        model.apply(.lost(Self.first))
        // The user's choice comes first: the app is listed, and chosen, before the model
        // would have inspected it on its own. Here: found with another identity first.
        var renamed = Self.demo
        renamed.deviceName = "Another iPhone"
        model.apply(.found(Self.later, renamed, session()))
        XCTAssertNil(model.inspectedApp)
        model.inspect(Self.later)
        XCTAssertTrue(
            try XCTUnwrap(model.inspection(at: Self.later)).borders.showsBorders,
            "another app: nothing is carried over")
    }

    // MARK: - The app's icon before the first hierarchy

    /// The first hierarchy waits for the app's icon to be answered, so that the two go out in
    /// one order: the server answers in order anyway (P-REQ-06), and scripts that replay a
    /// connection expect the icon first.
    @MainActor
    func test_C_WIN_04_theFirstHierarchyWaitsForTheIcon() async throws {
        let server = try await MockServer.start(script: try .fixtures("handshake", "hierarchy"))
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: ClientInfo(name: "Cutaway", version: "0.4.0"))
        _ = try await session.handshake()
        // Stands for the icon's request: it ends when the test says so.
        let (answered, answer) = AsyncStream<Void>.makeStream()
        let icon = Task {
            for await _ in answered { break }
        }
        let model = InspectionStore(session: session)

        model.enter(after: icon)
        try await Task.sleep(for: .milliseconds(200))
        var kinds = await server.receivedFrames.map { MessageKind($0.body) }
        XCTAssertEqual(kinds, [.hello], "nothing before the icon is in")
        answer.yield()
        answer.finish()
        let asked = await Wait.until {
            await server.receivedFrames.map { MessageKind($0.body) } == [.hello, .getHierarchy]
        }
        XCTAssertTrue(asked)
        kinds = await server.receivedFrames.map { MessageKind($0.body) }
        XCTAssertEqual(kinds, [.hello, .getHierarchy])

        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_WIN_04_theListPassesTheIconToTheInspection() {
        let model = AppListStore()
        model.apply(.found(Self.first, Self.demo, session()))
        model.inspect(Self.first)
        let icon = try? XCTUnwrap(model.iconLoad(at: Self.first))
        XCTAssertNotNil(icon)
        XCTAssertEqual(
            model.inspection(at: Self.first)?.enteredAfter, icon,
            "the first hierarchy waits for this icon")
    }

    @MainActor
    func test_C_PREV_18_aReconnectedInspectionKeepsTheConstraintEndsSwitch() throws {
        let model = inspecting()
        let old = try XCTUnwrap(model.inspection(at: Self.first))
        old.toggleConstraintEnds()
        model.apply(.lost(Self.first))
        model.apply(.found(Self.later, Self.demo, session()))
        XCTAssertEqual(model.inspection(at: Self.later)?.showsAllConstraintEnds, true)
    }
}
