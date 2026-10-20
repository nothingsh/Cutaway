import Foundation

// What the tests look at inside the inspection, in one place: the state its collaborators
// keep, read through the store so that a test need not know which of them holds it.
extension InspectionStore {
    /// Whether a hierarchy is on its way.
    var isLoading: Bool { loader.isLoading }

    /// Whether a whole reload waits for the load under way.
    var reloadAgain: Bool { loader.reloadAgain }

    /// The layer whose subtree is on its way, when the load under way is one.
    var loadingSubtree: UInt64? { loader.loadingSubtree }

    /// Subtrees to load after the load under way, in order.
    var queuedSubtrees: [UInt64] { loader.queuedSubtrees }

    /// Layers whose attributes changed, whose windows are taken again once nothing else is on
    /// its way.
    var changedLayers: Set<UInt64> { loader.changedLayers }

    /// How many batches of screenshots were asked for.
    var batchesStarted: Int { fetcher.batchesStarted }

    /// How many layers a batch of screenshots asks for, and how many batches may be under way
    /// at once (C-SCALE-04): 8 and 1 for the test that compares them with what they are.
    var screenshotBatchSize: Int {
        get { fetcher.scheduler.batchSize }
        set { fetcher.scheduler.batchSize = newValue }
    }

    var screenshotBatchesInFlight: Int {
        get { fetcher.scheduler.maxInFlight }
        set { fetcher.scheduler.maxInFlight = newValue }
    }

    /// How long a new tree's first batch waits for the rows in view.
    var rowsWait: Duration {
        get { fetcher.rowsWait }
        set { fetcher.rowsWait = newValue }
    }

    /// Asks the app for its hierarchy, as `refresh()` does without its conditions.
    func reload() {
        loader.reload()
    }
}
