import CutawayTransport
import Foundation

// `applyView(_:)` is internal only so that InspectionStore+Loading.swift can call it.
extension InspectionStore {
    // MARK: - Archive

    /// What the inspection shows now, as an archive keeps it (C-ARCH-03).
    var archiveState: ArchiveState {
        ArchiveState(
            expanded: expandedLayerIDs, selected: selectedLayerID, focused: focusedLayerID,
            previewMode: previewMode, cameras: cameras, showsHiddenLayers: showsHiddenLayers,
            borders: borders, showsConstraintEnds: showsAllConstraintEnds)
    }

    public var isSavingArchive: Bool { saver.isSaving }

    /// Whether the inspection is of an archive rather than of an app (C-ARCH-05).
    public var isArchive: Bool { !source.isLive }

    /// Takes over an archive's interface state (C-ARCH-03): now when the tree is in, else
    /// once the first one is. Layers that are not in the tree are passed over; camera values
    /// out of range are brought within it.
    public func restore(_ state: ArchiveState) {
        guard loadState == .loaded else {
            pendingRestore = state
            return
        }
        applyArchiveState(state)
    }

    private func applyArchiveState(_ state: ArchiveState) {
        // An archive that does not say leaves the expansion the tree came with (C-HIER-09).
        if let expanded = state.expanded {
            let ids = tree.layers(within: nil).map(\.id)
            // Collapsing first: a selection then lands on the row that stands for it.
            setExpanded(ids.filter { !expanded.contains($0) }, false)
            setExpanded(ids.filter { expanded.contains($0) }, true)
        }
        if let focused = state.focused, tree.contains(focused) {
            focus(on: focused)
        } else {
            focus(on: nil)
        }
        setShowsHiddenLayers(state.showsHiddenLayers)
        applyView(state)
    }

    /// The parts of a state that do not lay the tree out: the selection, the mode, the
    /// cameras, the borders and the constraint ends' switch.
    func applyView(_ state: ArchiveState) {
        select(state.selected.flatMap { tree.contains($0) ? $0 : nil })
        setPreviewMode(state.previewMode)
        // After the focus, which fits the cameras to what it shows.
        var cameras = PreviewCameras()
        cameras.twoD = PreviewCameras.limited(state.cameras.twoD, flat: true)
        cameras.threeD = PreviewCameras.limited(state.cameras.threeD, flat: false)
        if cameras != self.cameras { self.cameras = cameras }
        setBorders(state.borders)
        setShowsAllConstraintEnds(state.showsConstraintEnds)
    }

    /// Captures the app into an archive at `url` (C-ARCH-02), with the interface state of
    /// this moment (C-ARCH-03). Until it ends, refreshing and editing attributes are off;
    /// browsing goes on, and the preview keeps asking for its screenshots. Does nothing while
    /// one is under way, while the inspection is closed, after the app went away, or for an
    /// archive.
    public func saveArchive(to url: URL, cutawayVersion: String) {
        // Only a connection can be captured: an archive is not saved again.
        guard isOpen, !saver.isSaving, !connectionWasLost, let session = source.recordable
        else { return }
        let stamp = ArchiveCapture.Stamp(
            cutawayVersion: cutawayVersion, savedAt: Date(), state: archiveState)
        archiveSave = .saving(completed: 0, total: 0)
        attributes.setEditingSuspended(true)
        saver.save(
            from: session, to: url, stamp: stamp, maxTextureDimension: maxTextureDimension,
            progressed: { [weak self] completed, total in
                self?.archiveSave = .saving(completed: completed, total: total)
            },
            finished: { [weak self] outcome in self?.finishArchiveSave(outcome, at: url) })
    }

    /// Stops the capture under way; nothing is left at its destination.
    public func cancelArchiveSave() {
        saver.cancel()
    }

    /// Forgets an ended save. Does nothing while one is under way.
    public func dismissArchiveSave() {
        guard !saver.isSaving, archiveSave != .idle else { return }
        archiveSave = .idle
    }

    private func finishArchiveSave(_ outcome: Result<Void, ArchiveCaptureError>, at url: URL) {
        switch outcome {
        case .success:
            archiveSave = .saved(url)
        case .failure(.failed(let failure)):
            archiveSave = .failed(failure)
        case .failure(.cancelled):
            // Cancelled by the user, or by `leave()` after the app went away (C-WIN-03).
            archiveSave = connectionWasLost ? .failed(.disconnected) : .idle
        }
        attributes.setEditingSuspended(false)
    }
}
