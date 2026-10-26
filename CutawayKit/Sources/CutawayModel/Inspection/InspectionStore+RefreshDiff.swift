extension InspectionStore {
    /// Marks what refreshes change, or stops; turned off, the marks shown go at once
    /// (C-LIVE-05).
    public func setHighlightsChanges(_ on: Bool) {
        guard on != highlightsChanges else { return }
        highlightsChanges = on
        if !on, refreshDiff != nil { refreshDiff = nil }
    }

    /// What taking in `new` in place of `old` changed within `root`'s subtree, or the whole
    /// tree for nil, replaces what the last refresh changed. The first tree an inspection takes
    /// in marks nothing: the first load, the first after a reconnect, an archive (C-LIVE-05).
    func markChanges(from old: LayerTree, to new: LayerTree, within root: UInt64?) {
        defer { hasInstalledTree = true }
        guard hasInstalledTree, highlightsChanges else { return }
        let diff = RefreshDiff(from: old, to: new, within: root, generation: diffGeneration + 1)
        if diff != nil { diffGeneration += 1 }
        if diff != refreshDiff { refreshDiff = diff }
    }
}
