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

/// Asks the app for screenshots, a batch at a time, in the order the scheduler decides
/// (C-DET-01, C-DET-02): the batch under way, the wait for the rows in view before a new
/// tree's first batch, and whether asking stopped on a failure.
@MainActor
final class ScreenshotFetcher {
    private let source: any InspectionSource
    /// The longest side the app may send an image with; 0 for no limit (P-DET-05).
    private let maxTextureDimension: UInt32
    private unowned let delegate: any ScreenshotFetcherDelegate

    /// Which layers' screenshots to ask for next, and what has come this round.
    var scheduler = DetailScheduler()
    /// The batch being asked for, the active generation it was asked under, and the task
    /// that reads its stream.
    private var fetch: (batch: UInt64, generation: UInt64, task: Task<Void, Never>)?
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

    /// Whether a batch is on its way.
    var isFetching: Bool { fetch != nil }

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

    /// Asks for the next batch, unless one is under way, asking stopped on a failure, a new
    /// tree's first batch waits for the rows in view, or the inspection says not now.
    func fetchNext() {
        guard delegate.mayFetchScreenshots, !isStopped, !awaitingRows, fetch == nil,
              let batch = scheduler.nextBatch()
        else { return }
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
                    guard let self, self.fetch?.batch == batch.id else { break }
                    self.delegate.fetcher(self, took: decompressed)
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
        fetch = (batch.id, delegate.activeGeneration, task)
    }

    /// The decompression to use for a chunk of this batch; nil once the batch was cancelled or
    /// replaced.
    private func decoder(forBatch id: UInt64) -> (@Sendable (EncodedImage) throws -> Bitmap)? {
        fetch?.batch == id ? delegate.decodeImage : nil
    }

    /// The end of a batch's stream. Ignored for a batch that was cancelled or replaced.
    private func finishBatch(_ id: UInt64, failure: (any Error)?) {
        guard let current = fetch, current.batch == id else { return }
        // Held for the whole answer: the delegate is unowned, and what it does may let go
        // of it.
        let delegate = self.delegate
        fetch = nil
        guard let failure else {
            scheduler.batchEnded(id, completed: true)
            delegate.fetcherProgressChanged(self)
            fetchNext()
            return
        }
        scheduler.batchEnded(id, completed: false)
        if case .cancelled = failure as? RequestError, !retriedServerCancel {
            // The client forgets a batch before it cancels it, so this stream was cancelled
            // by the server on its own, which P-REQ-04 does not provide for. Asked for once
            // more in this round; a second time, the inspection decides.
            retriedServerCancel = true
            delegate.fetcherProgressChanged(self)
            fetchNext()
            return
        }
        delegate.fetcher(
            self, failedWith: failure, outOfDate: current.generation != delegate.activeGeneration)
    }

    /// Cancels the batch under way. Reading its stream stops, which cancels the request
    /// (P-REQ-04); what it did not bring is due again.
    /// Returns the cancelled batch's task, which ends once its `Cancel` has gone out.
    @discardableResult
    func cancel() -> Task<Void, Never>? {
        guard let current = fetch else { return nil }
        fetch = nil
        current.task.cancel()
        scheduler.batchEnded(current.batch, completed: false)
        delegate.fetcherProgressChanged(self)
        return current.task
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
