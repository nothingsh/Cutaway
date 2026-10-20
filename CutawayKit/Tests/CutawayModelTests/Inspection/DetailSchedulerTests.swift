import CutawayScene
import XCTest
@testable import CutawayModel

/// Which layers' screenshots to ask for, in what order, and how far loading got (C-DET-01,
/// C-DET-02, C-DET-03).
final class DetailSchedulerTests: XCTestCase {
    private func solo(_ id: UInt64) -> TextureNeed { TextureNeed(layerID: id, kind: .solo) }
    private func group(_ id: UInt64) -> TextureNeed { TextureNeed(layerID: id, kind: .group) }

    /// The `hierarchy` fixture, fully expanded (SceneLayoutTests).
    private var fixtureNeeds: [TextureNeed] {
        [solo(1), solo(2), group(3), solo(4), solo(6), group(7), group(8)]
    }

    private func scheduler(_ needs: [TextureNeed]) -> DetailScheduler {
        var scheduler = DetailScheduler()
        scheduler.startRound()
        scheduler.setNeeds(needs)
        return scheduler
    }

    // MARK: - C-DET-01

    func test_C_DET_01_theFirstBatchAsksForWhatIsNeededInTreeOrder() {
        var scheduler = scheduler(fixtureNeeds)
        XCTAssertEqual(scheduler.nextBatch()?.needs, fixtureNeeds)
        XCTAssertEqual(scheduler.progress, DetailProgress(completed: 0, total: 7))
    }

    func test_C_DET_01_rowsInViewComeFirst() {
        var scheduler = scheduler(fixtureNeeds)
        // 5 is in view but hidden: it needs nothing, and is skipped.
        scheduler.setVisible([7, 5, 8])
        XCTAssertEqual(
            scheduler.nextBatch()?.needs,
            [group(7), group(8), solo(1), solo(2), group(3), solo(4), solo(6)])
    }

    private static let size = DetailScheduler.defaultBatchSize

    /// The layers from `first`, `count` of them.
    private func ids(_ first: Int, _ count: Int) -> [UInt64] {
        (first..<first + count).map(UInt64.init)
    }

    func test_C_DET_01_aBatchHoldsAtMostThirtyTwoLayers() throws {
        XCTAssertEqual(Self.size, 32, "C-SCALE-04")
        let needs = (UInt64(1)...80).map { group($0) }
        var scheduler = scheduler(needs)
        let first = scheduler.nextBatch()
        XCTAssertEqual(first?.needs, Array(needs[0..<32]))
        XCTAssertEqual(scheduler.nextBatch()?.needs, Array(needs[32..<64]), "the second asks for others")
        XCTAssertNil(scheduler.nextBatch(), "two batches at a time (C-SCALE-04)")

        scheduler.batchEnded(try XCTUnwrap(first).id, completed: false)
        // Nothing of it arrived and it was not completed: the same ones are due again.
        XCTAssertEqual(scheduler.nextBatch()?.needs, Array(needs[0..<32]))
    }

    // MARK: - C-SCALE-04

    func test_C_SCALE_04_twoBatchesUnderWayNeverAskForTheSameLayer() throws {
        let needs = (UInt64(1)...80).map { group($0) }
        var scheduler = scheduler(needs)
        // 40 is in view: the first batch takes it, the second does not again.
        scheduler.setVisible([40])
        let first = try XCTUnwrap(scheduler.nextBatch())
        let second = try XCTUnwrap(scheduler.nextBatch())
        XCTAssertEqual(first.needs.map(\.layerID), [40] + ids(1, 31))
        XCTAssertEqual(second.needs.map(\.layerID), ids(32, 8) + ids(41, 24))
        XCTAssertNotEqual(first.id, second.id)
    }

    func test_C_SCALE_04_aBatchEndsOnItsOwn() throws {
        let needs = (UInt64(1)...100).map { group($0) }
        var scheduler = scheduler(needs)
        let first = try XCTUnwrap(scheduler.nextBatch())
        let second = try XCTUnwrap(scheduler.nextBatch())
        // An answer is the batch's that asked for the layer.
        scheduler.answered(40)
        XCTAssertEqual(scheduler.progress, DetailProgress(completed: 1, total: 100), "40's kind did not come")
        // The second ends first: completed, what it did not get failed; the first goes on.
        scheduler.batchEnded(second.id, completed: true)
        XCTAssertEqual(scheduler.progress, DetailProgress(completed: 32, total: 100))
        let third = try XCTUnwrap(scheduler.nextBatch(), "room for one more")
        XCTAssertEqual(third.needs.map(\.layerID), ids(65, 32))
        XCTAssertNil(scheduler.nextBatch())
        scheduler.batchEnded(first.id, completed: false)
        XCTAssertEqual(scheduler.nextBatch()?.needs.map(\.layerID), ids(1, 32), "due again")
    }

    func test_C_SCALE_04_aNewRoundDropsBothBatches() {
        let needs = (UInt64(1)...100).map { group($0) }
        var scheduler = scheduler(needs)
        _ = scheduler.nextBatch()
        _ = scheduler.nextBatch()
        XCTAssertNil(scheduler.nextBatch())
        scheduler.startRound()
        XCTAssertEqual(scheduler.nextBatch()?.needs.map(\.layerID), ids(1, 32))
        XCTAssertEqual(scheduler.nextBatch()?.needs.map(\.layerID), ids(33, 32))
    }

    func test_C_DET_01_whatArrivedIsNotAskedForAgain() throws {
        var scheduler = scheduler(fixtureNeeds)
        let batch = try XCTUnwrap(scheduler.nextBatch())
        scheduler.received(.group, for: 3)
        scheduler.received(.solo, for: 4)
        scheduler.received(.group, for: 4)  // not needed, still recorded
        XCTAssertEqual(scheduler.progress, DetailProgress(completed: 2, total: 7))
        scheduler.batchEnded(batch.id, completed: false)
        XCTAssertEqual(
            scheduler.nextBatch()?.needs, [solo(1), solo(2), solo(6), group(7), group(8)])
    }

    func test_C_DET_01_collapsingChangesWhatIsNeeded() throws {
        var scheduler = scheduler(fixtureNeeds)
        let batch = try XCTUnwrap(scheduler.nextBatch())
        for need in fixtureNeeds { scheduler.received(need.kind, for: need.layerID) }
        scheduler.batchEnded(batch.id, completed: true)
        XCTAssertEqual(scheduler.progress, DetailProgress(completed: 7, total: 7))
        XCTAssertNil(scheduler.nextBatch())

        // Layer 2 collapsed: it now needs its group; its subtree needs nothing.
        scheduler.setNeeds([solo(1), group(2)])
        XCTAssertEqual(scheduler.progress, DetailProgress(completed: 1, total: 2))
        XCTAssertEqual(scheduler.nextBatch()?.needs, [group(2)])
    }

    func test_C_DET_01_aKindThatIsNoLongerNeededDoesNotFailTheLayer() throws {
        var scheduler = scheduler(fixtureNeeds)
        let batch = try XCTUnwrap(scheduler.nextBatch())
        // Layer 4 is collapsed while its solo is on the way, and the solo does not come.
        scheduler.setNeeds([solo(1), solo(2), group(3), group(4), solo(6), group(7), group(8)])
        scheduler.answered(4)
        scheduler.batchEnded(batch.id, completed: true)
        XCTAssertEqual(scheduler.nextBatch()?.needs, [group(4)])
    }

    // MARK: - C-DET-02: rounds and progress

    func test_C_DET_02_aNewRoundAsksForEverythingAgain() throws {
        var scheduler = scheduler(fixtureNeeds)
        let batch = try XCTUnwrap(scheduler.nextBatch())
        for need in fixtureNeeds { scheduler.received(need.kind, for: need.layerID) }
        scheduler.batchEnded(batch.id, completed: true)
        XCTAssertNil(scheduler.nextBatch())

        scheduler.startRound()
        XCTAssertEqual(scheduler.progress, DetailProgress(completed: 0, total: 7))
        XCTAssertEqual(scheduler.nextBatch()?.needs, fixtureNeeds)
    }

    func test_C_DET_02_aNewRoundDropsTheBatchUnderWay() throws {
        var scheduler = scheduler(fixtureNeeds)
        let old = try XCTUnwrap(scheduler.nextBatch())
        scheduler.startRound()
        let new = try XCTUnwrap(scheduler.nextBatch(), "the old batch no longer blocks")
        XCTAssertNotEqual(new.id, old.id)

        // The old batch ending changes nothing about the new one.
        scheduler.batchEnded(old.id, completed: true)
        XCTAssertNil(scheduler.nextBatch(), "the new batch is still under way")
        XCTAssertEqual(scheduler.progress, DetailProgress(completed: 0, total: 7))
    }

    func test_C_DET_02_withNothingNeededThereIsNothingToShow() {
        var scheduler = DetailScheduler()
        XCTAssertEqual(scheduler.progress, .none)
        XCTAssertNil(scheduler.nextBatch())
    }

    // MARK: - C-DET-03: failures

    func test_C_DET_03_aLayerThatFailsIsSettledAndNotAskedAgain() throws {
        var scheduler = scheduler(fixtureNeeds)
        let batch = try XCTUnwrap(scheduler.nextBatch())
        scheduler.failed(3)  // LayerNotFound or CaptureFailed
        scheduler.batchEnded(batch.id, completed: false)
        XCTAssertEqual(scheduler.progress, DetailProgress(completed: 1, total: 7))
        XCTAssertFalse(try XCTUnwrap(scheduler.nextBatch()).needs.contains(group(3)))
    }

    func test_C_DET_03_anAnswerWithoutTheNeededKindFailsThatKind() throws {
        var scheduler = scheduler(fixtureNeeds)
        let batch = try XCTUnwrap(scheduler.nextBatch())
        scheduler.received(.group, for: 2)  // asked for the solo, got the group
        scheduler.answered(2)
        XCTAssertEqual(scheduler.progress, DetailProgress(completed: 1, total: 7))
        scheduler.batchEnded(batch.id, completed: false)
        XCTAssertFalse(try XCTUnwrap(scheduler.nextBatch()).needs.contains(solo(2)))
    }

    func test_C_DET_03_aCompletedBatchSettlesWhatItLeftOut() throws {
        var scheduler = scheduler(fixtureNeeds)
        let batch = try XCTUnwrap(scheduler.nextBatch())
        scheduler.received(.group, for: 3)
        scheduler.batchEnded(batch.id, completed: true)
        XCTAssertEqual(scheduler.progress, DetailProgress(completed: 7, total: 7))
        XCTAssertNil(scheduler.nextBatch())
    }

    func test_C_DET_03_aFailedKindLeavesTheOtherKindDue() throws {
        var scheduler = scheduler(fixtureNeeds)
        let batch = try XCTUnwrap(scheduler.nextBatch())
        scheduler.answered(2)  // no solo for 2
        scheduler.failed(6)  // capture failed: both kinds
        scheduler.batchEnded(batch.id, completed: true)

        scheduler.setNeeds([solo(1), group(2), group(3), solo(4), group(6), group(7), group(8)])
        XCTAssertEqual(scheduler.nextBatch()?.needs, [group(2)])
    }

    func test_C_DET_02_aNewRoundForgetsEarlierRounds() {
        var scheduler = scheduler([solo(1), group(2)])
        _ = scheduler.nextBatch()
        scheduler.received(.solo, for: 1)
        scheduler.failed(2)
        XCTAssertEqual(scheduler.recordCount, 3, "one arrival, two kinds failed")

        scheduler.startRound()
        XCTAssertEqual(scheduler.recordCount, 0)
        XCTAssertEqual(scheduler.progress, DetailProgress(completed: 0, total: 2))
    }

    // MARK: - C-DET-07

    func test_C_DET_07_invalidatedNeedsAreDueAgainInTheSameRound() throws {
        var scheduler = scheduler(fixtureNeeds)
        let batch = try XCTUnwrap(scheduler.nextBatch())
        for need in fixtureNeeds { scheduler.received(need.kind, for: need.layerID) }
        scheduler.batchEnded(batch.id, completed: true)
        XCTAssertNil(scheduler.nextBatch())
        XCTAssertEqual(scheduler.progress, DetailProgress(completed: 7, total: 7))

        // Layer 4's subtree and its ancestors' group images (C-DET-07). Layer 5 needs
        // nothing, and the ancestors are expanded: only layer 4's solo is due.
        scheduler.invalidate([solo(4), group(4), solo(5), group(5), group(2), group(1)])
        XCTAssertEqual(scheduler.progress, DetailProgress(completed: 6, total: 7))
        XCTAssertEqual(scheduler.nextBatch()?.needs, [solo(4)])
    }

    func test_C_DET_07_aFailureIsForgottenToo() throws {
        var scheduler = scheduler(fixtureNeeds)
        let batch = try XCTUnwrap(scheduler.nextBatch())
        for need in fixtureNeeds { scheduler.received(need.kind, for: need.layerID) }
        scheduler.failed(3)
        scheduler.batchEnded(batch.id, completed: true)
        XCTAssertNil(scheduler.nextBatch())
        scheduler.invalidate([group(3)])
        XCTAssertEqual(scheduler.nextBatch()?.needs, [group(3)])
    }

    func test_C_DET_07_anInvalidatedGroupIsAskedForOnceTheLayerIsCollapsed() throws {
        var scheduler = scheduler(fixtureNeeds)
        let batch = try XCTUnwrap(scheduler.nextBatch())
        for need in fixtureNeeds { scheduler.received(need.kind, for: need.layerID) }
        // Layer 2's group arrived too, asked for in an earlier collapse.
        scheduler.received(.group, for: 2)
        scheduler.batchEnded(batch.id, completed: true)

        scheduler.invalidate([group(2)])
        XCTAssertNil(scheduler.nextBatch(), "layer 2 is expanded: its solo is drawn")
        // Collapsing layer 2 draws its group.
        scheduler.setNeeds([solo(1), group(2)])
        XCTAssertEqual(scheduler.nextBatch()?.needs, [group(2)])
    }

    func test_C_DET_07_invalidatingDuringABatchLeavesItsEndAlone() throws {
        var scheduler = scheduler(fixtureNeeds)
        let batch = try XCTUnwrap(scheduler.nextBatch())
        scheduler.invalidate([group(3)])
        XCTAssertNil(scheduler.nextBatch(), "one batch at a time")
        scheduler.received(.group, for: 3)
        scheduler.batchEnded(batch.id, completed: true)
        // What the batch brought counts; what it did not bring failed, as before.
        XCTAssertEqual(scheduler.progress, DetailProgress(completed: 7, total: 7))
    }
}
