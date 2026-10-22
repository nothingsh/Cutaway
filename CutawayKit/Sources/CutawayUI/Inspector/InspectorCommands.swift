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
    /// Whether the keyboard is in text being edited, which keeps the keys it uses (C-ATTR-16).
    let isEditingText: Bool

    /// The commands as the store stands now.
    init(store: InspectionStore) {
        self.init(store: store, isArchive: store.isArchive)
    }

    /// Tests say what the window knows.
    init(store: InspectionStore, isArchive: Bool, isEditingText: Bool = false) {
        self.store = store
        self.isArchive = isArchive
        self.isEditingText = isEditingText
    }

    /// Whether the connection to the app is gone (C-WIN-03): the store takes none of the
    /// commands then, and they show as unavailable.
    var isDisconnected: Bool { store.connection.isLost }

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
        guard let id else { return false }
        return store.canExportImage(of: id, kind: kind)
    }

    // MARK: - The preview

    /// The mode, what the preview shows, and its camera (C-PREV-02, C-PREV-07 to C-PREV-09).
    var canChangePreview: Bool { !isDisconnected }

    var isShowingTwoD: Bool { store.previewMode == .twoD }

    var isShowingThreeD: Bool { store.previewMode == .threeD }

    var isShowingHiddenLayers: Bool { store.showsHiddenLayers }

    var isShowingBorders: Bool { store.borders.showsBorders }

    var borderStyle: BorderStyle { store.borders.style }

    var isOutliningOnlyAppClasses: Bool { store.borders.onlyAppClasses }

    var isShowingConstraintEnds: Bool { store.showsAllConstraintEnds }

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

    /// C-ATTR-16: a selected layer with a parent, while connected; not while text is edited,
    /// where ⌘↑ goes to the start of the text.
    var canSelectParent: Bool {
        !isDisconnected && !isEditingText && store.selectedParentID != nil
    }

    /// C-ATTR-16: a selected layer with a child the list shows; as `canSelectParent`.
    var canSelectFirstChild: Bool {
        !isDisconnected && !isEditingText && store.selectedFirstChildID != nil
    }

    /// C-HIER-06: layers to expand or collapse, and no search.
    var canExpandOrCollapseAll: Bool {
        !isDisconnected && store.filter == nil && !store.tree.isEmpty
    }
}
