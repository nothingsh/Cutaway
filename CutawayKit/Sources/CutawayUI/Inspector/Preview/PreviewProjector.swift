import CutawayModel
import CutawayScene
import Foundation

/// Works out what the preview shows: it projects the store's layout with the selection, the
/// hover, the mode's camera and the view's size, and goes over to a new mode, or a new
/// expansion, in a short transition from what is on screen (C-PREV-11, C-PREV-12). Each
/// projection goes to `show` with whether it is a frame of a transition.
@MainActor
final class PreviewProjector {
    // What the preview shows is worked out from these, which are the values the store
    // published. Inside a subscription the store itself still holds the old value.
    private(set) var layout = SceneLayout(layers: [], expanded: [])
    var selected: UInt64?
    var hovered: UInt64?
    var constraintEnds: [ConstraintEnd] = []
    /// Whether the preview measures the layer under the pointer against the selected one.
    var measuring = false
    private(set) var mode = PreviewMode.twoD
    private(set) var viewport = Viewport(width: 0, height: 0)
    private var cameras = PreviewCameras()

    /// Paces the transitions; nil for `PreviewMotion.instant`.
    private let clock: (any PreviewClock)?
    /// Asked as each transition would start: true leaves it out.
    private let reducesMotion: @MainActor () -> Bool
    /// Keeps the textures of the images drawn and drops the rest.
    private let keepTextures: @MainActor (Set<TextureKey>) -> Void
    private let show: @MainActor (_ list: DrawList, _ isInTransition: Bool) -> Void
    /// Whether the clock is ticking.
    private var isTicking = false
    /// Set once the subscriptions are made: the values they first send are where the preview
    /// starts, not changes to show.
    var followsChanges = false
    /// From the lens on screen when the mode changed, to the camera of the mode.
    private var lensTransition: (from: Lens, start: Double)?
    /// From what was on screen when the expansion changed, to `layout`.
    private var layoutTransition: (transition: SceneTransition, start: Double)?
    /// The least time between two showings of new images alone. Longer than a frame: while
    /// the screenshots load, a chunk comes every few milliseconds (C-SCALE-02). Changed by
    /// tests.
    var imagesInterval = Duration.milliseconds(50)
    /// When new images alone were last shown.
    private var imagesShownAt: ContinuousClock.Instant?
    /// Set while new images wait for their showing.
    private var imagesWaiting = false

    /// Counts the layouts followed, so that a still picture knows which one it shows.
    private var layoutRevision = 0
    /// The last still picture, with what it was projected from besides the selection and the
    /// hover. While that stays, a new selection or hover changes only which layers are
    /// highlighted, and costs no projection (C-SCALE-01).
    private var lastStill: (basis: StillBasis, list: DrawList)?
    /// The projections of the layout or a transition so far, for tests.
    private(set) var projectionCount = 0

    /// What a still picture is projected from, besides the selection and the hover.
    private struct StillBasis: Equatable {
        var layoutRevision: Int
        var lens: Lens
        var viewport: Viewport
        var marks: [SceneMark]
        var measured: UInt64?
    }

    /// Whether a transition is under way.
    var isInTransition: Bool { lensTransition != nil || layoutTransition != nil }

    init(
        clock: (any PreviewClock)?, reducesMotion: @escaping @MainActor () -> Bool,
        keepTextures: @escaping @MainActor (Set<TextureKey>) -> Void,
        show: @escaping @MainActor (_ list: DrawList, _ isInTransition: Bool) -> Void
    ) {
        self.clock = clock
        self.reducesMotion = reducesMotion
        self.keepTextures = keepTextures
        self.show = show
    }

    /// New cameras end the turn to a new mode: what moved them is shown at once.
    func follow(_ cameras: PreviewCameras) {
        self.cameras = cameras
        lensTransition = nil
        project()
    }

    func resize(to size: CGSize) {
        let new = Viewport(width: size.width, height: size.height)
        guard new != viewport else { return }
        viewport = new
        project()
    }

    /// Nobody sees a transition once the preview is off screen: it ends, and the clock stops
    /// even if no transition was left for its next tick to find.
    func endTransitions() {
        stopTicking()
        guard isInTransition else { return }
        lensTransition = nil
        if layoutTransition != nil {
            layoutTransition = nil
            keepDrawnTextures()
        }
        project()
    }

    /// Shows new images that wait. For tests.
    func showWaitingImages() {
        if imagesWaiting { showLayout() }
    }

    /// Keeps the textures of the images drawn, still or in the transition under way.
    private func keepDrawnTextures() {
        keepTextures(layoutTransition?.transition.drawnTextures ?? layout.drawnTextures)
    }

    // MARK: - Transitions

    /// Whether a change starting now goes over in a transition.
    private var animates: Bool {
        guard followsChanges, clock != nil else { return false }
        return !reducesMotion()
    }

    /// How far a transition that started at `start` is, eased.
    private func progress(since start: Double) -> Double {
        guard let clock else { return 1 }
        return PreviewMotion.eased((clock.now - start) / PreviewMotion.duration)
    }

    /// The lens on screen.
    private var lens: Lens {
        let target = Lens(cameras[mode])
        guard let turn = lensTransition else { return target }
        return turn.from.interpolated(to: target, progress: progress(since: turn.start))
    }

    /// Another mode: from the lens on screen to the mode's camera (C-PREV-11).
    func follow(_ mode: PreviewMode) {
        let from = lens
        self.mode = mode
        if animates, let clock, from != Lens(cameras[mode]) {
            lensTransition = (from, clock.now)
            startTicking()
        } else {
            lensTransition = nil
        }
        project()
    }

    /// A new layout. Another expansion goes over from what is on screen; new images join the
    /// transition under way; anything else shows at once (C-PREV-12).
    func follow(_ layout: SceneLayout) {
        if let moving = layoutTransition, let retargeted = moving.transition.retargeted(to: layout) {
            layoutTransition = (retargeted, moving.start)
        } else if animates, let clock, layout.expandsOtherNodes(than: self.layout),
                  let transition = SceneTransition(
                      from: layoutTransition.map { $0.transition.presentation(at: progress(since: $0.start)) }
                          ?? self.layout.presentation,
                      to: layout)
        {
            layoutTransition = (transition, clock.now)
            startTicking()
        } else {
            layoutTransition = nil
        }
        let imagesOnly = layout.isSameBuild(as: self.layout)
        self.layout = layout
        layoutRevision += 1
        if imagesOnly, followsChanges {
            showNewImages()
        } else {
            showLayout()
        }
    }

    /// Shows the layout: keeps the textures it draws, and projects it.
    private func showLayout() {
        if imagesWaiting { imagesShownAt = .now }
        imagesWaiting = false
        keepDrawnTextures()
        project()
    }

    /// New images alone are shown at most once every `imagesInterval` (C-SCALE-02): they come
    /// a chunk at a time, and each showing projects and draws every layer. Images that come
    /// sooner after the last showing wait for the rest of the interval, and are shown with any
    /// that come meanwhile; anything else shown before then shows them too.
    private func showNewImages() {
        let now = ContinuousClock.now
        guard let shown = imagesShownAt, now - shown < imagesInterval else {
            imagesShownAt = now
            showLayout()
            return
        }
        guard !imagesWaiting else { return }
        imagesWaiting = true
        let wait = imagesInterval - (now - shown)
        Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard let self, self.imagesWaiting else { return }
            self.showLayout()
        }
    }

    private func startTicking() {
        guard !isTicking, let clock else { return }
        isTicking = true
        clock.start { [weak self] in self?.tick() }
    }

    private func stopTicking() {
        guard isTicking else { return }
        isTicking = false
        clock?.stop()
    }

    /// One frame of the transitions under way. A transition that has reached its end is
    /// dropped before the frame, which is then the still picture; with none left, the clock
    /// stops and nothing more is drawn (C-REND-04).
    private func tick() {
        if let turn = lensTransition, progress(since: turn.start) >= 1 { lensTransition = nil }
        if let moving = layoutTransition, progress(since: moving.start) >= 1 {
            layoutTransition = nil
            keepDrawnTextures()
        }
        project()
    }

    /// The layer under the pointer is the hovered one; it is measured against the selected
    /// one in 2D and 3D, but not while the view turns over to the other mode (C-PREV-10,
    /// C-PREV-11, C-PREV-14). A still picture that differs from the last one only in the
    /// selection or the hover, with nothing measured, is the last one highlighted again.
    func project() {
        if imagesWaiting {
            imagesShownAt = .now
            imagesWaiting = false
            keepDrawnTextures()
        }
        let lens = lens
        let marks = constraintEnds.map(\.mark)
        let measured = measuring && lensTransition == nil ? hovered : nil
        let basis = StillBasis(
            layoutRevision: layoutRevision, lens: lens, viewport: viewport, marks: marks,
            measured: measured)
        let list: DrawList
        if let moving = layoutTransition {
            projectionCount += 1
            list = moving.transition.project(
                progress: progress(since: moving.start), lens: lens, viewport: viewport,
                selected: selected, hovered: hovered, marks: marks, measuring: measured)
        } else if lensTransition == nil, measured == nil, let last = lastStill,
                  last.basis == basis
        {
            list = last.list.rehighlighting(selected: selected, hovered: hovered)
        } else {
            projectionCount += 1
            list = layout.project(
                lens: lens, viewport: viewport, selected: selected, hovered: hovered,
                marks: marks, measuring: measured)
        }
        lastStill = isInTransition ? nil : (basis, list)
        // A change that shows at once may have ended the last transition: no tick is due.
        if !isInTransition { stopTicking() }
        show(list, isInTransition)
    }
}
