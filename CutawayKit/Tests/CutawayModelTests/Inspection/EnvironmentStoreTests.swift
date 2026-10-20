import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-ENV-01 to C-ENV-03: the inspection asks for the app's trait environment, changes it one
/// `SetEnvironment` at a time and takes the whole tree again after each change.
final class EnvironmentStoreTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "1.2.0")
    private static let iPhone = MockEnvironment.iPhone()

    private static func session(to server: MockServer) async throws -> Session {
        let channel = try await ConnectionChannel.connect(
            host: "127.0.0.1", port: server.port, timeout: .seconds(2))
        let session = Session(channel: channel, client: Self.client, requestTimeout: .seconds(10))
        _ = try await session.handshake()
        return session
    }

    private static func responding(
        _ environment: MockEnvironment? = iPhone, change: (inout MockResponder) -> Void = { _ in }
    ) throws -> MockScript {
        var responder = try MockResponder.demo()
        responder.environment = environment
        change(&responder)
        return MockScript(steps: try MockScript.fixtures("handshake").steps + [.respond(responder)])
    }

    /// An inspection, entered and loaded. The refresh after a change comes at once unless
    /// `settleDelay` says otherwise.
    @MainActor
    private static func model(_ session: Session, settleDelay: Duration = .zero) async -> InspectionStore {
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.rowsWait = .zero
        model.environmentSettleDelay = settleDelay
        model.enter()
        let ready = await Wait.until { await MainActor.run { model.loadState == .loaded } }
        XCTAssertTrue(ready)
        return model
    }

    private static func kinds(_ server: MockServer) async -> [MessageKind] {
        await server.receivedFrames.map { MessageKind($0.body) }
    }

    /// The overrides of each `SetEnvironment`, in order.
    private static func sent(_ server: MockServer) async -> [Traits] {
        await server.receivedFrames.compactMap { frame in
            if case .setEnvironment(let request) = frame.body { return request.overrides }
            return nil
        }
    }

    /// Waits until no change is on its way and the tree is loaded again.
    @MainActor
    private static func settled(_ model: InspectionStore) async -> Bool {
        await Wait.until {
            await MainActor.run {
                model.environment.controls?.isSending == false && model.loadState == .loaded
                    && !model.loader.isLoading
            }
        }
    }

    // MARK: - C-ENV-01

    @MainActor
    func test_C_ENV_01_allFiveKindsAreOfferedWithTheirCurrentValues() async throws {
        let server = try await MockServer.start(script: try Self.responding())
        let session = try await Self.session(to: server)
        let model = await Self.model(session)

        let controls = try XCTUnwrap(model.environment.controls)
        XCTAssertEqual(controls.overridable, TraitKind.allCases)
        XCTAssertEqual(controls.environment.current, Self.iPhone.own)
        XCTAssertEqual(controls.shown, .unspecified)
        XCTAssertFalse(controls.isOverriding)
        XCTAssertTrue(model.canChangeEnvironment)
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ENV_01_onlyTheAppearanceIsOfferedBeforeIOS17() async throws {
        let server = try await MockServer.start(
            script: try Self.responding(.iPhone(overridable: [.userInterfaceStyle])))
        let session = try await Self.session(to: server)
        let model = await Self.model(session)

        XCTAssertEqual(model.environment.controls?.overridable, [.userInterfaceStyle])
        // A kind the app cannot override is not sent.
        model.setEnvironment(.layoutDirection, to: .layoutDirection(.rightToLeft))
        try await Task.sleep(for: .milliseconds(100))
        let sent = await Self.sent(server)
        XCTAssertEqual(sent, [])
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ENV_01_aProtocol11PeerIsNotAsked() async throws {
        let server = try await MockServer.start(script: try Self.responding().asProtocol11())
        let session = try await Self.session(to: server)
        let model = await Self.model(session)

        XCTAssertEqual(model.environment, .unavailable)
        let kinds = await Self.kinds(server)
        XCTAssertFalse(kinds.contains(.getEnvironment))
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ENV_01_anAppThatCanOverrideNothingHasNoControls() async throws {
        let server = try await MockServer.start(script: try Self.responding(nil))
        let session = try await Self.session(to: server)
        let model = await Self.model(session)

        XCTAssertEqual(model.environment, .unavailable)
        XCTAssertFalse(model.canChangeEnvironment)
        await session.close()
        await server.stop()
    }

    // MARK: - C-ENV-02

    @MainActor
    func test_C_ENV_02_choosingDarkSendsOnlyTheAppearanceThenTakesTheTreeAgain() async throws {
        let server = try await MockServer.start(script: try Self.responding())
        let session = try await Self.session(to: server)
        let model = await Self.model(session)
        let before = await Self.kinds(server).count

        model.setEnvironment(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        XCTAssertEqual(model.environment.controls?.shown.userInterfaceStyle, .dark, "shown at once")
        XCTAssertEqual(model.environment.controls?.isSending, true)
        let screenshots = await Wait.until {
            await Self.kinds(server).dropFirst(before).contains(.getLayerDetails)
        }
        XCTAssertTrue(screenshots)

        let sent = await Self.sent(server)
        XCTAssertEqual(sent, [Traits(userInterfaceStyle: .dark)])
        let after = await Self.kinds(server).dropFirst(before)
        let set = try XCTUnwrap(after.firstIndex(of: .setEnvironment))
        let tree = try XCTUnwrap(after.firstIndex(of: .getHierarchy))
        XCTAssertLessThan(set, tree, "the whole tree is taken again after the answer")
        let isSettled = await Self.settled(model)
        XCTAssertTrue(isSettled)
        XCTAssertEqual(model.environment.controls?.environment.current.userInterfaceStyle, .dark)
        XCTAssertTrue(model.environment.controls?.isOverriding == true)
        await session.close()
        await server.stop()
    }

    /// Reported by the user (2026-10-20): after the appearance was overridden, the preview did
    /// not change until ⌘R. Every screenshot is to be taken again once the answer is in.
    @MainActor
    func test_C_ENV_02_everyScreenshotIsTakenAgainAfterTheAnswer() async throws {
        let server = try await MockServer.start(script: try Self.responding())
        let session = try await Self.session(to: server)
        let model = await Self.model(session)
        let total = model.detailProgress.total
        let first = await Wait.until { await MainActor.run { model.detailProgress.completed == total } }
        XCTAssertTrue(first, "\(model.detailProgress)")
        let before = model.images.mapValues { [$0.solo?.revision, $0.group?.revision] }
        XCTAssertFalse(before.isEmpty)
        let sentBefore = await Self.kinds(server).count

        model.setEnvironment(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        let isSettled = await Self.settled(model)
        XCTAssertTrue(isSettled)
        let again = await Wait.until {
            await MainActor.run {
                model.images.allSatisfy { id, images in
                    let old = before[id] ?? []
                    return [images.solo?.revision, images.group?.revision].enumerated().allSatisfy { index, revision in
                        revision == nil || old[index] == nil || revision! > old[index]!
                    }
                }
            }
        }
        let after = await Self.kinds(server).dropFirst(sentBefore)
        XCTAssertTrue(again, "every screenshot taken again: \(after)")
        await session.close()
        await server.stop()
    }

    /// An app may change its look a moment after
    /// the change (Wikipedia, 0.3 s later), so the tree is taken again only after a pause, and
    /// no screenshot is asked for meanwhile.
    @MainActor
    func test_C_ENV_02_theRefreshWaitsForTheAppToRedraw() async throws {
        let server = try await MockServer.start(script: try Self.responding())
        let session = try await Self.session(to: server)
        let model = await Self.model(session, settleDelay: .milliseconds(400))
        let total = model.detailProgress.total
        let first = await Wait.until { await MainActor.run { model.detailProgress.completed == total } }
        XCTAssertTrue(first)
        let before = await Self.kinds(server).count

        model.setEnvironment(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        let answered = await Wait.until {
            await MainActor.run { model.environment.controls?.isSending == false }
        }
        XCTAssertTrue(answered)
        try await Task.sleep(for: .milliseconds(150))
        var after = await Self.kinds(server).dropFirst(before)
        XCTAssertEqual(Array(after), [.setEnvironment], "nothing asked for while the app redraws")
        XCTAssertEqual(model.changesOnTheirWay, 1, "screenshots wait")

        let refreshed = await Wait.until { await Self.kinds(server).dropFirst(before).contains(.getLayerDetails) }
        XCTAssertTrue(refreshed)
        after = await Self.kinds(server).dropFirst(before)
        XCTAssertEqual(Array(after.prefix(2)), [.setEnvironment, .getHierarchy])
        XCTAssertEqual(model.changesOnTheirWay, 0)
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ENV_02_anotherChangeWhileWaitingRefreshesOnceAfterIt() async throws {
        let server = try await MockServer.start(script: try Self.responding())
        let session = try await Self.session(to: server)
        let model = await Self.model(session, settleDelay: .milliseconds(300))
        let before = await Self.kinds(server).count

        model.setEnvironment(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        let answered = await Wait.until {
            await MainActor.run { model.environment.controls?.isSending == false }
        }
        XCTAssertTrue(answered)
        // While the first change's refresh waits.
        model.setEnvironment(.layoutDirection, to: .layoutDirection(.rightToLeft))
        let refreshed = await Wait.until { await Self.kinds(server).dropFirst(before).contains(.getHierarchy) }
        XCTAssertTrue(refreshed)
        try await Task.sleep(for: .milliseconds(500))
        let after = await Self.kinds(server).dropFirst(before)
        XCTAssertEqual(after.filter { $0 == .setEnvironment }.count, 2)
        XCTAssertEqual(after.filter { $0 == .getHierarchy }.count, 1, "the first change's refresh was not made")
        let set = try XCTUnwrap(after.lastIndex(of: .setEnvironment))
        let tree = try XCTUnwrap(after.firstIndex(of: .getHierarchy))
        XCTAssertLessThan(set, tree)
        XCTAssertEqual(model.changesOnTheirWay, 0)
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ENV_03_closingWhileWaitingRefreshesNothing() async throws {
        let server = try await MockServer.start(script: try Self.responding())
        let session = try await Self.session(to: server)
        let model = await Self.model(session, settleDelay: .milliseconds(300))
        let before = await Self.kinds(server).count

        model.setEnvironment(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        let answered = await Wait.until {
            await MainActor.run { model.environment.controls?.isSending == false }
        }
        XCTAssertTrue(answered)
        model.leave()
        XCTAssertEqual(model.changesOnTheirWay, 0)
        try await Task.sleep(for: .milliseconds(500))
        let after = await Self.kinds(server).dropFirst(before)
        XCTAssertFalse(after.contains(.getHierarchy))
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ENV_02_aChangeKeepsTheOtherOverrides() async throws {
        let server = try await MockServer.start(script: try Self.responding())
        let session = try await Self.session(to: server)
        let model = await Self.model(session)

        model.setEnvironment(.contentSizeCategory, to: .contentSizeCategory(.accessibilityExtraLarge))
        var isSettled = await Self.settled(model)
        XCTAssertTrue(isSettled)
        model.setEnvironment(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        isSettled = await Self.settled(model)
        XCTAssertTrue(isSettled)

        let sent = await Self.sent(server)
        XCTAssertEqual(sent.last, Traits(userInterfaceStyle: .dark, contentSizeCategory: .accessibilityExtraLarge))
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ENV_02_threeChangesInFlightSendOnlyTheLast() async throws {
        let gate = MockGate()
        let server = try await MockServer.start(
            script: try Self.responding { $0.holdBeforeSetEnvironment = (1, gate) })
        let session = try await Self.session(to: server)
        let model = await Self.model(session)
        let before = await Self.kinds(server).count

        model.setEnvironment(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        let first = await Wait.until { await Self.sent(server).count == 1 }
        XCTAssertTrue(first)
        model.setEnvironment(.layoutDirection, to: .layoutDirection(.rightToLeft))
        model.setEnvironment(.contentSizeCategory, to: .contentSizeCategory(.extraLarge))
        model.setEnvironment(.userInterfaceStyle, to: .userInterfaceStyle(.light))
        let latest = Traits(
            userInterfaceStyle: .light, contentSizeCategory: .extraLarge, layoutDirection: .rightToLeft)
        XCTAssertEqual(model.environment.controls?.shown, latest)
        try await Task.sleep(for: .milliseconds(100))
        let held = await Self.sent(server).count
        XCTAssertEqual(held, 1, "nothing more while one is on its way")

        await gate.open()
        let isSettled = await Self.settled(model)
        XCTAssertTrue(isSettled)
        let sent = await Self.sent(server)
        XCTAssertEqual(sent, [Traits(userInterfaceStyle: .dark), latest])
        let trees = await Self.kinds(server).dropFirst(before).filter { $0 == .getHierarchy }.count
        XCTAssertEqual(trees, 1, "one refresh, after the last")
        XCTAssertEqual(model.environment.controls?.environment.overrides, latest)
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ENV_02_resetSendsEverythingUnspecified() async throws {
        let server = try await MockServer.start(script: try Self.responding())
        let session = try await Self.session(to: server)
        let model = await Self.model(session)

        model.setEnvironment(.layoutDirection, to: .layoutDirection(.rightToLeft))
        var isSettled = await Self.settled(model)
        XCTAssertTrue(isSettled)
        model.resetEnvironment()
        isSettled = await Self.settled(model)
        XCTAssertTrue(isSettled)

        let sent = await Self.sent(server)
        XCTAssertEqual(sent, [Traits(layoutDirection: .rightToLeft), .unspecified])
        XCTAssertEqual(model.environment.controls?.isOverriding, false)
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ENV_02_notSupportedPutsTheControlsBack() async throws {
        let all = Environment(overrides: .unspecified, current: Self.iPhone.own, overridable: TraitKind.allCases)
        var steps = try MockScript.fixtures("handshake").steps
        steps += [.expect(.getEnvironment, as: 20), .send(Frame(requestID: 20, body: .environment(all)))]
        steps += try MockScript.fixtures("hierarchy").steps
        steps += [
            .expect(.setEnvironment, as: 21),
            .send(Frame(requestID: 21, body: .error(ServerError(code: .notSupported, message: "no")))),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.enter()
        let ready = await Wait.until { await MainActor.run { model.environment.controls != nil } }
        XCTAssertTrue(ready)

        model.setEnvironment(.layoutDirection, to: .layoutDirection(.rightToLeft))
        let failed = await Wait.until {
            await MainActor.run { model.environment.controls?.failure != nil }
        }
        XCTAssertTrue(failed)
        let controls = try XCTUnwrap(model.environment.controls)
        XCTAssertEqual(controls.failure, .notSupported)
        XCTAssertEqual(controls.shown, .unspecified, "back to what the app has")
        XCTAssertFalse(controls.isSending)
        try await Task.sleep(for: .milliseconds(100))
        let kinds = await Self.kinds(server)
        let set = try XCTUnwrap(kinds.firstIndex(of: .setEnvironment))
        XCTAssertFalse(kinds[set...].contains(.getHierarchy), "nothing changed, nothing is taken again")

        // The next change clears it.
        model.dismissEnvironmentFailure()
        XCTAssertNil(model.environment.controls?.failure)
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ENV_02_appNotActivePutsTheControlsBack() async throws {
        let server = try await MockServer.start(
            script: try Self.responding { $0.failSetEnvironment = (1, .appNotActive) })
        let session = try await Self.session(to: server)
        let model = await Self.model(session)

        model.setEnvironment(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        let failed = await Wait.until {
            await MainActor.run { model.environment.controls?.failure != nil }
        }
        XCTAssertTrue(failed)
        XCTAssertEqual(model.environment.controls?.failure, .appNotActive)
        XCTAssertEqual(model.environment.controls?.shown, .unspecified)
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ENV_02_screenshotsAreCancelledBeforeTheChange() async throws {
        let gate = MockGate()
        let environment = Self.iPhone.answer
        var steps = try MockScript.fixtures("handshake").steps
        steps += [
            .expect(.getEnvironment, as: 20), .send(Frame(requestID: 20, body: .environment(environment))),
        ]
        steps += try MockScript.fixtures("hierarchy").steps
        steps += [
            .expect(.getLayerDetails, as: 50),
            .expect(.getLayerDetails, as: 52),
            .hold(gate),
            .expect(.cancel, as: 51),
            .expect(.cancel, as: 53),
            .send(Frame(requestID: 50, body: .streamEnd(StreamEnd(status: .cancelled, chunkCount: 0, error: nil)))),
            .send(Frame(requestID: 52, body: .streamEnd(StreamEnd(status: .cancelled, chunkCount: 0, error: nil)))),
            .expect(.setEnvironment, as: 30),
        ]
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = InspectionStore(session: session, newLayers: .expanded)
        model.screenshotBatchSize = 4
        model.rowsWait = .zero
        model.enter()
        let both = await Wait.until {
            await Self.kinds(server).filter { $0 == .getLayerDetails }.count == 2
        }
        XCTAssertTrue(both)

        model.setEnvironment(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        await gate.open()
        let changed = await Wait.until { await Self.kinds(server).contains(.setEnvironment) }
        XCTAssertTrue(changed)
        let kinds = await Self.kinds(server)
        XCTAssertEqual(
            Array(kinds.suffix(3)), [.cancel, .cancel, .setEnvironment], "both Cancels go out first")
        let mismatches = await server.mismatches
        XCTAssertEqual(mismatches, [])
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ENV_02_theSelectionAndModeStayAfterTheRefresh() async throws {
        let server = try await MockServer.start(script: try Self.responding())
        let session = try await Self.session(to: server)
        let model = await Self.model(session)
        model.select(3)
        model.setPreviewMode(.threeD)
        let cameras = model.cameras

        model.setEnvironment(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        let refreshed = await Wait.until { await Self.kinds(server).filter { $0 == .getHierarchy }.count == 2 }
        XCTAssertTrue(refreshed)
        let isSettled = await Self.settled(model)
        XCTAssertTrue(isSettled)
        XCTAssertEqual(model.selectedLayerID, 3)
        XCTAssertEqual(model.previewMode, .threeD)
        XCTAssertEqual(model.cameras, cameras)
        await session.close()
        await server.stop()
    }

    // MARK: - C-ENV-03

    @MainActor
    func test_C_ENV_03_theEnvironmentIsAskedBeforeTheHierarchy() async throws {
        let server = try await MockServer.start(script: try Self.responding())
        let session = try await Self.session(to: server)
        let model = await Self.model(session)

        let kinds = await Self.kinds(server)
        XCTAssertEqual(Array(kinds.prefix(3)), [.hello, .getEnvironment, .getHierarchy])
        XCTAssertEqual(kinds.filter { $0 == .getEnvironment }.count, 1)
        model.refresh()
        let refreshed = await Wait.until { await Self.kinds(server).filter { $0 == .getHierarchy }.count == 2 }
        XCTAssertTrue(refreshed)
        let after = await Self.kinds(server)
        XCTAssertEqual(after.filter { $0 == .getEnvironment }.count, 1, "⌘R does not ask again")
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ENV_03_aFailedGetEnvironmentStillLoadsTheTree() async throws {
        var steps = try MockScript.fixtures("handshake").steps
        steps += [
            .expect(.getEnvironment, as: 20),
            .send(Frame(requestID: 20, body: .error(ServerError(code: .internalError, message: nil)))),
        ]
        steps += try MockScript.fixtures("hierarchy").steps
        let server = try await MockServer.start(script: MockScript(steps: steps))
        let session = try await Self.session(to: server)
        let model = await Self.model(session)

        XCTAssertEqual(model.environment, .unavailable)
        XCTAssertFalse(model.tree.isEmpty)
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ENV_03_aLostConnectionShowsTheAppsOwn() async throws {
        let server = try await MockServer.start(script: try Self.responding())
        let session = try await Self.session(to: server)
        let model = await Self.model(session)
        model.setEnvironment(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        let isSettled = await Self.settled(model)
        XCTAssertTrue(isSettled)

        model.connectionLost()
        XCTAssertEqual(model.environment, .lost)
        XCTAssertFalse(model.canChangeEnvironment)
        model.toggleAppearance()
        await session.close()
        await server.stop()
    }

    @MainActor
    func test_C_ENV_03_aNewConnectionSendsNoSetEnvironment() async throws {
        let server = try await MockServer.start(script: try Self.responding())
        let first = try await Self.session(to: server)
        let old = await Self.model(first)
        old.setEnvironment(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        let isSettled = await Self.settled(old)
        XCTAssertTrue(isSettled)
        old.connectionLost()
        old.leave()
        await first.close()

        // The window that waited for the app takes a new inspection (C-WIN-04); the server put
        // the app's own traits back (P-ENV-03).
        let second = try await Self.session(to: server)
        let new = await Self.model(second)
        let sent = await Self.sent(server)
        XCTAssertEqual(sent.count, 1, "only the old connection's change")
        XCTAssertEqual(new.environment.controls?.shown, .unspecified)
        XCTAssertEqual(new.environment.controls?.environment.current, Self.iPhone.own)
        await second.close()
        await server.stop()
    }

    @MainActor
    func test_C_ENV_03_closingTheInspectionSendsNothing() async throws {
        let server = try await MockServer.start(script: try Self.responding())
        let session = try await Self.session(to: server)
        let model = await Self.model(session)
        model.setEnvironment(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        let isSettled = await Self.settled(model)
        XCTAssertTrue(isSettled)
        let before = await Self.sent(server).count

        model.leave()
        try await Task.sleep(for: .milliseconds(100))
        let after = await Self.kinds(server)
        let sent = await Self.sent(server).count
        XCTAssertEqual(sent, before)
        XCTAssertNotEqual(after.last, .getEnvironment)
        await session.close()
        await server.stop()
    }
}
