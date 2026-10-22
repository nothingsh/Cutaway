import AppKit
import Combine
import CutawayModel
import CutawayProjects
import CutawayScene
import CutawayTransport
import CutawayWire
import DeclarativeAppKit
import DeclarativeCombine

/// The window that inspects one app (C-WIN-01): the app's name and device in the title, the
/// 2D / 3D switch and a way to the app list in the toolbar, and the three panes below.
public final class InspectorWindowController: NSWindowController {
    /// What the window undoes while nothing can be changed: nothing.
    private let idleUndoManager = UndoManager()
    static let modeIdentifier = "inspection.mode"
    static let capsuleItem = NSToolbarItem.Identifier("inspector.capsule")
    static let modeItem = NSToolbarItem.Identifier("inspector.mode")
    static let archiveTagItem = NSToolbarItem.Identifier("inspector.archiveTag")
    static let size = NSSize(width: 1200, height: 760)
    /// Room for the three panes at their least: 220 + 320 + 260 points, and the dividers.
    static let minimumSize = NSSize(width: 820, height: 460)

    /// The app this window inspects; nil for an archive's window.
    let location: AppLocation?
    /// The archive this window shows; nil for an app's (C-ARCH-05).
    let archiveURL: URL?
    /// Which app that is, across connections; nil when it cannot be recognised (C-WIN-04).
    let identity: AppIdentity?
    let store: InspectionStore
    let splitController: InspectorSplitViewController
    let appIcon: NSImage?
    /// The toolbar's 2D / 3D switch, once the toolbar has made it.
    var modeControl: NSSegmentedControl?
    /// The toolbar's app capsule, once the toolbar has made it (C-WIN-06).
    var appCapsule: AppCapsuleView?
    /// The toolbar's Environment button and its popover (C-ENV-01).
    private(set) lazy var environment: EnvironmentToolbarController = .init(store: store) { [weak self] in
        self?.insertEnvironmentItem()
    }

    /// The title and subtitle the window is given; the capsule shows them.
    let windowTitle: InspectorWindowTitle
    /// The way to the app's project folder (C-SRC-01 to C-SRC-03).
    let project: ProjectLookup
    /// Where Copy LLDB Command puts its text (C-SRC-06); tests give one of their own.
    var pasteboard = NSPasteboard.general
    /// The panels of saving, exporting and the project folder; tests answer them themselves.
    let fileActions: InspectorFileActions
    /// Whether the window has been shown, and the project folder looked at.
    private var hasShown = false
    /// How long the capsule says "Saved" before it goes back (C-WIN-06).
    private let savedNoticeDuration: Duration
    private var savedDismissal: Task<Void, Never>?
    /// Whether the connection to the app is gone (C-WIN-03).
    public var isDisconnected: Bool { store.connection.isLost }
    /// Called when the user asks for the app list.
    var onShowApps: () -> Void = {}
    /// Called when the window is about to close, however it was closed.
    var onClose: () -> Void = {}
    /// Called when an archive was saved from this window, with its place.
    var onArchiveSaved: (URL) -> Void = { _ in }
    /// Asks where to save an archive, suggesting a name without the extension, and calls back
    /// with the place chosen; not at all when the user cancels (C-ARCH-02). The app's tests
    /// put a place of their own.
    public var chooseArchiveDestination: @MainActor (NSWindow, String, @escaping (URL) -> Void) -> Void {
        get { fileActions.chooseArchiveDestination }
        set { fileActions.chooseArchiveDestination = newValue }
    }

    /// Asks where to export a screenshot, as `chooseArchiveDestination` does (C-ARCH-06).
    public var chooseScreenshotDestination: @MainActor (NSWindow, String, @escaping (URL) -> Void) -> Void {
        get { fileActions.chooseScreenshotDestination }
        set { fileActions.chooseScreenshotDestination = newValue }
    }

    var cancellables = Set<AnyCancellable>()

    /// The window of an app over a connection.
    convenience init(
        location: AppLocation, entry: AppEntry?, store: InspectionStore,
        paneWidths: PaneWidths? = nil, savedNoticeDuration: Duration = .seconds(4),
        projects: ProjectSources? = nil
    ) {
        self.init(
            location: location, archiveURL: nil, info: entry?.info, icon: entry?.icon,
            title: InspectorWindowTitle(app: entry?.info), store: store, paneWidths: paneWidths,
            savedNoticeDuration: savedNoticeDuration, projects: projects)
    }

    /// The window of an archive (C-ARCH-05): its file's name is the title; the app, its
    /// device and when it was saved are under it.
    convenience init(
        archive: OpenedArchive, store: InspectionStore, paneWidths: PaneWidths? = nil,
        projects: ProjectSources? = nil
    ) {
        self.init(
            location: nil, archiveURL: archive.url, info: archive.app, icon: archive.icon,
            title: InspectorWindowTitle(
                archive: archive.url, app: archive.app, savedAt: archive.manifest.savedAt,
                overrides: archive.source.savedEnvironment?.overrides ?? .unspecified),
            store: store, paneWidths: paneWidths, savedNoticeDuration: .seconds(4), projects: projects)
    }

    private init(
        location: AppLocation?, archiveURL: URL?, info: AppInfo?, icon: Bitmap?,
        title: InspectorWindowTitle, store: InspectionStore, paneWidths: PaneWidths?,
        savedNoticeDuration: Duration, projects: ProjectSources?
    ) {
        self.location = location
        self.archiveURL = archiveURL
        // An archive's app is not waited for (C-WIN-04).
        self.identity = archiveURL == nil ? info.flatMap(AppIdentity.init) : nil
        self.store = store
        windowTitle = title
        self.savedNoticeDuration = savedNoticeDuration
        let name = AppEntryPresentation.name(of: info)
        // An archive's folder is found by the bundle ID it was saved from.
        project = ProjectLookup(bundleID: info?.bundleID, appName: name, sources: projects)
        fileActions = InspectorFileActions(store: store, project: project, appName: name)
        splitController = InspectorSplitViewController(
            store: store, appName: name, paneWidths: paneWidths, project: project)
        appIcon = icon?.makeImage()

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        // The capsule shows them (C-WIN-06); the Window menu and Mission Control still read
        // them.
        window.title = title.title
        window.subtitle = title.subtitle
        window.titleVisibility = .hidden
        // No band behind the toolbar: its capsules float over the preview (C-WIN-06).
        window.titlebarAppearsTransparent = true
        window.representedURL = archiveURL
        window.toolbarStyle = .unified
        // View › Enter Full Screen (C-MENU-02); a window has no full screen unless it asks.
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentViewController = splitController
        // Assigning the content view controller shrinks the window to the view's fitting size.
        window.setContentSize(Self.size)
        window.contentMinSize = Self.minimumSize
        super.init(window: window)

        // One identifier for each window: toolbars that share one take each other's
        // insertions, and the Environment button joins only the window of an app that can
        // override its environment (C-ENV-01).
        let toolbar = NSToolbar(identifier: "inspector-\(UUID().uuidString)")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.delegate = self

        splitController.containerController.onShowApps = { [weak self] in self?.close() }
        // AppKit shrinks a window larger than the screen as it shows it, and the panes with
        // it; made to fit now, they do not move then (C-WIN-02).
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            let minimum = window.frameRect(
                forContentRect: NSRect(origin: .zero, size: Self.minimumSize)).size
            window.setFrame(
                Self.frame(window.frame, fitting: visible, minimum: minimum), display: false)
        }
        window.center()
        // Laid out now, before it is shown: the panes appear at their widths (C-WIN-02).
        window.layoutIfNeeded()
        // The arrow keys and typing go to the list from the start.
        window.initialFirstResponder = splitController.hierarchyController.outlineView
        store.$archiveSave
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                if case .saved(let url) = state { self?.onArchiveSaved(url) }
            }
            .store(in: &cancellables)
        // After the panes' own subscriptions: they follow the store before the window does.
        // The connection is gone: the 2D / 3D switch shows that it can no longer be used
        // (C-WIN-03).
        store.$connection
            .sink { [weak self] connection in
                if connection.isLost { self?.modeControl?.isEnabled = false }
            }
            .store(in: &cancellables)
        environment.follow()
    }

    /// Whether this window shows an archive rather than an app (C-ARCH-05).
    public var isArchive: Bool { archiveURL != nil }

    /// Which commands can be used now: asked anew each time, so that it reads the store then.
    var commands: InspectorCommands {
        InspectorCommands(store: store, isArchive: isArchive, isEditingText: isEditingText)
    }

    /// Whether the keyboard is in text being edited: a text field's or the attribute panel's
    /// text area. A text view that only shows text, as a constraint's equation, does not count.
    var isEditingText: Bool {
        (window?.firstResponder as? NSTextView)?.isEditable ?? false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// `frame` made no larger than `visible`, a screen's visible frame, and no smaller than
    /// `minimum` (C-WIN-02).
    static func frame(_ frame: NSRect, fitting visible: NSRect, minimum: NSSize) -> NSRect {
        var fitted = frame
        fitted.size.width = max(min(frame.width, visible.width), minimum.width)
        fitted.size.height = max(min(frame.height, visible.height), minimum.height)
        return fitted
    }

    /// The capsule follows the inspection: the screenshots, a save and the connection
    /// (C-WIN-06). "Saved" goes after a few seconds, unless another save took its place.
    func followStatus() {
        guard !isArchive else { return }
        AppCapsuleState.publisher(for: store, subtitle: windowTitle.subtitle)
            .sink { [weak self] state in self?.appCapsule?.show(state) }
            .store(in: &cancellables)
        store.$archiveSave
            .sink { [weak self] state in
                guard let self else { return }
                self.savedDismissal?.cancel()
                guard case .saved(let url) = state else { return }
                self.savedDismissal = Task { [weak self, savedNoticeDuration] in
                    guard (try? await Task.sleep(for: savedNoticeDuration)) != nil,
                          let store = self?.store, store.archiveSave == .saved(url)
                    else { return }
                    store.dismissArchiveSave()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc func showApps(_ sender: Any?) {
        onShowApps()
    }

    /// Loads the layers, their screenshots and the selected layer's attributes again
    /// (C-DET-05).
    @objc func refresh(_ sender: Any?) {
        store.refresh()
        // So is the project folder's index, as far as its files changed (C-SRC-02).
        fileActions.updateProject(on: window)
    }

    /// The window shows, and the project folder's index is brought up to date (C-SRC-02);
    /// a folder that is gone is told of the first time since Cutaway opened (C-SRC-01).
    override public func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard !hasShown else { return }
        hasShown = true
        fileActions.updateProject(on: window)
    }

    /// File › Link Project Folder… (C-SRC-01): the folder of the window's app, by its bundle
    /// ID.
    @objc func linkProjectFolder(_ sender: Any?) {
        guard let window else { return }
        fileActions.linkProjectFolder(on: window)
    }

    /// Where the selected layer's classes are declared; none once disconnected (C-SRC-03).
    var selectionOpenable: OpenableClasses {
        isDisconnected ? .none : project.openable(store.selectedLayerID, in: store.tree)
    }

    /// File › Open in Xcode (C-SRC-03): the first class of the selected layer found, its one
    /// place, or the choice among several at the pointer.
    @objc func openInXcode(_ sender: Any?) {
        project.open(selectionOpenable.first)
    }

    /// Asks where to save, then captures the app into an archive there (C-ARCH-02).
    @objc func saveArchive(_ sender: Any?) {
        guard commands.canSaveArchive, let window else { return }
        fileActions.saveArchive(on: window) { [weak self] in self?.commands.canSaveArchive ?? false }
    }

    /// Exports a layer's own screenshot (C-ARCH-06): the layer of the row menu it was chosen
    /// from, or else the selected one.
    @objc func exportLayerScreenshot(_ sender: Any?) {
        exportScreenshot(.solo, sender)
    }

    /// Exports the screenshot of a layer and its sublayers (C-ARCH-06).
    @objc func exportScreenshotWithSublayers(_ sender: Any?) {
        exportScreenshot(.group, sender)
    }

    private func exportTarget(_ sender: Any?) -> UInt64? {
        (sender as? NSMenuItem)?.representedObject as? UInt64 ?? store.selectedLayerID
    }

    private func canExport(_ kind: TextureKey.Kind, _ sender: Any?) -> Bool {
        commands.canExport(kind, of: exportTarget(sender))
    }

    private func exportScreenshot(_ kind: TextureKey.Kind, _ sender: Any?) {
        guard canExport(kind, sender), let id = exportTarget(sender), let window else { return }
        fileActions.exportScreenshot(of: id, kind: kind, on: window)
    }

    /// Loads the selected layer's subtree again, with its screenshots (C-DET-07).
    @objc func refreshSelectedSubtree(_ sender: Any?) {
        guard let id = store.selectedLayerID else { return }
        store.refreshSubtree(of: id)
    }

    @objc func showTwoD(_ sender: Any?) {
        store.setPreviewMode(.twoD)
    }

    @objc func showThreeD(_ sender: Any?) {
        store.setPreviewMode(.threeD)
    }

    /// Puts the focus in the list's search field, showing the sidebar if it is collapsed
    /// (C-HIER-04).
    @objc func findLayer(_ sender: Any?) {
        splitController.splitViewItems.first?.isCollapsed = false
        window?.makeFirstResponder(splitController.hierarchyController.searchField)
    }

    /// Shows or hides the layers that cannot be seen (C-PREV-08).
    @objc func toggleHiddenLayers(_ sender: Any?) {
        store.setShowsHiddenLayers(!store.showsHiddenLayers)
    }

    /// Turns the borders off, or back to the style they last had (C-PREV-09, C-PREV-17).
    @objc func toggleBorders(_ sender: Any?) {
        store.toggleBorders()
    }

    /// One colour for every border (C-PREV-17).
    @objc func showPlainBorders(_ sender: Any?) {
        store.setBorderStyle(.plain)
    }

    /// Each border in its layer's kind's colour (C-PREV-17).
    @objc func showBordersByKind(_ sender: Any?) {
        store.setBorderStyle(.byKind)
    }

    /// Outlines only the app's own classes, or every layer (C-PREV-17).
    @objc func toggleOnlyAppClasses(_ sender: Any?) {
        store.setOnlyAppClasses(!store.borders.onlyAppClasses)
    }

    /// Marks every other end of the selected layer's constraints, or only those pointed at
    /// (C-PREV-18).
    @objc func toggleConstraintEnds(_ sender: Any?) {
        store.toggleConstraintEnds()
    }

    /// View › Show Inspector while the window itself is the first responder, as it is once
    /// disconnected: the window passes Show Sidebar on to the split view, but not this
    /// (C-MENU-02). With a pane's view first, the split view answers before the window does.
    @objc func toggleInspector(_ sender: Any?) {
        splitController.toggleInspector(sender)
    }

    /// View › Zoom In: as a pinch would, about the middle of the preview (C-MENU-02).
    @objc func zoomIn(_ sender: Any?) {
        splitController.previewController.zoomAboutCentre(by: PreviewViewController.zoomStep)
    }

    /// View › Zoom Out (C-MENU-02).
    @objc func zoomOut(_ sender: Any?) {
        splitController.previewController.zoomAboutCentre(by: 1 / PreviewViewController.zoomStep)
    }

    /// Puts the camera of the mode shown back as it starts (C-PREV-07).
    @objc func resetView(_ sender: Any?) {
        store.resetCamera()
    }

    /// View › Select Parent Layer (C-ATTR-16).
    @objc func selectParentLayer(_ sender: Any?) {
        store.selectParent()
    }

    /// View › Select First Child Layer (C-ATTR-16).
    @objc func selectFirstChildLayer(_ sender: Any?) {
        store.selectFirstChild()
    }

    @objc func focusOnSelectedLayer(_ sender: Any?) {
        store.focus(on: store.selectedLayerID)
    }

    @objc func showAllLayers(_ sender: Any?) {
        store.focus(on: nil)
    }

    @objc func expandAllLayers(_ sender: Any?) {
        store.expandAll()
    }

    @objc func collapseAllLayers(_ sender: Any?) {
        store.collapseAll()
    }
}

extension InspectorWindowController: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        onClose()
    }

    /// The window's undo is the attribute changes (C-ATTR-08): the Edit menu's Undo and Redo
    /// read their titles from it. The panel's fields keep no undo of their own.
    /// An empty one while nothing can be changed (C-ATTR-04), as once the connection is gone:
    /// Undo and Redo are unavailable then, rather than failing and losing their step. Nil would
    /// not do: the window would use an undo manager of its own.
    public func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        guard store.attributes.canEdit else { return idleUndoManager }
        return store.attributes.undoManager
    }
}

extension InspectorWindowController: NSMenuItemValidation {
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(showTwoD(_:)):
            menuItem.state = commands.isShowingTwoD ? .on : .off
            return commands.canChangePreview
        case #selector(showThreeD(_:)):
            menuItem.state = commands.isShowingThreeD ? .on : .off
            return commands.canChangePreview
        case #selector(refresh(_:)):
            return commands.canRefresh
        case #selector(refreshSelectedSubtree(_:)):
            return commands.canRefreshSelectedSubtree
        case #selector(saveArchive(_:)):
            return commands.canSaveArchive
        case #selector(linkProjectFolder(_:)):
            // The folder linked now, under the item.
            let folder = project.linkedFolder
            if #available(macOS 14.4, *) { menuItem.subtitle = folder?.lastPathComponent }
            menuItem.toolTip = folder?.path
            return project.canLink
        case #selector(openInXcode(_:)):
            return !selectionOpenable.isEmpty
        case #selector(copyLLDBPrintCommand(_:)), #selector(copyLLDBFrameBreakpoints(_:)):
            return validateLLDBItem(menuItem)
        case #selector(chooseEnvironmentValue(_:)), #selector(toggleAppearance(_:)),
             #selector(resetEnvironment(_:)):
            return validateEnvironmentItem(menuItem)
        case #selector(exportLayerScreenshot(_:)):
            return canExport(.solo, menuItem)
        case #selector(exportScreenshotWithSublayers(_:)):
            return canExport(.group, menuItem)
        case #selector(toggleHiddenLayers(_:)):
            menuItem.state = commands.isShowingHiddenLayers ? .on : .off
            return commands.canChangePreview
        case #selector(toggleBorders(_:)):
            menuItem.state = commands.isShowingBorders ? .on : .off
            return commands.canChangePreview
        case #selector(showPlainBorders(_:)):
            menuItem.state = commands.borderStyle == .plain ? .on : .off
            return commands.canChangePreview
        case #selector(showBordersByKind(_:)):
            menuItem.state = commands.borderStyle == .byKind ? .on : .off
            return commands.canChangePreview
        case #selector(toggleOnlyAppClasses(_:)):
            menuItem.state = commands.isOutliningOnlyAppClasses ? .on : .off
            return commands.canChangePreview
        case #selector(toggleConstraintEnds(_:)):
            menuItem.state = commands.isShowingConstraintEnds ? .on : .off
            return commands.canChangePreview
        case #selector(toggleInspector(_:)):
            return splitController.validateUserInterfaceItem(menuItem)
        case #selector(resetView(_:)), #selector(zoomIn(_:)), #selector(zoomOut(_:)):
            return commands.canChangePreview
        case #selector(findLayer(_:)):
            return commands.canFindLayer
        case #selector(selectParentLayer(_:)):
            return commands.canSelectParent
        case #selector(selectFirstChildLayer(_:)):
            return commands.canSelectFirstChild
        case #selector(focusOnSelectedLayer(_:)):
            return commands.canFocusOnSelectedLayer
        case #selector(showAllLayers(_:)):
            return commands.canShowAllLayers
        case #selector(expandAllLayers(_:)), #selector(collapseAllLayers(_:)):
            return commands.canExpandOrCollapseAll
        default:
            return true
        }
    }
}
