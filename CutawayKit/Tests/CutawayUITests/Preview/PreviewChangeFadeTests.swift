import CutawayModel
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// What the last refresh changed fades out of the preview on the transitions' clock, without
/// projecting again, and then the clock stops (C-REND-12).
final class PreviewChangeFadeTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")
    private static let viewport = Viewport(width: 480, height: 900)
    private static let diff = RefreshDiff(added: [4], changed: [3, 7], removed: 1, generation: 1)

    @MainActor
    private final class Log {
        var shown: [DrawList] = []
    }

    @MainActor
    private func projector(
        clock: ManualClock?, reducesMotion: Bool = false, log: Log
    ) throws -> PreviewProjector {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        let projector = PreviewProjector(
            clock: clock, reducesMotion: { reducesMotion }, keepTextures: { _ in },
            show: { list, _ in log.shown.append(list) })
        projector.resize(to: Self.viewport)
        projector.follow(model.layout)
        projector.follow(model.previewMode)
        projector.follow(model.cameras)
        projector.followsChanges = true
        return projector
    }

    private func marks(_ list: DrawList?) -> [UInt64: ChangeMark] {
        Dictionary(uniqueKeysWithValues: (list?.items ?? []).compactMap { item in
            item.change.map { (item.layerID, $0) }
        })
    }

    @MainActor
    func test_C_REND_12_theMarksFadeOnTheClockWithoutProjectingAgainThenTheClockStops() throws {
        let clock = ManualClock()
        let log = Log()
        let projector = try projector(clock: clock, log: log)
        projector.follow(Self.diff)
        XCTAssertEqual(marks(log.shown.last), [4: .added, 3: .changed, 7: .changed])
        XCTAssertEqual(log.shown.last?.changeStrength, 1)
        XCTAssertTrue(clock.isRunning)
        XCTAssertFalse(projector.isInTransition, "a fade holds nothing back")

        let projections = projector.projectionCount
        clock.advance(by: projector.changeFade / 2)
        XCTAssertEqual(try XCTUnwrap(log.shown.last?.changeStrength), 0.5, accuracy: 0.01)
        XCTAssertEqual(projector.projectionCount, projections, "only the strength changed")

        clock.advance(by: projector.changeFade)
        XCTAssertEqual(log.shown.last?.changeStrength, 0)
        XCTAssertEqual(marks(log.shown.last), [:])
        XCTAssertFalse(clock.isRunning)
        let frames = log.shown.count
        clock.advance(by: 1)
        XCTAssertEqual(log.shown.count, frames, "nothing more is drawn")
    }

    @MainActor
    func test_C_REND_12_aNewRefreshStartsTheMarksOver() throws {
        let clock = ManualClock()
        let log = Log()
        let projector = try projector(clock: clock, log: log)
        projector.follow(Self.diff)
        clock.advance(by: projector.changeFade * 0.8)
        projector.follow(RefreshDiff(added: [], changed: [8], removed: 0, generation: 2))
        XCTAssertEqual(marks(log.shown.last), [8: .changed])
        XCTAssertEqual(log.shown.last?.changeStrength, 1)

        // Nothing changed this time: the marks go.
        projector.follow(nil)
        XCTAssertEqual(marks(log.shown.last), [:])
    }

    @MainActor
    func test_C_REND_12_withReduceMotionTheMarksStayThenGoAtOnce() async throws {
        let clock = ManualClock()
        let log = Log()
        let projector = try projector(clock: clock, reducesMotion: true, log: log)
        projector.changeFade = 0.05
        projector.follow(Self.diff)
        XCTAssertEqual(log.shown.last?.changeStrength, 1)
        XCTAssertFalse(clock.isRunning, "no frames while the marks stay")
        let gone = await Wait.untilOnMain(within: .seconds(2)) { self.marks(log.shown.last).isEmpty }
        XCTAssertTrue(gone)
    }
}
