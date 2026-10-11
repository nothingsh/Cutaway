import CutawayModel
import CutawayScene

/// Which of an inspector window's menu and toolbar commands can be used now, and which are
/// checked. Every property reads the store when it is asked, as AppKit asks before it shows a
/// menu or after an event; nothing is kept.
@MainActor
struct InspectorCommands {
    let store: InspectionStore
    /// Whether the window shows an archive rather than an app (C-ARCH-05).
    let isArchive: Bool
    /// Whether the connection to the app is gone (C-WIN-03).
    let isDisconnected: Bool

    /// The commands as the store stands now.
    init(store: InspectionStore) {
        self.init(store: store, isArchive: store.isArchive, isDisconnected: store.connection.isLost)
    }

    /// Tests say what the window knows.
    init(store: InspectionStore, isArchive: Bool, isDisconnected: Bool) {
        self.store = store
        self.isArchive = isArchive
        self.isDisconnected = isDisconnected
    }

    // MARK: - Asking the app

    /// The window is an app's, the connection is there, and no archive is being saved: what
    /// asking the app again needs.
    var canAskTheApp: Bool {
        !isArchive && !isDisconnected && !store.isSavingArchive
    }

    /// C-DET-05.
    var canRefresh: Bool { canAskTheApp }

    /// C-DET-07: a server that can, and a layer to start from.
    var canRefreshSelectedSubtree: Bool {
        canAskTheApp && store.canRefreshSubtrees && store.selectedLayerID != nil
    }

    /// C-ARCH-02.
    var canSaveArchive: Bool { canAskTheApp }

    /// C-ARCH-06: a layer whose screenshot can be had, while connected.
    func canExport(_ kind: TextureKey.Kind, of id: UInt64?) -> Bool {
        guard !isDisconnected, let id else { return false }
        return store.canExportImage(of: id, kind: kind)
    }

    // MARK: - The preview

    /// The mode, what the preview shows, and its camera (C-PREV-02, C-PREV-07 to C-PREV-09).
    var canChangePreview: Bool { !isDisconnected }

    var isShowingTwoD: Bool { store.previewMode == .twoD }

    var isShowingThreeD: Bool { store.previewMode == .threeD }

    var isShowingHiddenLayers: Bool { store.showsHiddenLayers }

    var isShowingBorders: Bool { store.showsBorders }

    // MARK: - The list

    /// C-HIER-04: once the layers are in.
    var canFindLayer: Bool {
        !isDisconnected && store.loadState == .loaded
    }

    /// C-HIER-05: a selected layer that is not the focus already.
    var canFocusOnSelectedLayer: Bool {
        !isDisconnected && store.selectedLayerID != nil
            && store.selectedLayerID != store.focusedLayerID
    }

    /// C-HIER-05: while there is a focus.
    var canShowAllLayers: Bool {
        !isDisconnected && store.focusedLayerID != nil
    }

    /// C-HIER-06: layers to expand or collapse, and no search.
    var canExpandOrCollapseAll: Bool {
        !isDisconnected && store.filter == nil && !store.tree.isEmpty
    }
}
