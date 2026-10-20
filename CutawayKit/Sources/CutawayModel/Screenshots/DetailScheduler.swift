import CutawayScene

/// How far loading the screenshots got: of the layers that are drawn, how many have the
/// image they are drawn with, or failed, in this round (C-DET-02).
public struct DetailProgress: Equatable, Sendable {
    public var completed: Int
    public var total: Int

    public init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }

    public static let none = Self(completed: 0, total: 0)
}

/// One request's worth of layers, and the number that tells it from earlier ones.
struct DetailBatch: Equatable, Sendable {
    var id: UInt64
    var needs: [TextureNeed]
}

/// Decides which layers' screenshots to ask for next (C-DET-01). It knows what the display
/// needs, which rows are in view, and for each layer and kind of image the round in which it
/// arrived or failed; it does no requesting itself.
///
/// A round starts each time the hierarchy is loaded: everything is due again, while the
/// images already held stay shown until new ones replace them.
struct DetailScheduler: Sendable {
    /// 32 (C-SCALE-04): what each answer costs the main thread, the preview's new
    /// projection and drawing above all, is paid once a batch rather than once in 8 layers.
    /// Still small enough that the order follows the list soon after a scroll or a collapse:
    /// a batch takes about 10 ms in the test configuration.
    static let defaultBatchSize = 32
    /// Two, so that the next batch waits at the server while one is answered (C-SCALE-04).
    static let batchesInFlight = 2

    /// How many layers a batch asks for, and how many batches may be under way at once. Eight
    /// and one give the scheduling of before, for the test that compares the two.
    var batchSize = Self.defaultBatchSize
    var maxInFlight = Self.batchesInFlight

    private var round: UInt64 = 0
    private var needs: [TextureNeed] = []
    private var kindByLayer: [UInt64: TextureKey.Kind] = [:]
    private var visible: [UInt64] = []
    private var receivedIn: [TextureNeed: UInt64] = [:]
    private var failedIn: [TextureNeed: UInt64] = [:]
    /// The batches under way, oldest first.
    private var inFlight: [DetailBatch] = []
    private var nextBatchID: UInt64 = 1
    /// How many times each need is in `needs`.
    private var neededCount: [TextureNeed: Int] = [:]
    /// How many of `needs` are settled in this round. Counted as they settle, so that taking
    /// in a chunk does not look at every need (C-SCALE-02).
    private var settledCount = 0
    /// Every need before this index in `needs` is settled: a batch looks from here on.
    private var cursor = 0

    init() {}

    /// Everything is due again. The batches under way no longer count. What arrived or failed
    /// in earlier rounds is forgotten: only this round's records are read.
    mutating func startRound() {
        round += 1
        inFlight = []
        receivedIn.removeAll(keepingCapacity: true)
        failedIn.removeAll(keepingCapacity: true)
        settledCount = 0
        cursor = 0
    }

    /// What the display needs now, as `SceneLayout.neededTextures` gives it.
    mutating func setNeeds(_ needs: [TextureNeed]) {
        self.needs = needs
        kindByLayer = Dictionary(
            needs.map { ($0.layerID, $0.kind) }, uniquingKeysWith: { first, _ in first })
        neededCount = Dictionary(needs.map { ($0, 1) }, uniquingKeysWith: +)
        settledCount = 0
        for need in needs where isSettled(need) { settledCount += 1 }
        cursor = 0
    }

    /// The layers whose rows are in the list's visible area, top to bottom.
    mutating func setVisible(_ ids: [UInt64]) {
        visible = ids
    }

    /// The next batch: needs that are not settled in this round nor asked for by a batch under
    /// way, rows in view first, then the rest in tree order. Nil while as many batches as may
    /// be are under way, or when nothing is due.
    mutating func nextBatch() -> DetailBatch? {
        guard inFlight.count < maxInFlight else { return nil }
        let asked = Set(inFlight.flatMap(\.needs).map(\.layerID))
        while cursor < needs.count, isSettled(needs[cursor]) { cursor += 1 }
        let inView = visible.compactMap { id in
            kindByLayer[id].map { TextureNeed(layerID: id, kind: $0) }
        }
        var chosen: [TextureNeed] = []
        var seen = asked
        func consider(_ need: TextureNeed) -> Bool {
            if !isSettled(need), seen.insert(need.layerID).inserted { chosen.append(need) }
            return chosen.count < batchSize
        }
        search: do {
            for need in inView where !consider(need) { break search }
            for need in needs[cursor...] where !consider(need) { break search }
        }
        guard !chosen.isEmpty else { return nil }
        let batch = DetailBatch(id: nextBatchID, needs: chosen)
        nextBatchID += 1
        inFlight.append(batch)
        return batch
    }

    /// These needs are due again in this round: what arrived or failed for them is
    /// forgotten (C-DET-07). Whether the display asks for one still follows `setNeeds`.
    mutating func invalidate(_ needs: some Sequence<TextureNeed>) {
        for need in needs {
            settle(need) {
                $0.receivedIn[need] = nil
                $0.failedIn[need] = nil
            }
        }
    }

    /// An image of this kind arrived for the layer, asked for or not.
    mutating func received(_ kind: TextureKey.Kind, for layerID: UInt64) {
        let need = TextureNeed(layerID: layerID, kind: kind)
        settle(need) { $0.receivedIn[need] = $0.round }
    }

    /// The layer is not there, or could not be captured: neither kind will come this round.
    mutating func failed(_ layerID: UInt64) {
        for kind in [TextureKey.Kind.solo, .group] {
            let need = TextureNeed(layerID: layerID, kind: kind)
            settle(need) { $0.failedIn[need] = $0.round }
        }
    }

    /// A successful detail for the layer was taken in. If a batch under way asked for a kind
    /// that is still needed and it did not come, that kind failed this round.
    mutating func answered(_ layerID: UInt64) {
        for batch in inFlight {
            guard let asked = batch.needs.first(where: { $0.layerID == layerID }) else { continue }
            failIfStillDue(asked)
        }
    }

    /// The batch with this number ended. When it completed, what it asked for and did not
    /// get failed this round; otherwise that is due again. The other batch under way goes on.
    /// The end of a batch of an earlier round is ignored.
    mutating func batchEnded(_ id: UInt64, completed: Bool) {
        guard let index = inFlight.firstIndex(where: { $0.id == id }) else { return }
        let batch = inFlight.remove(at: index)
        guard completed else { return }
        for need in batch.needs { failIfStillDue(need) }
    }

    /// How many arrivals and failures are recorded. For tests.
    var recordCount: Int { receivedIn.count + failedIn.count }

    var progress: DetailProgress {
        DetailProgress(completed: settledCount, total: needs.count)
    }

    /// Changes the records of a need, and keeps the count and the cursor right: a need that
    /// is due again may be before the cursor.
    private mutating func settle(_ need: TextureNeed, _ change: (inout Self) -> Void) {
        let was = isSettled(need)
        change(&self)
        let now = isSettled(need)
        guard was != now else { return }
        let count = neededCount[need] ?? 0
        settledCount += now ? count : -count
        if !now { cursor = 0 }
    }

    private func isSettled(_ need: TextureNeed) -> Bool {
        receivedIn[need] == round || failedIn[need] == round
    }

    /// Fails a kind that was asked for, if the display still needs that kind of that layer.
    private mutating func failIfStillDue(_ asked: TextureNeed) {
        guard kindByLayer[asked.layerID] == asked.kind, !isSettled(asked) else { return }
        settle(asked) { $0.failedIn[asked] = $0.round }
    }
}
