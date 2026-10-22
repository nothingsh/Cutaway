import Combine
import CutawayScene
import CutawayTransport
import CutawayWire
import Foundation

/// The inspection of one app: its layer tree, which nodes are expanded and selected
/// (C-HIER-01, C-HIER-02), the layers' images, and how the preview shows them (C-PREV-01 to
/// C-PREV-03).
///
/// It belongs to one connection. Layer IDs are stable only within a connection (P-HIER-03),
/// so the state kept here means nothing for another one.
///
/// The selected layer's attributes are in `attributes`, which this store keeps informed
/// (C-ATTR-01). The requests go through its collaborators: `loader` asks for the layers,
/// `fetcher` for their screenshots, `saver` captures archives. The store decides what each
/// answer means for what is shown, and publishes it in an order the interface can follow.
@MainActor
public final class InspectionStore: ObservableObject {
    // What the InspectionStore+*.swift files use is internal here only so that they can reach
    // it: the stored state that is not private, and the internal setters of the published
    // properties. It belongs to InspectionStore alone. What is internal for tests says so.
    // How the tree is looked at (the expansion, the focus, the selection, the hover, the
    // search) is published only from this file, by the functions under "Publishing the view of
    // the tree"; `HierarchyViewState` works out its changes.

    public enum LoadFailure: Equatable, Sendable {
        /// The app is not in the foreground (P-APP-01).
        case appNotActive
        /// The app sent a hierarchy that is not a tree. The text says what is wrong with it.
        case invalidHierarchy(String)
        /// A timeout, or another error from the server.
        case other
    }

    public enum LoadState: Equatable, Sendable {
        /// No hierarchy has arrived yet, or one is being asked for again after a failure.
        case loading
        case loaded
        case failed(LoadFailure)
    }

    /// Something the inspection has to say while the tree is shown (C-DET-04).
    public enum Notice: Equatable, Sendable {
        /// Loading stopped because the app is not active; it goes on when the app is active.
        case appNotActive
        /// Loading screenshots stopped on a timeout or another error.
        case screenshotsFailed
        /// Loading the layers again failed; the ones shown stay (C-DET-05).
        case layersFailed
        /// The layer whose subtree was to be refreshed is no longer in the app; the tree
        /// stays as it was (C-DET-07).
        case layerGone
    }

    /// How the inspection reaches its app (C-WIN-03, C-WIN-04, C-ARCH-05). Once the connection
    /// is gone, what was shown stays and the store takes none of the user's intents
    /// (`takesIntents`); the interface follows it to show them unavailable.
    public enum Connection: Equatable, Sendable {
        case live
        /// The app went away; `waiting` when the window waits for it to come back.
        case lost(waiting: Bool)
        case archive

        public var isLost: Bool {
            if case .lost = self { return true }
            return false
        }
    }

    /// How layers the inspection has not seen before start.
    public enum NewLayers: Sendable {
        /// Open down to the view controllers on show (C-HIER-09).
        case byRule
        /// All expanded, as every layer was before C-HIER-09. For tests whose fixtures are
        /// laid out expanded.
        case expanded
    }

    // MARK: - What the interface follows

    @StoreState public private(set) var connection: Connection
    @StoreState public internal(set) var loadState: LoadState = .loading
    /// When this publishes, `isExpanded(_:)` and `selectedLayerID` already describe the new
    /// tree.
    @StoreState public internal(set) var tree: LayerTree = .empty
    /// Never a layer inside a collapsed node: such a selection moves onto that node, so that
    /// the selected layer is always a row the list shows. Changed only by `setSelection(_:)`,
    /// which the attributes follow.
    @StoreState public private(set) var selectedLayerID: UInt64?

    /// The attributes of the selected layer (C-ATTR-01).
    public let attributes: AttributesStore
    /// The other ends of the selected layer's constraints that the preview marks: all of them
    /// with `showsAllConstraintEnds` (C-LAYOUT-04), otherwise those of the constraints and the
    /// chip the pointer is on in the attribute panel (C-LAYOUT-07). Empty while its
    /// constraints are not held. Ends not in the tree are left for the scene to pass over.
    @StoreState public internal(set) var constraintEnds: [ConstraintEnd] = []
    /// The ends the preview stresses while the other ends fade: the chip's the pointer is on
    /// (C-LAYOUT-06), or else the row's (C-LAYOUT-07). Empty while there are none.
    @StoreState public internal(set) var emphasizedConstraintEnds: [SceneMark] = []
    /// Whether every end of the selected layer's constraints is marked, or only those pointed
    /// at (C-PREV-18).
    @StoreState public internal(set) var showsAllConstraintEnds = false
    /// The layer under the pointer in the preview (C-PREV-03).
    @StoreState public private(set) var hoveredLayerID: UInt64?
    @StoreState public internal(set) var previewMode: PreviewMode = .twoD
    /// The camera of each mode; each keeps its own (C-PREV-07). Moving a camera never lays
    /// the tree out again (C-SCENE-07).
    @StoreState public internal(set) var cameras = PreviewCameras()
    /// Whether layers that cannot be seen are drawn, as ghosts (C-PREV-08).
    @StoreState public internal(set) var showsHiddenLayers = false
    /// How layers are outlined (C-PREV-09, C-PREV-17).
    @StoreState public internal(set) var borders = BorderOptions()
    /// The layers' images by layer ID, compressed as they arrived (C-DET-08). Only layers of
    /// `tree` have an entry. Their pixels are handed out once, by `arrivingPixels`, and
    /// decompressed again only when asked for (`pixels(for:)`). Not published: a chunk of
    /// screenshots changes a few entries in place and `imagesChanged` names them, so that a
    /// chunk costs what its layers cost rather than a copy of every entry (C-SCALE-02).
    public internal(set) var images: [UInt64: LayerImages] = [:]
    /// The layers whose images changed, sent once `images` holds the change and before the
    /// layout that draws it publishes.
    public var imagesChanged: AnyPublisher<[UInt64], Never> {
        imagesChangedSubject.eraseToAnyPublisher()
    }

    /// The pixels of images just taken in, by the keys they are held under, sent right before
    /// `imagesChanged` names their layers. Nothing keeps them: whoever wants them takes them
    /// now.
    public var arrivingPixels: AnyPublisher<[TextureKey: Bitmap], Never> {
        arrivingPixelsSubject.eraseToAnyPublisher()
    }

    /// Goes up by one each time a node is expanded or collapsed. The expansion itself is
    /// read with `isExpanded(_:)` or `expandedLayerIDs`, and is already in place when this
    /// publishes.
    @StoreState public private(set) var expansionRevision: UInt64 = 0
    /// What the search field holds, as typed (C-HIER-04).
    @StoreState public private(set) var searchText = ""
    /// The rows the search leaves; nil when there is no search. Searching changes only the
    /// list: the expansion, and so the preview, stay as they are.
    @StoreState public private(set) var filter: HierarchyFilter?
    /// The layer the inspection is focused on, or nil for the whole tree (C-HIER-05). The
    /// list shows it and what is inside it, the preview draws only that, and only those
    /// layers can be selected.
    @StoreState public private(set) var focusedLayerID: UInt64?
    /// Goes up by one each time the list's rows change: another tree, search or focus. The
    /// rows are read from `tree`, `filter` and `focusedLayerID`, which are in place when this
    /// publishes.
    @StoreState public private(set) var rowsRevision: UInt64 = 0
    /// The tree laid out with the images the inspection holds. Its geometry is built again
    /// only when the tree, the expansion or the focus changes; when only images change, their
    /// textures are swapped in. When this publishes, `images`, the expansion and
    /// `expansionRevision` already describe it.
    @StoreState public internal(set) var layout = SceneLayout(layers: [], expanded: [])
    /// Of the layers that are drawn, how many have the screenshot they are drawn with, or
    /// failed, in this round (C-DET-02).
    @StoreState public internal(set) var detailProgress = DetailProgress.none
    /// Shown while the tree is shown. Nil when there is nothing to say.
    @StoreState public internal(set) var notice: Notice?
    /// Whether the source can send a subtree: an app can, an archive cannot (C-DET-07). False
    /// until the source has told, which `enter()` asks it. Set by tests that have no server.
    @StoreState public internal(set) var canRefreshSubtrees = false
    /// Saving an archive (C-ARCH-02). Ended saves stay until `dismissArchiveSave()`.
    @StoreState public internal(set) var archiveSave = ArchiveSaveState.idle
    /// Exporting a layer's screenshot (C-ARCH-06).
    @StoreState public internal(set) var screenshotExport = ScreenshotExportState.idle
    /// The app's trait environment and the overrides set on it (C-ENV-01).
    @StoreState public internal(set) var environment = EnvironmentState.unavailable

    // MARK: - What the store is made of

    /// Internal for tests.
    let source: any InspectionSource
    /// The longest side the app may send an image with; 0 for no limit (P-DET-05).
    let maxTextureDimension: UInt32
    let newLayers: NewLayers
    /// How the inspection started; Reset View goes back to its cameras (C-PREF-02).
    public let start: InspectionStart
    /// The interface's words for what the model must name (C-LOC-01).
    let text: InspectionText
    /// Asks the app for its layers, one request at a time, and queues the rest.
    private(set) lazy var loader = HierarchyLoader(source: source, delegate: self)
    /// Asks the app for screenshots, a batch at a time.
    private(set) lazy var fetcher = ScreenshotFetcher(
        source: source, maxTextureDimension: maxTextureDimension, delegate: self)
    /// Asks for the app's trait environment and changes it (C-ENV-01).
    private(set) lazy var environmentController = EnvironmentController(source: source, delegate: self)
    /// Captures archives (C-ARCH-02).
    let saver = ArchiveSaver()
    let arrivingPixelsSubject = PassthroughSubject<[TextureKey: Bitmap], Never>()
    let imagesChangedSubject = PassthroughSubject<[UInt64], Never>()
    private var attributesState: AnyCancellable?
    /// The selected layer's constraints while they are held, and what the pointer is on
    /// among them (C-LAYOUT-04): what `constraintEnds` is made from.
    var heldConstraints = HeldConstraints()

    // MARK: - What the store keeps besides what it publishes

    /// Whether the inspection is on screen: only then are screenshots asked for.
    private(set) var isOpen = false
    /// Goes up each time the app reports it is active. A request remembers the value it was
    /// made under: an `AppNotActive` failure made under an earlier one is out of date.
    private(set) var activeGeneration: UInt64 = 0
    /// Which nodes are expanded: one entry for every layer of `tree`. Changed only by
    /// `transition(_:)`.
    private(set) var expansion = Expansion()
    /// The layers whose rows the list last reported in view, top to bottom (C-DET-01).
    var visibleLayerIDs: [UInt64] = []
    /// The layout without images.
    var geometry = SceneLayout(layers: [], expanded: [])
    var nextImageRevision: UInt64 = 1
    /// Changes sent and not yet answered. No batch of screenshots starts meanwhile: it would
    /// go ahead of the next one on the server (P-REQ-06).
    var changesOnTheirWay = 0
    /// How long the app is given to redraw after its environment changed, before the tree and
    /// the screenshots are taken again (C-ENV-02): an app may update its look a moment
    /// after the change, which no server can wait for. Tests set it to zero.
    package var environmentSettleDelay: Duration = .milliseconds(500)
    /// The refresh that waits for it; its change counts as on its way until then.
    var environmentSettle: Task<Void, Never>?
    /// Decompresses one image. Only ever called away from the main thread (C-DET-09). Tests
    /// replace it.
    var decodeImage: @Sendable (EncodedImage) throws -> Bitmap = { try $0.decoded() }
    /// Set when the app went away: a capture that stops after it failed for that reason.
    var connectionWasLost = false
    /// An archive's interface state, to take over once the first tree is in (C-ARCH-03).
    var pendingRestore: ArchiveState?
    /// How many times the geometry was built. For tests.
    private(set) var geometryBuildCount = 0
    /// What the last `enter(after:)` waited for. For tests.
    private(set) var enteredAfter: Task<Void, Never>?

    public convenience init(
        session: Session, maxTextureDimension: UInt32 = 0, newLayers: NewLayers = .byRule,
        start: InspectionStart = InspectionStart(), text: InspectionText = InspectionText()
    ) {
        self.init(
            source: session, maxTextureDimension: maxTextureDimension, newLayers: newLayers,
            start: start, text: text)
    }

    /// An inspection of what `source` gives: an app over a connection, or an archive
    /// (C-ARCH-05). It starts as `start` says (C-PREF-02) and names things as `text` says
    /// (C-LOC-01).
    public init(
        source: any InspectionSource, maxTextureDimension: UInt32 = 0,
        newLayers: NewLayers = .byRule, start: InspectionStart = InspectionStart(),
        text: InspectionText = InspectionText()
    ) {
        self.source = source
        self.newLayers = newLayers
        self.start = start
        self.text = text
        connection = source.isLive ? .live : .archive
        previewMode = start.previewMode
        cameras = start.cameras
        showsHiddenLayers = start.showsHiddenLayers
        borders = start.borders
        showsAllConstraintEnds = start.showsConstraintEnds
        self.maxTextureDimension = maxTextureDimension
        self.attributes = AttributesStore(source: source, undoActionName: text.undoActionName)
        attributes.delegate = self
        // The attributes store sets the layer its state is about before the state.
        attributesState = attributes.$state.sink { [weak self] state in
            guard let self else { return }
            var constraints: [LayoutConstraint] = []
            if case .loaded(_, let held) = state, self.attributes.selectedID != nil {
                constraints = held
            }
            if self.heldConstraints.hold(constraints, of: self.attributes.selectedID) {
                self.showConstraintEnds()
            }
        }
    }

    // MARK: - Entering and leaving

    /// Opens the inspection: loads the hierarchy, then asks for screenshots and the selected
    /// layer's attributes. The hierarchy is asked for once `previous` (the app's icon) is
    /// done, and the first time also the environment (C-ENV-03): the app answers in order
    /// anyway (P-REQ-06), and one order on the wire is what a replayed connection expects.
    public func enter(after previous: Task<Void, Never>? = nil) {
        isOpen = true
        enteredAfter = previous
        let environmentLoaded = Task { [weak self] in
            await previous?.value
            await self?.environmentController.load()
        }
        loader.reload(after: environmentLoaded)
        attributes.setOpen(true)
        Task { [weak self, source] in
            // The handshake is long over when an inspection opens, so this is the final word.
            guard let capabilities = await source.capabilities else { return }
            self?.canRefreshSubtrees = capabilities.canRefreshSubtrees
            self?.attributes.setCapabilities(capabilities)
        }
    }

    /// The app reported a new state. When it is active again and the inspection is open and
    /// waiting for that, loading starts over (C-DET-04); attributes that are missing are
    /// asked for.
    public func appStateDidChange(_ state: AppState) {
        if state == .active { activeGeneration += 1 }
        // A whole load under way already follows the app back: its tree is taken now, or it
        // is refused as not active from before this news and asked again. A subtree on its
        // way is not: it renews only itself.
        if isOpen, state == .active, !loader.isLoadingWholeTree,
           loadState == .failed(.appNotActive) || notice == .appNotActive
        {
            loader.reload()
        }
        attributes.appStateDidChange(state)
    }

    /// Closes the inspection: the screenshots and attributes under way are cancelled
    /// (C-DET-02), and the screenshots held are let go unless the app went away (C-DET-10).
    public func leave() {
        isOpen = false
        cancelEnvironmentSettle()
        // A reload queued for the visit that ends is not wanted: entering again reloads.
        loader.dropQueued()
        fetcher.cancelWaitForRows()
        fetcher.cancel()
        cancelArchiveSave()
        attributes.setOpen(false)
        // An app that went away keeps its last screenshots on screen (C-WIN-03); they go with
        // the window.
        if !connectionWasLost { releaseImages() }
    }

    /// Lets go of every screenshot (C-DET-10). A new round makes them all due again: entering
    /// again asks for them even if its hierarchy does not come, or asking stopped before.
    private func releaseImages() {
        fetcher.startRound()
        guard !images.isEmpty else {
            publishProgress()
            return
        }
        let released = Array(images.keys)
        images = [:]
        imagesChangedSubject.send(released)
        swapTextures()
    }

    /// The app went away (C-WIN-03): the interface shows it, and a capture under way failed
    /// because of it, also when it is cancelled by `leave()` before it noticed. `waiting`
    /// when the window waits for the app to come back (C-WIN-04). From then on nothing is
    /// hovered, the attributes cannot be changed, and the user's intents are not taken
    /// (`takesIntents`). Told once; an archive is never lost.
    package func connectionLost(waiting: Bool = false) {
        connectionWasLost = true
        cancelEnvironmentSettle()
        if connection == .live {
            connection = .lost(waiting: waiting)
            publishHover(nil)
            attributes.connectionLost()
        }
        environmentController.connectionLost()
    }

    /// Whether the user's intents are taken: what they ask of the tree, the preview and the
    /// app. Not once the connection is gone (C-WIN-03): what was shown stays as it was. What
    /// only ends something, as leaving, cancelling a save or dismissing a notice, still goes
    /// on, and so does text typed into the search before the connection went (C-WIN-04).
    var takesIntents: Bool { !connection.isLost }

    // MARK: - Publishing the view of the tree

    /// Runs a transition of how the tree is looked at, on what the store holds, and returns
    /// what changed with the new state. The expansion is in place when this returns: it is
    /// not published, only announced. The rest is the caller's to publish, part by part, in
    /// the order its interface needs.
    func transition(
        _ body: (inout HierarchyViewState) -> HierarchyViewState.Change
    ) -> (HierarchyViewState.Change, HierarchyViewState) {
        var state = HierarchyViewState(
            expansion: expansion, focus: focusedLayerID, selection: selectedLayerID,
            hover: hoveredLayerID)
        // The state holds the only reference: a transition changes the expansion in place
        // rather than copying an entry for every layer.
        expansion = Expansion()
        let change = body(&state)
        expansion = state.expansion
        return (change, state)
    }

    /// The one way the selection changes. It publishes, then the attributes follow it
    /// (C-ATTR-01): they never choose a layer of their own. A new tree tells them first, with
    /// its round (`install`), and this then has nothing left to tell them.
    func setSelection(_ id: UInt64?) {
        guard id != selectedLayerID else { return }
        selectedLayerID = id
        attributes.select(id)
    }

    func publishFocus(_ id: UInt64?) {
        if id != focusedLayerID { focusedLayerID = id }
    }

    func publishHover(_ id: UInt64?) {
        if id != hoveredLayerID { hoveredLayerID = id }
    }

    /// Returns whether the text changed.
    func publishSearchText(_ text: String) -> Bool {
        guard text != searchText else { return false }
        searchText = text
        return true
    }

    /// Says that the expansion changed; it is in place already.
    func announceExpansion() {
        expansionRevision += 1
    }

    /// Says that the list's rows changed; `tree`, `filter` and `focusedLayerID` are in place.
    func announceRows() {
        rowsRevision += 1
    }

    /// Searches the tree, by default the one shown, again with the text, within the focus.
    /// Returns whether the filter changed, after publishing it.
    @discardableResult
    func refilter(in tree: LayerTree? = nil) -> Bool {
        let new = HierarchyFilter(
            text: searchText, tree: tree ?? self.tree, within: focusedLayerID,
            untitled: text.untitledLayer)
        guard new != filter else { return false }
        filter = new
        return true
    }

    // MARK: - For the geometry

    /// Builds the geometry of a tree and takes its needs, without publishing anything: a new
    /// tree is laid out before it is published, so whoever follows the tree and asks for
    /// screenshots asks for the new tree's.
    func layOut(_ tree: LayerTree) {
        geometry = SceneLayout(
            layers: tree.sceneLayers(), expanded: expansion.expandedIDs, focus: focusedLayerID,
            showsHidden: showsHiddenLayers, keepingLevelsOf: geometry)
        geometryBuildCount += 1
        fetcher.scheduler.setNeeds(geometry.neededTextures)
    }
}
