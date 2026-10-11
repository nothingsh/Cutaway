import CutawayScene
import CutawayTestSupport
import XCTest

@testable import CutawayModel

/// The scheduler counts what is settled and does not look again at needs it has passed,
/// so that taking in a chunk costs the same however many layers there are (C-SCALE-02). It
/// must ask for the same batches and report the same progress as the scheduler that counted
/// by looking at every need (`ReferenceScheduler`).
final class DetailSchedulerCountingTests: XCTestCase {
    func test_C_SCALE_02_theCountingSchedulerAsksAndReportsAsBefore() {
        for seed in UInt64(1)...40 {
            var random = SeededGenerator(seed: seed)
            var scheduler = DetailScheduler()
            var reference = ReferenceScheduler()
            let layers = UInt64(1)...UInt64(60)
            func someNeeds() -> [TextureNeed] {
                var needs = layers.shuffled(using: &random)
                    .prefix(Int.random(in: 0...60, using: &random))
                    .map { TextureNeed(layerID: $0, kind: Bool.random(using: &random) ? .solo : .group) }
                // Now and then a layer twice, with the same kind or the other.
                if let some = needs.randomElement(using: &random), Bool.random(using: &random) {
                    let kind: TextureKey.Kind = Bool.random(using: &random) ? some.kind : .solo
                    needs.insert(
                        TextureNeed(layerID: some.layerID, kind: kind),
                        at: Int.random(in: 0...needs.count, using: &random))
                }
                return needs
            }
            let needs = someNeeds()
            scheduler.setNeeds(needs)
            reference.setNeeds(needs)
            var batch: DetailBatch?
            for step in 0..<400 {
                let label = "seed \(seed), step \(step)"
                let id = UInt64.random(in: layers, using: &random)
                let kind: TextureKey.Kind = Bool.random(using: &random) ? .solo : .group
                switch Int.random(in: 0..<100, using: &random) {
                case 0..<4:
                    let needs = someNeeds()
                    scheduler.setNeeds(needs)
                    reference.setNeeds(needs)
                case 4..<8:
                    let visible = Array(layers.shuffled(using: &random).prefix(6))
                    scheduler.setVisible(visible)
                    reference.setVisible(visible)
                case 8..<30:
                    let mine = scheduler.nextBatch(), theirs = reference.nextBatch()
                    XCTAssertEqual(mine?.needs, theirs?.needs, label)
                    if let mine { batch = mine }
                case 30..<55:
                    // What a batch's answer does: arrivals of the kinds asked for, mostly.
                    let asked = batch?.needs.randomElement(using: &random)
                    let layer = asked?.layerID ?? id
                    let arrived = Int.random(in: 0..<4, using: &random) == 0 ? kind : (asked?.kind ?? kind)
                    scheduler.received(arrived, for: layer)
                    reference.received(arrived, for: layer)
                    scheduler.answered(layer)
                    reference.answered(layer)
                case 55..<62:
                    scheduler.failed(id)
                    reference.failed(id)
                case 62..<75:
                    if let batch {
                        let completed = Bool.random(using: &random)
                        scheduler.batchEnded(batch.id, completed: completed)
                        reference.batchEnded(batch.id, completed: completed)
                    }
                case 75..<82:
                    let needs = [TextureNeed(layerID: id, kind: kind)]
                    scheduler.invalidate(needs)
                    reference.invalidate(needs)
                case 82..<85:
                    scheduler.startRound()
                    reference.startRound()
                    batch = nil
                default:
                    scheduler.answered(id)
                    reference.answered(id)
                }
                XCTAssertEqual(scheduler.progress, reference.progress, label)
            }
        }
    }
}

/// The scheduler as it was before it counted, to compare with.
struct ReferenceScheduler {
    static let batchSize = 8

    private var round: UInt64 = 0
    private var needs: [TextureNeed] = []
    private var kindByLayer: [UInt64: TextureKey.Kind] = [:]
    private var visible: [UInt64] = []
    private var receivedIn: [TextureNeed: UInt64] = [:]
    private var failedIn: [TextureNeed: UInt64] = [:]
    private var current: DetailBatch?
    private var nextBatchID: UInt64 = 1

    init() {}

    mutating func startRound() {
        round += 1
        current = nil
        receivedIn.removeAll(keepingCapacity: true)
        failedIn.removeAll(keepingCapacity: true)
    }

    mutating func setNeeds(_ needs: [TextureNeed]) {
        self.needs = needs
        kindByLayer = Dictionary(
            needs.map { ($0.layerID, $0.kind) }, uniquingKeysWith: { first, _ in first })
    }

    mutating func setVisible(_ ids: [UInt64]) {
        visible = ids
    }

    mutating func nextBatch() -> DetailBatch? {
        guard current == nil else { return nil }
        let inView = visible.compactMap { id in
            kindByLayer[id].map { TextureNeed(layerID: id, kind: $0) }
        }
        var chosen: [TextureNeed] = []
        var seen = Set<UInt64>()
        for need in inView + needs where chosen.count < Self.batchSize {
            guard !isSettled(need), seen.insert(need.layerID).inserted else { continue }
            chosen.append(need)
        }
        guard !chosen.isEmpty else { return nil }
        let batch = DetailBatch(id: nextBatchID, needs: chosen)
        nextBatchID += 1
        current = batch
        return batch
    }

    mutating func invalidate(_ needs: some Sequence<TextureNeed>) {
        for need in needs {
            receivedIn[need] = nil
            failedIn[need] = nil
        }
    }

    mutating func received(_ kind: TextureKey.Kind, for layerID: UInt64) {
        receivedIn[TextureNeed(layerID: layerID, kind: kind)] = round
    }

    mutating func failed(_ layerID: UInt64) {
        failedIn[TextureNeed(layerID: layerID, kind: .solo)] = round
        failedIn[TextureNeed(layerID: layerID, kind: .group)] = round
    }

    mutating func answered(_ layerID: UInt64) {
        guard let asked = current?.needs.first(where: { $0.layerID == layerID }) else { return }
        failIfStillDue(asked)
    }

    mutating func batchEnded(_ id: UInt64, completed: Bool) {
        guard let batch = current, batch.id == id else { return }
        current = nil
        guard completed else { return }
        for need in batch.needs { failIfStillDue(need) }
    }

    var recordCount: Int { receivedIn.count + failedIn.count }

    var progress: DetailProgress {
        DetailProgress(completed: needs.lazy.filter { isSettled($0) }.count, total: needs.count)
    }

    private func isSettled(_ need: TextureNeed) -> Bool {
        receivedIn[need] == round || failedIn[need] == round
    }

    private mutating func failIfStillDue(_ asked: TextureNeed) {
        guard kindByLayer[asked.layerID] == asked.kind, !isSettled(asked) else { return }
        failedIn[asked] = round
    }
}
