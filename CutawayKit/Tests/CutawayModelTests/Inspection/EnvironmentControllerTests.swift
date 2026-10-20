import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayModel

/// C-ENV-02, C-ENV-03, C-MENU-05: what `EnvironmentController` decides without a connection.
@MainActor
final class EnvironmentControllerTests: XCTestCase {
    /// An app on protocol 1.2 that answers at once, as `MockEnvironment` says.
    private actor Source: InspectionSource {
        nonisolated var isLive: Bool { true }
        var negotiatedVersion: Version? { ProtocolVersion.current }
        var environment: MockEnvironment
        private(set) var sent: [Traits] = []
        /// Held answers, while `holds`.
        var holds = false
        private var held: [CheckedContinuation<Void, Never>] = []

        init(_ environment: MockEnvironment) {
            self.environment = environment
        }

        func hold() { holds = true }

        func release() {
            holds = false
            held.forEach { $0.resume() }
            held.removeAll()
        }

        func hierarchy() async throws -> Hierarchy { throw RequestError.unsupported }
        func subtree(of rootID: UInt64) async throws -> Hierarchy { throw RequestError.unsupported }
        func layerDetails(_ request: GetLayerDetails) async -> LayerDetailsStream {
            LayerDetailsStream(chunks: AsyncThrowingStream { $0.finish() }, cancelAction: {})
        }

        func setAttribute(_ request: SetAttribute) async throws -> SetAttributeResult {
            throw RequestError.unsupported
        }

        private(set) var asked = 0

        func environment() async throws -> Environment {
            asked += 1
            return environment.answer
        }

        func setEnvironment(_ overrides: Traits) async throws -> Environment {
            sent.append(overrides)
            if holds { await withCheckedContinuation { held.append($0) } }
            environment.overrides = overrides
            return environment.answer
        }
    }

    private final class Delegate: EnvironmentControllerDelegate {
        var mayChangeEnvironment = true
        var answers: [Bool] = []

        func environmentWillSend(_ controller: EnvironmentController) -> Task<Void, Never>? { nil }
        func environmentController(_ controller: EnvironmentController, didAnswer refresh: Bool) {
            answers.append(refresh)
        }

        func environmentStateChanged(_ controller: EnvironmentController) {}
    }

    private func loaded(
        _ environment: MockEnvironment = .iPhone()
    ) async -> (EnvironmentController, Source, Delegate) {
        let source = Source(environment)
        let delegate = Delegate()
        let controller = EnvironmentController(source: source, delegate: delegate)
        await controller.load()
        return (controller, source, delegate)
    }

    private func answered(_ delegate: Delegate, count: Int) async -> Bool {
        await Wait.until { await MainActor.run { delegate.answers.count == count } }
    }

    func test_C_ENV_02_nothingChangesWhileAnArchiveIsSaved() async {
        let (controller, source, delegate) = await loaded()
        delegate.mayChangeEnvironment = false

        XCTAssertFalse(controller.canChange)
        controller.set(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        controller.toggleAppearance()
        XCTAssertEqual(controller.state.controls?.shown, .unspecified)
        let sent = await source.sent
        XCTAssertEqual(sent, [])
    }

    func test_C_ENV_02_choosingWhatIsShownAgainSendsNothing() async {
        let (controller, source, _) = await loaded()
        controller.set(.layoutDirection, to: .layoutDirection(.unspecified))
        let sent = await source.sent
        XCTAssertEqual(sent, [])
    }

    func test_C_ENV_02_aWaitingChangeEqualToTheAnswerIsNotSent() async {
        let (controller, source, delegate) = await loaded()
        await source.hold()
        controller.set(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        let first = await Wait.until { await source.sent.count == 1 }
        XCTAssertTrue(first)
        // Changed and changed back while the first is on its way.
        controller.set(.userInterfaceStyle, to: .userInterfaceStyle(.light))
        controller.set(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        await source.release()

        let ended = await answered(delegate, count: 1)
        XCTAssertTrue(ended)
        let sent = await source.sent
        XCTAssertEqual(sent, [Traits(userInterfaceStyle: .dark)])
        XCTAssertEqual(delegate.answers, [true])
    }

    func test_C_MENU_05_toggleOverridesTheOppositeOfWhatTheAppShows() async {
        let (controller, source, delegate) = await loaded()
        controller.toggleAppearance()
        var ended = await answered(delegate, count: 1)
        XCTAssertTrue(ended)
        controller.toggleAppearance()
        ended = await answered(delegate, count: 2)
        XCTAssertTrue(ended)

        let sent = await source.sent
        XCTAssertEqual(sent, [Traits(userInterfaceStyle: .dark), Traits(userInterfaceStyle: .light)])
    }

    func test_C_MENU_05_toggleFromADarkAppOverridesLight() async {
        var environment = MockEnvironment.iPhone()
        environment.own.userInterfaceStyle = .dark
        let (controller, source, delegate) = await loaded(environment)
        controller.toggleAppearance()
        let ended = await answered(delegate, count: 1)
        XCTAssertTrue(ended)
        let sent = await source.sent
        XCTAssertEqual(sent, [Traits(userInterfaceStyle: .light)])
    }

    func test_C_MENU_05_toggleNeedsTheAppearance() async {
        let (controller, source, _) = await loaded(.iPhone(overridable: [.layoutDirection]))
        controller.toggleAppearance()
        let sent = await source.sent
        XCTAssertEqual(sent, [])
    }

    func test_C_ENV_03_anAnswerAfterTheConnectionWentChangesNothing() async {
        let (controller, source, delegate) = await loaded()
        await source.hold()
        controller.set(.userInterfaceStyle, to: .userInterfaceStyle(.dark))
        let first = await Wait.until { await source.sent.count == 1 }
        XCTAssertTrue(first)
        controller.connectionLost()
        await source.release()

        let ended = await answered(delegate, count: 1)
        XCTAssertTrue(ended)
        XCTAssertEqual(controller.state, .lost)
        XCTAssertEqual(delegate.answers, [false], "no refresh")
    }

    func test_C_ENV_03_theEnvironmentIsAskedOnlyOnce() async {
        let (controller, source, _) = await loaded()
        await controller.load()
        let asked = await source.asked
        XCTAssertEqual(asked, 1, "entering again does not ask again")
    }
}
