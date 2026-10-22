import CutawayTransport
import CutawayWire

extension InspectionStore {
    // MARK: - Screenshots

    /// The layers whose rows are in the list's visible area, top to bottom. Their screenshots
    /// are asked for first (C-DET-01).
    public func setVisibleLayers(_ ids: [UInt64]) {
        visibleLayerIDs = ids
        fetcher.scheduler.setVisible(ids)
        // `expansion` already describes a tree that is being published, `tree` not yet.
        if fetcher.awaitingRows, ids.contains(where: expansion.knows) {
            fetcher.stopWaitingForRows()
            return
        }
        fetchNext()
    }

    /// Asks for the next batch, when one may go out.
    func fetchNext() {
        fetcher.fetchNext()
    }

    func publishProgress() {
        let progress = fetcher.scheduler.progress
        if progress != detailProgress { detailProgress = progress }
    }
}

// MARK: - What the fetcher's batches mean

extension InspectionStore: ScreenshotFetcherDelegate {
    /// Never once the connection is gone: a view that still holds the inspection may report
    /// its rows, and nothing may go out over the connection that ended.
    var mayFetchScreenshots: Bool {
        isOpen && takesIntents && !loader.isLoading && changesOnTheirWay == 0
    }

    func fetcher(_ fetcher: ScreenshotFetcher, took details: [ImageDecompression.DecompressedDetail]) {
        take(details)
    }

    func fetcherProgressChanged(_ fetcher: ScreenshotFetcher) {
        publishProgress()
    }

    func fetcher(_ fetcher: ScreenshotFetcher, failedWith failure: any Error, outOfDate: Bool) {
        if case .appNotActive = failure as? RequestError, outOfDate, isOpen {
            // The app became active after this batch went out, and that news came first
            // (C-DET-04): loading starts over, as it does when the news comes second. A load
            // that is on its way already is that start: what this batch did not bring is due
            // again, and asked for once it is in. A subtree on its way is not:
            // it renews only itself.
            publishProgress()
            if !loader.isLoadingWholeTree { loader.reload() }
            return
        }
        fetcher.stopOnFailure()
        switch failure as? RequestError {
        case .appNotActive:
            notice = .appNotActive
        case .disconnected:
            // The app is about to leave the list, and this inspection with it (C-CONN-07).
            break
        default:
            notice = .screenshotsFailed
        }
        publishProgress()
    }
}
