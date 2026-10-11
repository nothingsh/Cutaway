import CutawayModel
import CutawayScene
import CutawayTestSupport
import CutawayTransport
import CutawayWire
import XCTest

@testable import CutawayUI

/// What the preview shows, worked out without a preview: the still picture, the turn to
/// another mode (C-PREV-11), the change of the expansion (C-PREV-12), and new images that
/// wait for their showing (C-SCALE-02).
final class PreviewProjectorTests: XCTestCase {
    private static let client = ClientInfo(name: "Cutaway", version: "0.1.0")
    private static let viewport = Viewport(width: 480, height: 900)

    /// What the projector sent on.
    @MainActor
    private final class Log {
        var shown: [(list: DrawList, isInTransition: Bool)] = []
        var kept: [Set<TextureKey>] = []
    }

    /// A model with the `hierarchy` fixture.
    @MainActor
    private func model() throws -> InspectionStore {
        let model = InspectionStore(
            session: Session(channel: InertChannel(), client: Self.client), newLayers: .expanded)
        model.apply(try Fixtures.hierarchy())
        return model
    }

    /// A projector that starts where the model is, as the preview's controller sets it up.
    @MainActor
    private func projector(
        _ model: InspectionStore, clock: ManualClock?, reducesMotion: Bool = false,
        log: Log
    ) -> PreviewProjector {
        let projector = PreviewProjector(
            clock: clock, reducesMotion: { reducesMotion },
            keepTextures: { log.kept.append($0) },
            show: { log.shown.append(($0, $1)) })
        projector.resize(to: CGSize(width: Self.viewport.width, height: Self.viewport.height))
        projector.follow(model.layout)
        projector.follow(model.previewMode)
        projector.follow(model.cameras)
        projector.followsChanges = true
        return projector
    }

    /// The still picture of the model's state.
    @MainActor
    private func still(_ model: InspectionStore) -> DrawList {
        model.layout.project(
            camera: model.camera, viewport: Self.viewport, selected: model.selectedLayerID,
            hovered: model.hoveredLayerID)
    }

    // MARK: - C-PREV-11

    @MainActor
    func test_C_PREV_11_aNewModeTurnsOverAndEndsOnItsCamera() throws {
        let model = try model()
        let clock = ManualClock()
        let log = Log()
        let projector = projector(model, clock: clock, log: log)
        XCTAssertEqual(log.shown.last?.list, still(model))
        XCTAssertFalse(clock.isRunning)

        model.setPreviewMode(.threeD)
        projector.follow(model.previewMode)
        XCTAssertTrue(projector.isInTransition)
        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(log.shown.last?.isInTransition, true)
        XCTAssertNotEqual(log.shown.last?.list, still(model))

        clock.advance(by: PreviewMotion.duration / 2)
        XCTAssertTrue(projector.isInTransition)
        clock.advance(by: PreviewMotion.duration)
        XCTAssertFalse(projector.isInTransition)
        XCTAssertFalse(clock.isRunning, "nothing more is drawn")
        XCTAssertEqual(log.shown.last?.isInTransition, false)
        XCTAssertEqual(log.shown.last?.list, still(model))
    }

    @MainActor
    func test_C_PREV_11_newCamerasOnTheWayEndTheTurn() throws {
        let model = try model()
        let clock = ManualClock()
        let log = Log()
        let projector = projector(model, clock: clock, log: log)
        model.setPreviewMode(.threeD)
        projector.follow(model.previewMode)
        XCTAssertTrue(projector.isInTransition)

        model.rotate(byDragOf: 30, 0)
        projector.follow(model.cameras)
        XCTAssertFalse(projector.isInTransition)
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(log.shown.last?.isInTransition, false)
        XCTAssertEqual(log.shown.last?.list, still(model))
    }

    @MainActor
    func test_C_PREV_11_withoutMotionOrBeforeFollowingChangesTheModeShowsAtOnce() throws {
        let model = try model()
        let clock = ManualClock()
        let log = Log()
        let reduced = projector(model, clock: clock, reducesMotion: true, log: log)
        model.setPreviewMode(.threeD)
        reduced.follow(model.previewMode)
        XCTAssertFalse(reduced.isInTransition)
        XCTAssertEqual(log.shown.last?.list, still(model))

        let instant = projector(model, clock: nil, log: log)
        model.setPreviewMode(.twoD)
        instant.follow(model.previewMode)
        XCTAssertFalse(instant.isInTransition)
        XCTAssertEqual(log.shown.last?.list, still(model))
        XCTAssertFalse(clock.isRunning)
    }

    @MainActor
    func test_C_PREV_11_endingTheTransitionsShowsTheStillPictureAndStopsTheClock() throws {
        let model = try model()
        let clock = ManualClock()
        let log = Log()
        let projector = projector(model, clock: clock, log: log)
        model.setPreviewMode(.threeD)
        projector.follow(model.previewMode)
        XCTAssertTrue(clock.isRunning)

        projector.endTransitions()
        XCTAssertFalse(projector.isInTransition)
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(log.shown.last?.list, still(model))
    }

    // MARK: - C-PREV-12

    @MainActor
    func test_C_PREV_12_aNewExpansionGoesOverAndKeepsTheTexturesOfBothEndsUntilItEnds() throws {
        let model = try model()
        let clock = ManualClock()
        let log = Log()
        let projector = projector(model, clock: clock, log: log)
        XCTAssertEqual(log.kept.last, model.layout.drawnTextures)

        model.setExpanded(2, false)
        projector.follow(model.layout)
        XCTAssertTrue(projector.isInTransition)
        let kept = log.kept.count
        clock.advance(by: PreviewMotion.duration / 2)
        XCTAssertEqual(log.kept.count, kept, "not for every frame")

        clock.advance(by: PreviewMotion.duration)
        XCTAssertFalse(projector.isInTransition)
        XCTAssertEqual(log.kept.count, kept + 1)
        XCTAssertEqual(log.kept.last, model.layout.drawnTextures)
        XCTAssertEqual(log.shown.last?.list, still(model))
    }

    // MARK: - C-PREV-01, C-PREV-03, C-PREV-10

    @MainActor
    func test_C_PREV_03_aNewHoverOrSelectionIsShownWithoutProjectingAgain() throws {
        let model = try model()
        let log = Log()
        let projector = projector(model, clock: nil, log: log)
        let projections = projector.projectionCount
        for id: UInt64? in [3, 8, nil, 4] {
            model.hover(id)
            projector.hovered = model.hoveredLayerID
            projector.project()
            XCTAssertEqual(log.shown.last?.list, still(model), "hovering \(String(describing: id))")
        }
        model.select(8)
        projector.selected = model.selectedLayerID
        projector.project()
        XCTAssertEqual(log.shown.last?.list, still(model), "selecting")
        XCTAssertEqual(projector.projectionCount, projections, "only the highlights changed")

        // Anything else projects again, and the next hover starts from that.
        model.pan(by: 10, 5)
        projector.follow(model.cameras)
        XCTAssertEqual(projector.projectionCount, projections + 1)
        model.hover(3)
        projector.hovered = model.hoveredLayerID
        projector.project()
        XCTAssertEqual(projector.projectionCount, projections + 1)
        XCTAssertEqual(log.shown.last?.list, still(model), "after the camera moved")
    }

    @MainActor
    func test_C_PREV_01_aNewSelectionWithOtherMarksIsProjected() throws {
        let model = try model()
        let log = Log()
        let projector = projector(model, clock: nil, log: log)
        let projections = projector.projectionCount
        projector.selected = 3
        projector.constraintEnds = [ConstraintEnd(mark: .layer(8))]
        projector.project()
        XCTAssertEqual(projector.projectionCount, projections + 1)
        XCTAssertEqual(
            log.shown.last?.list,
            model.layout.project(
                camera: model.camera, viewport: Self.viewport, selected: 3, hovered: nil,
                marks: [.layer(8)]))
    }

    @MainActor
    func test_C_PREV_10_whileMeasuringEachNewHoverIsProjectedWithItsMeasurement() throws {
        let model = try model()
        let log = Log()
        let projector = projector(model, clock: nil, log: log)
        model.select(3)
        projector.selected = 3
        projector.measuring = true
        projector.project()
        let projections = projector.projectionCount
        for (index, id) in [UInt64?.some(8), 2, nil].enumerated() {
            projector.hovered = id
            projector.project()
            XCTAssertEqual(projector.projectionCount, projections + index + 1)
            XCTAssertEqual(
                log.shown.last?.list,
                model.layout.project(
                    camera: model.camera, viewport: Self.viewport, selected: 3, hovered: id,
                    measuring: id),
                "hovering \(String(describing: id))")
        }
        XCTAssertNotNil(
            model.layout.project(
                camera: model.camera, viewport: Self.viewport, selected: 3, hovered: 8,
                measuring: 8).measurement, "the hover is measured")
    }

    // MARK: - C-SCALE-02

    @MainActor
    func test_C_SCALE_02_newImagesSoonAfterOthersWaitAndAProjectionShowsThem() async throws {
        let model = try model()
        let log = Log()
        let projector = projector(model, clock: nil, log: log)
        projector.imagesInterval = .seconds(10)
        let details = try Fixtures.layerDetails(scenario: "layer-details")
        let three = try XCTUnwrap(details.first { $0.layerID == 3 })
        let four = try XCTUnwrap(details.first { $0.layerID == 4 })
        func drawnTexture(_ id: UInt64) -> TextureKey? {
            log.shown.last?.list.items.first { $0.layerID == id }?.texture
        }

        // The first images after a quiet spell show at once.
        await model.applyDetails([three])
        projector.follow(model.layout)
        XCTAssertNotNil(drawnTexture(3))
        let kept = log.kept.count
        let shown = log.shown.count

        // The next, soon after, wait.
        await model.applyDetails([four])
        projector.follow(model.layout)
        XCTAssertEqual(log.shown.count, shown, "shown within the interval")
        XCTAssertEqual(log.kept.count, kept)

        // Any projection shows them, with their textures.
        projector.project()
        XCTAssertNotNil(drawnTexture(4))
        XCTAssertEqual(log.kept.count, kept + 1)
        XCTAssertEqual(log.kept.last, model.layout.drawnTextures)
    }
}
