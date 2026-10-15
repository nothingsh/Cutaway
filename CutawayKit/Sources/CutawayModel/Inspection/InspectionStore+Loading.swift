import CutawayScene
import CutawayTransport
import CutawayWire

extension InspectionStore {
    // MARK: - Asking for the layers

    /// Asks the app for its layers again and starts a new round of screenshots and of the
    /// selected layer's attributes (C-DET-05). What is shown stays until the new arrives;
    /// expansion, selection, focus and the cameras are kept (C-HIER-02). Asked for again while
    /// one is under way, it is made once more after that one. Nothing happens while the
    /// inspection is closed.
    public func refresh() {
        guard isOpen, !isSavingArchive else { return }
        loader.reload()
    }

    /// Asks the app for the layer and all its descendants again and puts the answer in place
    /// of that subtree (C-DET-07, C-HIER-08). Their screenshots, and the ancestors' group
    /// images, are asked for again; the rest of the tree and its screenshots stay. Queued
    /// after a load under way; a subtree that is already on its way or waiting is not asked
    /// for twice, nor while a whole reload waits. Nothing happens while the inspection is
    /// closed, when the server cannot send subtrees, or for a layer that is not in the tree.
    public func refreshSubtree(of id: UInt64) {
        guard isOpen, !isSavingArchive, canRefreshSubtrees, loadState == .loaded, tree.contains(id)
        else { return }
        loader.requestSubtree(id)
    }

    /// Takes a hierarchy as the new tree. Layers that are still there keep their expansion
    /// and the selection (C-HIER-02); new layers open by the rule (C-HIER-09); the state of
    /// layers that are gone is dropped. A hierarchy that is not a tree is refused and what is
    /// there stays. Package for tests.
    package func apply(_ hierarchy: Hierarchy) {
        let newTree: LayerTree
        do {
            newTree = try LayerTree(hierarchy)
        } catch {
            loadState = .failed(.invalidHierarchy(error.explanation))
            return
        }
        install(newTree, renewing: .all)
    }

    // MARK: - Taking a tree in

    /// What screenshots a new tree asks for again.
    private enum Renewal {
        /// A whole tree: a new round, everything.
        case all
        /// A subtree taken again: these, in the round under way.
        case needs([TextureNeed])
    }

    /// Puts a new tree in place, from a whole hierarchy or from a subtree taken again
    /// (C-HIER-08). They differ in the screenshots: a whole tree starts a new round, a
    /// subtree makes some images due again in the round under way (C-DET-06, C-DET-07). The
    /// attributes start a new round too, except after a change: the changed layer's are the
    /// change's answer, and the others were dropped then.
    private func install(_ newTree: LayerTree, renewing: Renewal, renewsAttributes: Bool = true) {
        // An archive's state is taken in before the tree is laid out: the expansion, the
        // focus and the hidden layers each laid a tree of thousands of layers out again. The
        // rest of it follows once the tree is in.
        let restoring = pendingRestore
        let (change, state) = transition {
            $0.take(newTree, restoring: restoring, newLayers: newLayers)
        }
        if let restoring, restoring.showsHiddenLayers != showsHiddenLayers {
            showsHiddenLayers = restoring.showsHiddenLayers
        }
        // Images and the hover of layers that are gone go too, before the tree is published.
        dropImages(goneFrom: newTree)
        publishHover(state.hover)

        // The selection first, the tree after it: whoever follows the tree finds the rest in
        // place. The focus before the layout is built, which reads it.
        let focusChanged = change.contains(.focus)
        publishFocus(state.focus)
        // The attributes start their new round with the new selection, so that publishing it
        // asks for nothing twice.
        if renewsAttributes { attributes.select(state.selection, newRound: newTree) }
        setSelection(state.selection)
        renewScreenshots(renewing, for: newTree)
        // Before the tree, as the selection: the rows are in place when it publishes.
        let filterChanged = refilter(in: newTree)
        // An equal tree has the same layers, expansion and geometry: laying it out again
        // and publishing it would only make the list reload. The new round goes on.
        let treeChanged = newTree != tree
        if treeChanged || restoring != nil {
            layOut(newTree)
            tree = newTree
        }
        // A state restored onto an equal tree changes only the expansion: the list follows it.
        if restoring != nil, !treeChanged { announceExpansion() }
        if treeChanged || filterChanged || focusChanged { announceRows() }
        swapTextures()
        // A focus that ended with its layer is a change of focus like any other.
        if focusChanged { fitCamerasToTheFocus() }
        // After the new round's progress: clearing the notice first would show the earlier
        // round's progress for a moment.
        if notice != nil { notice = nil }
        if loadState != .loaded { loadState = .loaded }
        if let restoring {
            pendingRestore = nil
            applyView(restoring)
        }
        // Another load that waits goes first: a batch now would be ahead of it on the server.
        if loader.hasNothingQueued { fetchNext() }
    }

    /// The images of layers that are gone.
    private func dropImages(goneFrom newTree: LayerTree) {
        let gone = images.keys.filter { !newTree.contains($0) }
        guard !gone.isEmpty else { return }
        for id in gone { images[id] = nil }
        imagesChangedSubject.send(gone)
    }

    /// What is held stays shown. A batch whose end has not been taken in yet is settled
    /// first, so that it cannot mark anything below as failed.
    private func renewScreenshots(_ renewing: Renewal, for newTree: LayerTree) {
        fetcher.cancel()
        switch renewing {
        case .needs(let needs):
            fetcher.invalidate(needs)
        case .all:
            // A new round: everything is asked for again.
            fetcher.startRound()
        }
        // The list reports its rows when it shows the new tree. Unless rows it reported
        // already are in this tree, the first batch waits for that.
        if visibleLayerIDs.contains(where: newTree.contains) {
            fetcher.cancelWaitForRows()
        } else {
            fetcher.waitForRows()
        }
    }
}

// MARK: - What the loader's answers mean

extension InspectionStore: HierarchyLoaderDelegate {
    var hasLoadedTree: Bool { loadState == .loaded }

    func loaderWillLoad(_ loader: HierarchyLoader, wholeTree: Bool) {
        attributes.setTreeLoading(true)
        // A tree that is already shown stays shown until the new one arrives.
        if wholeTree, loadState != .loaded { loadState = .loading }
    }

    func loader(
        _ loader: HierarchyLoader, finishedWholeLoad result: Result<Hierarchy, any Error>,
        outOfDate: Bool
    ) {
        switch result {
        case .success(let hierarchy):
            apply(hierarchy)
        case .failure(let error):
            switch error as? RequestError {
            case .appNotActive where outOfDate && isOpen:
                // The app became active after this request went out, and that news came
                // first (C-DET-04). Asked again rather than shown.
                loader.reloadAgain = true
            case .appNotActive:
                // A tree that is shown stays; the notice says why nothing new comes (C-DET-04).
                // Screenshots stop too: every request would fail the same way. The app coming
                // back loads everything again.
                if loadState == .loaded {
                    fetcher.stopOnFailure()
                    fetcher.cancel()
                    notice = .appNotActive
                } else {
                    loadState = .failed(.appNotActive)
                }
            case .disconnected:
                // The app is about to leave the list, and this inspection with it (C-CONN-07).
                // Nothing more is asked for; the attributes still learn the tree stopped coming.
                loader.reloadAgain = false
                loader.queuedSubtrees.removeAll()
            default:
                // A tree that is shown stays; the notice says the new one did not come
                // (C-DET-05).
                if loadState == .loaded {
                    notice = .layersFailed
                } else {
                    loadState = .failed(.other)
                }
            }
        }
    }

    func loader(
        _ loader: HierarchyLoader, finishedSubtree id: UInt64, changed: Set<UInt64>?,
        result: Result<Hierarchy, any Error>, outOfDate: Bool
    ) {
        switch result {
        case .success(let answer):
            do {
                let newTree = try tree.replacingSubtree(with: answer)
                if let changed {
                    install(
                        newTree,
                        renewing: .needs(LayerTree.needsAfterChanges(changed, in: id, from: tree, to: newTree)),
                        renewsAttributes: false)
                } else {
                    install(newTree, renewing: .needs(LayerTree.needs(ofSubtree: id, in: newTree)))
                }
            } catch {
                // The layers moved in a way a subtree cannot say: only the whole tree is
                // right (C-HIER-08), and it is reloaded without a notice.
                loader.reloadAgain = true
            }
        case .failure(let error):
            switch error as? RequestError {
            case .layerNotFound where changed != nil:
                // The window went away with the change: only the whole tree is right.
                loader.reloadAgain = true
            case .layerNotFound:
                // The tree stays; the whole tree is a refresh away (C-DET-07).
                notice = .layerGone
            case .appNotActive where outOfDate && isOpen:
                // The app became active after this request went out, and that news came
                // first (C-DET-04). Asked again rather than shown.
                if let changed {
                    loader.changedLayers.formUnion(changed)
                } else {
                    loader.queuedSubtrees.insert(id, at: 0)
                }
            case .appNotActive:
                // As for a whole reload: the tree stays, screenshots stop, and the app
                // coming back loads everything again (C-DET-04).
                fetcher.stopOnFailure()
                fetcher.cancel()
                notice = .appNotActive
            case .disconnected:
                // The app is about to leave the list, and this inspection with it (C-CONN-07).
                loader.dropQueued()
            case .unsupported:
                // Not asked for when the source cannot send subtrees (an archive); if it
                // happens anyway, the whole tree does the same job.
                loader.reloadAgain = true
            default:
                notice = .layersFailed
            }
        }
    }

    /// Attributes wait while a hierarchy is on its way, as screenshots do; so do
    /// screenshots, and when nothing is on its way any more they go on, since a batch that
    /// ended meanwhile asked for nothing after it.
    func loaderDidSettle(_ loader: HierarchyLoader) {
        attributes.setTreeLoading(loader.isLoading)
        fetchNext()
    }
}

// MARK: - What the attributes' changes mean

extension InspectionStore: AttributesStoreDelegate {
    /// A change goes ahead of the screenshots, and the preview follows it (C-DET-06).
    func attributesStoreWillSendChange(_ store: AttributesStore) -> Task<Void, Never>? {
        changesOnTheirWay += 1
        return fetcher.cancel()
    }

    /// An attribute of the layer changed (C-DET-06). Its window is taken again once nothing
    /// else is on its way; changes that succeed meanwhile make one refresh after it.
    func attributesStore(_ store: AttributesStore, didChangeLayer id: UInt64) {
        changeEnded()
        // An answer that comes after the inspection closed changes nothing shown.
        guard isOpen, loader.layerDidChange(id) else { return }
        // A change whose layer is not in the tree starts nothing: screenshots go on.
        if !loader.isLoading { fetchNext() }
    }

    func attributesStoreDidFailToChange(_ store: AttributesStore) {
        changeEnded()
        fetchNext()
    }

    /// A change that went out ended, one way or another: screenshots may go again.
    private func changeEnded() {
        if changesOnTheirWay > 0 { changesOnTheirWay -= 1 }
    }
}
