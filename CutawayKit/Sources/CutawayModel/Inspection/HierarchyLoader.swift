import CutawayTransport
import CutawayWire

/// What the loader asks of the inspection, and tells it. What a tree that came, or did not,
/// means for what is shown is the inspection's to decide; the loader only sequences the
/// requests.
@MainActor
protocol HierarchyLoaderDelegate: AnyObject {
    /// Whether the inspection is on screen.
    var isOpen: Bool { get }
    /// Goes up each time the app reports it is active (C-DET-04).
    var activeGeneration: UInt64 { get }
    /// Whether a tree is shown.
    var hasLoadedTree: Bool { get }
    var tree: LayerTree { get }
    /// A load is about to go out: the whole tree, or a subtree.
    func loaderWillLoad(_ loader: HierarchyLoader, wholeTree: Bool)
    /// The whole tree came, or did not. `outOfDate` when the app reported itself active after
    /// the request went out. The loader goes on to the loads that wait afterwards.
    func loader(
        _ loader: HierarchyLoader, finishedWholeLoad result: Result<Hierarchy, any Error>,
        outOfDate: Bool
    )
    /// A subtree came, or did not. `changed` is nil for a subtree the user asked for
    /// (C-DET-07), and the changed layers for a refresh after a change (C-DET-06).
    func loader(
        _ loader: HierarchyLoader, finishedSubtree id: UInt64, changed: Set<UInt64>?,
        result: Result<Hierarchy, any Error>, outOfDate: Bool
    )
    /// The loads that waited were started or dropped; `isLoading` says whether one is on its
    /// way now.
    func loaderDidSettle(_ loader: HierarchyLoader)
}

/// Asks the app for its layers: the whole tree (C-DET-05) or a subtree (C-DET-07, C-DET-06),
/// one request at a time. Asked while one is on its way, it remembers what to ask next: a
/// whole reload first, then a refresh after changes, then the subtrees in order. A whole
/// reload takes the place of every subtree that waits.
@MainActor
final class HierarchyLoader {
    private let source: any InspectionSource
    private unowned let delegate: any HierarchyLoaderDelegate

    private(set) var isLoading = false
    /// Set when a reload is asked for while a load is under way: it is made after that one.
    var reloadAgain = false
    /// The layer whose subtree is on its way, when the load under way is one.
    private(set) var loadingSubtree: UInt64?
    /// Subtrees to load after the load under way, in the order they were asked for.
    var queuedSubtrees: [UInt64] = []
    /// Layers whose attributes changed since the last refresh after a change started; their
    /// windows are taken again once the load under way ends (C-DET-06).
    var changedLayers: Set<UInt64> = []
    /// The changed layers the load under way refreshes, when it is a refresh after a change.
    private(set) var refreshingChanges: Set<UInt64>?

    init(source: any InspectionSource, delegate: any HierarchyLoaderDelegate) {
        self.source = source
        self.delegate = delegate
    }

    /// Whether the load under way is of the whole tree.
    var isLoadingWholeTree: Bool { isLoading && loadingSubtree == nil }

    /// Whether no load waits for the one under way to end.
    var hasNothingQueued: Bool { !reloadAgain && changedLayers.isEmpty && queuedSubtrees.isEmpty }

    // MARK: - The whole tree

    /// Asks the app for its hierarchy, once `previous` is done. Asked while a request is
    /// under way, it asks once more after that one.
    func reload(after previous: Task<Void, Never>? = nil) {
        guard !isLoading else {
            reloadAgain = true
            // The whole tree holds every subtree that waits.
            queuedSubtrees.removeAll()
            return
        }
        isLoading = true
        delegate.loaderWillLoad(self, wholeTree: true)
        let generation = delegate.activeGeneration
        Task { [weak self, source] in
            await previous?.value
            let result: Result<Hierarchy, any Error>
            do {
                result = .success(try await source.hierarchy())
            } catch {
                result = .failure(error)
            }
            self?.finishWholeLoad(result, generation: generation)
        }
    }

    private func finishWholeLoad(_ result: Result<Hierarchy, any Error>, generation: UInt64) {
        // Held for the whole answer: the delegate is unowned, and what it does may let go
        // of it.
        let delegate = self.delegate
        isLoading = false
        delegate.loader(
            self, finishedWholeLoad: result, outOfDate: generation != delegate.activeGeneration)
        startNext(delegate)
    }

    // MARK: - Subtrees

    /// Asks for the layer's subtree, or queues it after the load under way: a subtree that is
    /// already on its way or waiting is not asked for twice, nor while a whole reload waits.
    func requestSubtree(_ id: UInt64) {
        guard !isLoading else {
            if !reloadAgain, loadingSubtree != id || refreshingChanges != nil,
               !queuedSubtrees.contains(id)
            {
                queuedSubtrees.append(id)
            }
            return
        }
        loadSubtree(id)
    }

    /// An attribute of the layer changed (C-DET-06). Its window is taken again once nothing
    /// else is on its way; changes that succeed meanwhile make one refresh after it. Returns
    /// whether that could start now; otherwise the change waits for the load under way, or
    /// for a tree.
    @discardableResult
    func layerDidChange(_ id: UInt64) -> Bool {
        changedLayers.insert(id)
        guard !isLoading, delegate.hasLoadedTree else { return false }
        startRefreshAfterChanges()
        return true
    }

    /// Takes the window of the changed layers again; changed layers of other windows wait
    /// for the next load. Changed layers no longer in the tree are dropped.
    private func startRefreshAfterChanges() {
        let tree = delegate.tree
        changedLayers = changedLayers.filter(tree.contains)
        guard let first = changedLayers.first, let root = tree.path(to: first).first else {
            return
        }
        let changed = changedLayers.filter { tree.path(to: $0).first == root }
        changedLayers.subtract(changed)
        loadSubtree(root, after: changed)
    }

    /// `changed` is nil for a subtree the user asked for (C-DET-07), and the changed layers
    /// for a refresh after a change (C-DET-06).
    private func loadSubtree(_ id: UInt64, after changed: Set<UInt64>? = nil) {
        isLoading = true
        loadingSubtree = id
        refreshingChanges = changed
        delegate.loaderWillLoad(self, wholeTree: false)
        let generation = delegate.activeGeneration
        Task { [weak self, source] in
            let result: Result<Hierarchy, any Error>
            do {
                result = .success(try await source.subtree(of: id))
            } catch {
                result = .failure(error)
            }
            self?.finishSubtree(id, result, generation: generation)
        }
    }

    private func finishSubtree(
        _ id: UInt64, _ result: Result<Hierarchy, any Error>, generation: UInt64
    ) {
        let delegate = self.delegate
        isLoading = false
        loadingSubtree = nil
        let changed = refreshingChanges
        refreshingChanges = nil
        delegate.loader(
            self, finishedSubtree: id, changed: changed, result: result,
            outOfDate: generation != delegate.activeGeneration)
        startNext(delegate)
    }

    // MARK: - What waits

    /// After a load ended: a whole reload that waits goes first, then a refresh after changes
    /// (C-DET-06), then the subtrees that wait, in order. A whole reload does not take the
    /// place of changes: its answer may be older than they are. Subtrees of a tree that is
    /// not loaded, such as one the last whole load refused, are dropped: only a whole load
    /// can bring it back.
    private func startNext(_ delegate: any HierarchyLoaderDelegate) {
        if reloadAgain {
            reloadAgain = false
            queuedSubtrees.removeAll()
            reload()
        } else if !delegate.hasLoadedTree {
            queuedSubtrees.removeAll()
            changedLayers.removeAll()
        } else {
            if delegate.isOpen, !changedLayers.isEmpty { startRefreshAfterChanges() }
            while !isLoading, !queuedSubtrees.isEmpty {
                let next = queuedSubtrees.removeFirst()
                if delegate.isOpen, delegate.tree.contains(next) { loadSubtree(next) }
            }
        }
        delegate.loaderDidSettle(self)
    }

    /// Nothing that waits is wanted any more: the inspection is left, and entering again
    /// reloads.
    func dropQueued() {
        reloadAgain = false
        queuedSubtrees.removeAll()
        changedLayers.removeAll()
    }
}
