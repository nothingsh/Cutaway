import CutawayWire

/// Why automatic refreshes wait (C-LIVE-03). Saving an archive holds them too, which the
/// inspection knows of itself.
public enum AutoRefreshHold: Hashable, Sendable {
    /// An attribute's field has the focus and input not yet sent.
    case editing
    /// The preview is in the middle of an expand or collapse transition (C-PREV-12).
    case transition
    /// ⌥ is held to measure (C-PREV-10).
    case measuring
}

/// The changes the app reported that no load has covered yet (C-LIVE-02, C-LIVE-03).
struct ReportedChanges: Equatable {
    var roots: Set<UInt64> = []
    var whole = false

    var isEmpty: Bool { !whole && roots.isEmpty }

    /// An event without roots asks for the whole tree, as one with `whole` does: taking too
    /// much is never wrong (P-WATCH-05).
    mutating func add(_ change: HierarchyChanged) {
        if change.whole || change.roots.isEmpty {
            whole = true
        } else {
            roots.formUnion(change.roots)
        }
    }

    /// A load of `root`'s subtree, or of the whole tree when nil, was just sent: it reads the
    /// app no earlier than the checks of the events already received (P-WATCH-04).
    mutating func cover(_ root: UInt64?, in tree: LayerTree) {
        guard let root else {
            self = Self()
            return
        }
        roots = roots.filter { !tree.path(to: $0).contains(root) }
    }

    /// The subtrees to take again, outermost only and in a steady order; nil for the whole
    /// tree, also when a root is not in `tree`.
    func refresh(in tree: LayerTree) -> [UInt64]? {
        guard !whole, roots.allSatisfy(tree.contains) else { return nil }
        return roots.filter { root in
            !tree.path(to: root).dropLast().contains(where: roots.contains)
        }.sorted()
    }
}

extension InspectionStore {
    // MARK: - The switch (C-LIVE-01)

    /// Turns automatic refreshing on or off. With an app that can tell of changes, and once
    /// the first tree is in, the app is asked to tell, or to stop. Nothing happens once the
    /// connection is gone (`takesIntents`).
    public func setAutoRefresh(_ on: Bool) {
        guard takesIntents, on != autoRefresh else { return }
        autoRefresh = on
        if on {
            startWatchingIfDue()
        } else if watchSent == true {
            sendWatch(false)
        }
    }

    public func toggleAutoRefresh() {
        setAutoRefresh(!autoRefresh)
    }

    /// Asks the app to tell of changes when the switch is on, the app can, the first tree is
    /// in and it was not asked already.
    func startWatchingIfDue() {
        guard autoRefresh, canAutoRefresh, takesIntents, loadState == .loaded, watchSent != true
        else { return }
        sendWatch(true)
    }

    /// One request after another, in the order the switch moved. A request that fails leaves
    /// the switch as it is, says nothing, and is not made again until the switch moves.
    private func sendWatch(_ enabled: Bool) {
        watchSent = enabled
        if !enabled {
            watchIsOn = false
            turningWatchOff += 1
        }
        let previous = watchRequest
        watchRequest = Task { [weak self, source] in
            await previous?.value
            let on = try? await source.watchHierarchy(enabled)
            guard let self else { return }
            if enabled {
                watchIsOn = on == true && watchSent == true
            } else {
                turningWatchOff -= 1
            }
        }
    }

    // MARK: - Events (C-LIVE-02)

    /// The app reported that part of its hierarchy changed (P-WATCH-02). Taken in while the
    /// switch is on, or until the app has answered that it stopped telling; refreshed once
    /// nothing else is on its way and nothing holds refreshes back (C-LIVE-03).
    public func hierarchyDidChange(_ change: HierarchyChanged) {
        guard isOpen, takesIntents, autoRefresh || turningWatchOff > 0 else { return }
        reportedChanges.add(change)
        refreshAutomaticallyIfDue()
    }

    /// Holds automatic refreshes back, or lets them go (C-LIVE-03). Changes reported meanwhile
    /// make one refresh once nothing holds.
    public func holdAutoRefresh(_ hold: AutoRefreshHold, _ held: Bool) {
        if held {
            autoRefreshHolds.insert(hold)
        } else if autoRefreshHolds.remove(hold) != nil {
            refreshAutomaticallyIfDue()
        }
    }

    /// Makes the reported changes one refresh, unless something holds it back or another load
    /// is on its way or waits: those end by asking again.
    func refreshAutomaticallyIfDue() {
        guard !reportedChanges.isEmpty, isOpen, takesIntents, loadState == .loaded,
              !isSavingArchive, autoRefreshHolds.isEmpty, !loader.isLoading, loader.hasNothingQueued
        else { return }
        let roots = reportedChanges.refresh(in: tree)
        reportedChanges = ReportedChanges()
        if let roots {
            loader.refreshAutomatically(roots)
        } else {
            loader.reload()
        }
    }
}
