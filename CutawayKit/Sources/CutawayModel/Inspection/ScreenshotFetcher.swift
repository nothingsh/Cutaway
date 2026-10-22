import CutawayScene
import CutawayTransport
import CutawayWire

/// What the fetcher asks of the inspection, and tells it. What a failed batch means for what
/// is shown is the inspection's to decide; the fetcher only asks for the batches.
@MainActor
protocol ScreenshotFetcherDelegate: AnyObject {
    /// Whether a batch may go out now: the inspection is open, no hierarchy is on its way
    /// (the new tree starts a new round, and a batch of the old one would only be
    /// cancelled), and no change is on its way (P-REQ-06).
    var mayFetchScreenshots: Bool { get }
    /// Goes up each time the app reports it is active (C-DET-04).
    var activeGeneration: UInt64 { get }
    /// Decompresses one image, away from the main thread (C-DET-09).
    var decodeImage: @Sendable (EncodedImage) throws -> Bitmap { get }
    /// A chunk of a batch, decompressed.
    func fetcher(_ fetcher: ScreenshotFetcher, took details: [ImageDecompression.DecompressedDetail])
    /// How far the round got may have changed.
    func fetcherProgressChanged(_ fetcher: ScreenshotFetcher)
    /// A batch's stream failed, other than a first cancel by the server. `outOfDate` when the
    /// app reported itself active after the batch went out.
    func fetcher(_ fetcher: ScreenshotFetcher, failedWith failure: any Error, outOfDate: Bool)
}

/// Asks the app for screenshots, two batches under way at a time (C-SCALE-04), in the order the
/// scheduler decides (C-DET-01, C-DET-02): the batches under way, the wait for the rows in
/// view before a new tree's first batch, and whether asking stopped on a failure.
@MainActor
final class ScreenshotFetcher {
    private let source: any InspectionSource
    /// The longest side the app may send an image with; 0 for no limit (P-DET-05).
    private let maxTextureDimension: UInt32
    /// Weak: a task may hold the fetcher while it delivers an answer after the inspection is
    /// gone, which then does nothing.
    private weak var delegate: (any ScreenshotFetcherDelegate)?

    /// Which layers' screenshots to ask for next, and what has come this round.
    var scheduler = DetailScheduler()
    /// A batch being asked for, the active generation it was asked under, and the task that
    /// reads its stream.
    private struct Fetch {
        var batch: UInt64
        var generation: UInt64
        var task: Task<Void, Never>
    }

    /// The batches being asked for, oldest first.
    private var fetches: [Fetch] = []
    /// Set when asking for screenshots stopped on a failure; a new round clears it.
    private(set) var isStopped = false
    /// Set when the server ended a batch's stream as cancelled without being asked to, and
    /// that batch was asked for again. A new round clears it.
    private(set) var retriedServerCancel = false
    /// Set while a new tree's first batch waits for the list to say which rows it shows, so
    /// that it is not asked for in tree order (C-DET-01). A report of rows in the tree, or
    /// `rowsWait`, ends it.
    private(set) var awaitingRows = false
    private var rowsWaitTask: Task<Void, Never>?
    /// How long a first batch waits for the rows in view. Changed by tests.
    var rowsWait: Duration = .milliseconds(200)
    /// How many batches were asked for. For tests.
    private(set) var batchesStarted = 0

    init(
        source: any InspectionSource, maxTextureDimension: UInt32,
        delegate: any ScreenshotFetcherDelegate
    ) {
        self.source = source
        self.maxTextureDimension = maxTextureDimension
        self.delegate = delegate
    }

    private func isUnderWay(_ batch: UInt64) -> Bool {
        fetches.contains { $0.batch == batch }
    }

    // MARK: - Rounds

    /// A new round: everything is asked for again, and asking goes on even if it had
    /// stopped.
    func startRound() {
        scheduler.startRound()
        isStopped = false
        retriedServerCancel = false
    }

    /// These needs are due again in the round under way (C-DET-06, C-DET-07), and asking
    /// goes on even if it had stopped.
    func invalidate(_ needs: [TextureNeed]) {
        scheduler.invalidate(needs)
        isStopped = false
        retriedServerCancel = false
    }

    /// Asking stopped on a failure: no batch goes out until a new round, or until a
    /// subtree makes images due again.
    func stopOnFailure() {
        isStopped = true
    }

    // MARK: - Batches

    /// Asks for batches until as many are under way as the scheduler allows, unless asking
    /// stopped on a failure, a new tree's first batch waits for the rows in view, or the
    /// inspection says not now.
    func fetchNext() {
        while startBatch() {}
    }

    /// Asks for one more batch; false when none went out.
    private func startBatch() -> Bool {
        guard let delegate, delegate.mayFetchScreenshots, !isStopped, !awaitingRows,
              let batch = scheduler.nextBatch()
        else { return false }
        batchesStarted += 1
        let request = GetLayerDetails(
            requests: batch.needs.map {
                LayerDetailRequest(
                    layerID: $0.layerID, wantSolo: $0.kind == .solo, wantGroup: $0.kind == .group,
                    wantAttributes: false)
            },
            maxTextureDimension: maxTextureDimension)
        let task = Task { [weak self, source] in
            // Cancelled before it ran: nothing was sent, so there is nothing to cancel, and
            // cancel() has settled the batch already.
            guard !Task.isCancelled else { return }
            let stream = await source.layerDetails(request)
            var failure: (any Error)?
            do {
                for try await details in stream.chunks {
                    // A batch that was cancelled or replaced takes nothing more in: checked
                    // again once the chunk is decompressed, which a cancel may have overtaken.
                    guard let decode = self?.decoder(forBatch: batch.id) else { break }
                    let decompressed = await ImageDecompression.decompress(details, using: decode)
                    guard let self, self.isUnderWay(batch.id) else { break }
                    self.delegate?.fetcher(self, took: decompressed)
                }
            } catch {
                failure = error
            }
            if Task.isCancelled {
                // Awaited here, so that whoever waits for this task knows the Cancel went
                // out: a change sent next must not overtake it (C-DET-06).
                await stream.cancel()
                return
            }
            self?.finishBatch(batch.id, failure: failure)
        }
        fetches.append(Fetch(batch: batch.id, generation: delegate.activeGeneration, task: task))
        return true
    }

    /// The decompression to use for a chunk of this batch; nil once the batch was cancelled or
    /// replaced.
    private func decoder(forBatch id: UInt64) -> (@Sendable (EncodedImage) throws -> Bitmap)? {
        isUnderWay(id) ? delegate?.decodeImage : nil
    }

    /// The end of a batch's stream. Ignored for a batch that was cancelled or replaced.
    private func finishBatch(_ id: UInt64, failure: (any Error)?) {
        // Held for the whole answer: what the delegate does may let go of it.
        guard let index = fetches.firstIndex(where: { $0.batch == id }), let delegate else { return }
        let current = fetches.remove(at: index)
        guard let failure else {
            scheduler.batchEnded(id, completed: true)
            delegate.fetcherProgressChanged(self)
            fetchNext()
            return
        }
        scheduler.batchEnded(id, completed: false)
        if case .cancelled = failure as? RequestError, !retriedServerCancel {
            // The other batch goes on.
            // The client forgets a batch before it cancels it, so this stream was cancelled
            // by the server on its own, which P-REQ-04 does not provide for. Asked for once
            // more in this round; a second time, the inspection decides.
            retriedServerCancel = true
            delegate.fetcherProgressChanged(self)
            fetchNext()
            return
        }
        // The other batch is cancelled too: what it did not bring is due again, and the
        // inspection decides what the failure means, as with one batch.
        cancel()
        delegate.fetcher(
            self, failedWith: failure, outOfDate: current.generation != delegate.activeGeneration)
    }

    /// Cancels the batches under way. Reading their streams stops, which cancels the
    /// requests (P-REQ-04); what they did not bring is due again.
    /// Returns a task that ends once every `Cancel` has gone out (C-DET-06).
    @discardableResult
    func cancel() -> Task<Void, Never>? {
        guard !fetches.isEmpty else { return nil }
        let cancelled = fetches
        fetches = []
        for fetch in cancelled {
            fetch.task.cancel()
            scheduler.batchEnded(fetch.batch, completed: false)
        }
        delegate?.fetcherProgressChanged(self)
        let tasks = cancelled.map(\.task)
        return Task {
            for task in tasks { await task.value }
        }
    }

    // MARK: - The rows in view

    /// Holds the next batch until the list reports the rows it shows, or `rowsWait` passes.
    func waitForRows() {
        awaitingRows = true
        rowsWaitTask?.cancel()
        rowsWaitTask = Task { [weak self, rowsWait] in
            // A timer replaced while its end was already on its way to the main actor must
            // not end the newer wait.
            guard (try? await Task.sleep(for: rowsWait)) != nil, !Task.isCancelled else { return }
            self?.stopWaitingForRows()
        }
    }

    /// The rows came, or the wait is over: the batch goes out.
    func stopWaitingForRows() {
        guard awaitingRows else { return }
        cancelWaitForRows()
        fetchNext()
    }

    func cancelWaitForRows() {
        awaitingRows = false
        rowsWaitTask?.cancel()
        rowsWaitTask = nil
    }
}
