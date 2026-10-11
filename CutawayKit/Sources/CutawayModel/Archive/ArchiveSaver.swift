import Foundation

/// Runs one capture at a time (C-ARCH-02): starts it, carries its progress to the main actor
/// and says how it ended. What the ending means for what is shown is the inspection's to
/// decide.
@MainActor
final class ArchiveSaver {
    private var task: Task<Void, Never>?

    /// Whether a capture is under way.
    var isSaving: Bool { task != nil }

    /// Captures `source` into an archive at `url`. Does nothing while one is under way.
    /// `progressed` is called with layers done and the total; `finished` once, with success
    /// or why the capture ended otherwise, after which another may start.
    func save(
        from source: any ArchiveRecordable, to url: URL, stamp: ArchiveCapture.Stamp,
        maxTextureDimension: UInt32, progressed: @escaping @MainActor (Int, Int) -> Void,
        finished: @escaping @MainActor (Result<Void, ArchiveCaptureError>) -> Void
    ) {
        guard task == nil else { return }
        // The capture reports from wherever it runs; the reports are taken in here.
        let (reports, reporter) = AsyncStream.makeStream(of: (Int, Int).self)
        let progress = Task { [weak self] in
            for await (completed, total) in reports {
                // A report that comes after the end is passed over.
                guard self?.task != nil else { continue }
                progressed(completed, total)
            }
        }
        task = Task { [weak self, source] in
            let outcome: Result<Void, ArchiveCaptureError>
            defer { progress.cancel() }
            do throws(ArchiveCaptureError) {
                try await ArchiveCapture.run(
                    from: source, to: url, stamp: stamp, maxTextureDimension: maxTextureDimension,
                    progress: { reporter.yield(($0, $1)) })
                outcome = .success(())
            } catch {
                outcome = .failure(error)
            }
            self?.task = nil
            finished(outcome)
        }
    }

    /// Stops the capture under way; nothing is left at its destination.
    func cancel() {
        task?.cancel()
    }
}
