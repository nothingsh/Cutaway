import AppKit
import Combine
import CutawayModel
import CutawayRender
import CutawayScene
import DeclarativeAppKit
import Metal

/// The preview of the inspected app's layers. It follows the store: the store's layout says
/// what is where and with which image; the selection, the hover, the mode and the view's size
/// decide only how the layout is projected. What the pointer does goes to the store.
///
/// The store changes at once; the preview goes over to a new mode, or a new expansion, in a
/// short transition from what is on screen (C-PREV-11, C-PREV-12). `projector` works out what
/// is shown and `textureLoader` keeps the textures; both exist once there is a preview.
final class PreviewViewController: NSViewController {
    static let unavailableIdentifier = "preview.unavailable"

    private let store: InspectionStore
    private(set) var preview: PreviewView?
    private(set) var projector: PreviewProjector?
    private var textureLoader: PreviewTextureLoader?
    /// False once the connection is gone: the pointer no longer moves the camera (C-WIN-03).
    private var takesInput = true
    private var cancellables = Set<AnyCancellable>()
    private let motion: PreviewMotion
    private lazy var layerMenu = LayerContextMenu(store: store)

    /// Whether a transition is under way.
    var isInTransition: Bool { projector?.isInTransition ?? false }

    init(store: InspectionStore, motion: PreviewMotion = .system) {
        self.store = store
        self.motion = motion
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = try? Renderer(device: device)
        else {
            let root = NSView()
            root.addVStack(alignment: .center) {
                Spacer()
                NSTextField(
                    wrappingLabelWithString: localized("preview.noMetal"))
                    .textColor(.secondaryLabelColor)
                    .accessibilityIdentifier(Self.unavailableIdentifier)
                Spacer()
            }
            view = root
            return
        }
        let preview = PreviewView(renderer: renderer, followsAppearance: true)
        let textureLoader = PreviewTextureLoader(
            store: store, textures: preview.textures,
            onLateTextures: { [weak preview] in preview?.needsDisplay = true })
        let motion = motion
        self.textureLoader = textureLoader
        projector = PreviewProjector(
            clock: motion.makeClock?(preview),
            reducesMotion: { [weak preview] in preview.map { motion.reducesMotion($0) } ?? true },
            keepTextures: { drawn in textureLoader.keepDrawnTextures(drawn) },
            show: { [weak preview] list, isInTransition in
                preview?.isInTransition = isInTransition
                preview?.show(list)
            })
        takeInput(from: preview)
        self.preview = preview
        view = preview
        followStore()
        projector?.followsChanges = true
    }

    /// The pointer, clicks, drags, scrolls and pinches on the preview.
    private func takeInput(from preview: PreviewView) {
        preview.onHover = { [weak store] id in store?.hover(id) }
        preview.onClick = { [weak self, weak store] id in
            guard let store, self?.takesInput == true else { return }
            // A click on the selected layer asks again for its attributes when they could not
            // be loaded, as a click on its row does (C-ATTR-01).
            if let id, id == store.selectedLayerID {
                store.retryAttributes()
            } else {
                store.select(id)
            }
        }
        // A double click on a layer with sublayers expands or collapses it, as a double
        // click on its row does; the list follows the store (C-PREV-13).
        preview.onDoubleClick = { [weak self, weak store] id in
            guard let store, self?.takesInput == true, !store.tree.children(of: id).isEmpty
            else { return }
            store.setExpanded(id, !store.isExpanded(id))
        }
        // A right click selects the layer under it, then opens its menu, the one its row
        // has; on nothing the menu only offers to show all layers while focused (C-PREV-15).
        preview.onContextMenu = { [weak self] id in
            guard let self, self.takesInput else { return nil }
            if let id, id != self.store.selectedLayerID { self.store.select(id) }
            let menu = NSMenu()
            self.layerMenu.fill(menu, for: id)
            return menu.items.isEmpty ? nil : menu
        }
        preview.onResize = { [weak self] viewport in self?.projector?.resize(to: viewport) }
        preview.onMeasuringChange = { [weak self] measuring in
            self?.projector?.measuring = measuring
            self?.projector?.project()
        }
        // A drag turns the 3D view, or pans with ⌥ and in 2D (C-PREV-04, C-PREV-06).
        preview.onDrag = { [weak self] dx, dy, pans in
            guard let self, let projector = self.projector, self.takesInput else { return }
            if pans || projector.mode == .twoD {
                self.store.pan(by: dx, dy)
            } else {
                self.store.rotate(byDragOf: dx, dy)
            }
        }
        preview.onPan = { [weak self] dx, dy in
            guard let self, self.takesInput else { return }
            self.store.pan(by: dx, dy)
        }
        preview.onZoom = { [weak self] factor, point in
            guard let self, let projector = self.projector, self.takesInput else { return }
            self.store.zoom(by: factor, about: point, in: projector.viewport)
        }
    }

    /// How much View › Zoom In and Zoom Out change the zoom (C-MENU-02).
    static let zoomStep = 1.25

    /// Zooms about the middle of the preview between what floats over it, keeping what is there where it is (C-MENU-02,
    /// C-PREV-05). Nothing before the preview has a size, or once it no longer takes input.
    func zoomAboutCentre(by factor: Double) {
        guard let projector, takesInput else { return }
        let viewport = projector.viewport
        store.zoom(by: factor, about: viewport.middle, in: viewport)
    }

    /// What the preview shows follows the store.
    private func followStore() {
        // Pixels before the images, and images before the layout: when the layout comes, the
        // textures of what arrived are in place.
        store.arrivingPixels
            .sink { [weak self] pixels in self?.textureLoader?.upload(pixels) }
            .store(in: &cancellables)
        store.imagesChanged
            .sink { [weak self] ids in self?.textureLoader?.follow(changedLayers: ids) }
            .store(in: &cancellables)
        store.$layout
            .sink { [weak self] layout in self?.projector?.follow(layout) }
            .store(in: &cancellables)
        store.$selectedLayerID
            .sink { [weak self] id in
                self?.projector?.selected = id
                self?.projector?.project()
            }
            .store(in: &cancellables)
        store.$hoveredLayerID
            .sink { [weak self] id in
                self?.projector?.hovered = id
                self?.projector?.project()
            }
            .store(in: &cancellables)
        store.$constraintEnds
            .sink { [weak self] ends in
                self?.projector?.constraintEnds = ends
                self?.projector?.project()
            }
            .store(in: &cancellables)
        store.$emphasizedConstraintEnds
            .sink { [weak self] marks in
                self?.projector?.emphasizedEnds = marks
                self?.projector?.project()
            }
            .store(in: &cancellables)
        store.$previewMode
            .sink { [weak self] mode in self?.projector?.follow(mode) }
            .store(in: &cancellables)
        // Any other move of a camera (a drag, a scroll, a pinch, the spacing, a reset, a new
        // focus) ends the turn to a new mode: what the move did is shown at once.
        store.$cameras
            .sink { [weak self] cameras in self?.projector?.follow(cameras) }
            .store(in: &cancellables)
        store.$borders
            .sink { [weak self] options in self?.preview?.borders.options = options }
            .store(in: &cancellables)
        store.$tree
            .sink { [weak self] tree in self?.preview?.borders.tree = tree }
            .store(in: &cancellables)
    }

    /// Nobody sees a transition once the preview is off screen: it ends, and the clock stops.
    override func viewDidDisappear() {
        super.viewDidDisappear()
        projector?.endTransitions()
    }

    /// Shows new images that wait, and returns once the pixels asked for so far are
    /// uploaded. For tests.
    func texturesSettled() async {
        projector?.showWaitingImages()
        await textureLoader?.settled()
    }

    /// The connection is gone: dragging, scrolling and pinching no longer move the camera.
    func stopTakingInput() {
        takesInput = false
    }

    /// The connection is gone: the pointer no longer hovers a layer (C-WIN-03).
    func stopHovering() {
        preview?.onHover = nil
    }
}
