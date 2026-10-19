import AppKit
import Combine
import CutawayModel
import Foundation

/// The three panes of an inspection: the layers in the sidebar, the preview in the middle and
/// the selected layer's attributes in the inspector. The panes have their starting widths
/// before the window is first shown (C-WIN-02).
final class InspectorSplitViewController: NSSplitViewController {
    /// The sidebar's starting width, and how narrow and wide it can be dragged.
    static let sidebarWidth: CGFloat = 280
    static let minimumSidebarWidth: CGFloat = 220
    static let maximumSidebarWidth: CGFloat = 420
    /// The inspector's starting width, and how narrow and wide it can be dragged.
    static let inspectorWidth: CGFloat = 300
    static let minimumInspectorWidth: CGFloat = 260
    static let maximumInspectorWidth: CGFloat = 440
    /// The least the preview can be squeezed to by the panes beside it.
    static let minimumPreviewWidth: CGFloat = 320

    let hierarchyController: HierarchyViewController
    let containerController: PreviewPaneViewController
    let attributesController: AttributesViewController
    private let store: InspectionStore
    private var hasPlacedDividers = false
    private var cancellables = Set<AnyCancellable>()
    /// Where the side panes' widths are remembered; nil to start at the default widths
    /// every time.
    let paneWidths: PaneWidths?

    var previewController: PreviewViewController { containerController.previewController }

    /// `project` is the way to the app's project folder (C-SRC-03), nil for none.
    init(store: InspectionStore, appName: String, paneWidths: PaneWidths? = nil, project: ProjectLookup? = nil) {
        self.paneWidths = paneWidths
        self.store = store
        hierarchyController = HierarchyViewController(store: store, appName: appName)
        containerController = PreviewPaneViewController(store: store, appName: appName)
        let layer = project.map { store.selectedLayerSummary(index: $0.index) } ?? store.selectedLayerSummary
        attributesController = AttributesViewController(
            store: store.attributes, appName: appName, layer: layer,
            tree: store.$tree.eraseToAnyPublisher(),
            connection: store.$connection.eraseToAnyPublisher(),
            onRetry: { [weak store] in store?.retryAttributes() },
            onShowLayer: { [weak store] id in store?.showLayer(id) },
            onHoverLayer: { [weak store] id in
                // Not once the connection is gone, as in the list.
                guard let store, !store.connection.isLost else { return }
                store.hover(id)
            },
            onHoverConstraintEnd: { [weak store] end in
                guard let store, !store.connection.isLost else { return }
                store.hoverConstraintEnd(end?.mark, layerID: end?.layerID)
            },
            onPointConstraints: { [weak store] pointer in
                guard let store, !store.connection.isLost else { return }
                switch pointer {
                case .entered(let indices, let stresses):
                    store.pointConstraints(indices, stresses: stresses)
                case .left(let indices):
                    store.leaveConstraints(indices)
                }
            },
            openInXcode: { [weak project] locations, button in project?.open(locations, from: button) },
            projectIndex: project?.index ?? Just(nil).eraseToAnyPublisher())
        super.init(nibName: nil, bundle: nil)
        hierarchyController.layerMenu.project = project
        previewController.layerMenu.project = project
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.dividerStyle = .thin

        let sidebar = NSSplitViewItem(sidebarWithViewController: hierarchyController)
        sidebar.minimumThickness = Self.minimumSidebarWidth
        sidebar.maximumThickness = Self.maximumSidebarWidth
        sidebar.canCollapse = true

        let content = NSSplitViewItem(viewController: containerController)
        content.minimumThickness = Self.minimumPreviewWidth
        // The preview runs up under the toolbar and its capsules float over it (C-WIN-06):
        // no line between them.
        content.titlebarSeparatorStyle = .none

        let inspector = NSSplitViewItem(inspectorWithViewController: attributesController)
        inspector.minimumThickness = Self.minimumInspectorWidth
        inspector.maximumThickness = Self.maximumInspectorWidth
        inspector.canCollapse = true

        // When the window is resized the side panes keep their widths and the preview takes
        // the rest.
        sidebar.holdingPriority = NSLayoutConstraint.Priority(rawValue: 260)
        content.holdingPriority = NSLayoutConstraint.Priority(rawValue: 250)
        inspector.holdingPriority = NSLayoutConstraint.Priority(rawValue: 260)

        addSplitViewItem(sidebar)
        addSplitViewItem(content)
        addSplitViewItem(inspector)

        // The connection is gone: the panes fade (C-WIN-03). Each pane stops taking clicks on
        // layers by itself.
        store.$connection
            .sink { [weak self] connection in
                guard case .lost = connection else { return }
                self?.fadePanes()
            }
            .store(in: &cancellables)
    }

    /// Puts the dividers at the starting widths, once, as soon as there is the width for
    /// them: the remembered ones, within their ranges, or the defaults. The window lays
    /// itself out before it is first shown, so this happens off screen (C-WIN-02).
    override func viewDidLayout() {
        super.viewDidLayout()
        guard !hasPlacedDividers else { return }
        let width = splitView.bounds.width
        let saved = paneWidths?.load()
        let starts = [
            (
                min(max(saved?.sidebar ?? Self.sidebarWidth, Self.minimumSidebarWidth),
                    Self.maximumSidebarWidth),
                min(max(saved?.inspector ?? Self.inspectorWidth, Self.minimumInspectorWidth),
                    Self.maximumInspectorWidth)
            ),
            (Self.sidebarWidth, Self.inspectorWidth),
        ]
        // Remembered widths that leave the preview too little room give way to the defaults.
        guard let (sidebar, inspector) = starts.first(where: { sidebar, inspector in
            width >= sidebar + Self.minimumPreviewWidth + inspector + 2 * splitView.dividerThickness
        }) else { return }
        hasPlacedDividers = true
        splitView.setPosition(sidebar, ofDividerAt: 0)
        // Where the divider goes, the inspector's frame begins: a sidebar's and an inspector's
        // dividers take no width of their own.
        splitView.setPosition(width - inspector, ofDividerAt: 1)
    }

    /// Remembers the side panes' widths after a divider moved, once they have been placed. A
    /// window made narrower squeezes the panes; that is not a width the user chose. A divider
    /// that moves, dragged or set, comes with "NSSplitViewUserResizeKey" in the notification;
    /// the squeeze of a window that changes size does not (observed on macOS 26; the key is
    /// not documented, so a test pins it down).
    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        guard notification.userInfo?["NSSplitViewUserResizeKey"] != nil, hasPlacedDividers,
              let paneWidths, splitViewItems.count == 3,
              !splitViewItems[0].isCollapsed, !splitViewItems[2].isCollapsed
        else { return }
        let panes = splitView.arrangedSubviews
        paneWidths.save(sidebar: panes[0].frame.width, inspector: panes[2].frame.width)
    }

    private func fadePanes() {
        for item in splitViewItems {
            item.viewController.view.alphaValue = 0.5
        }
        // The disconnected notice in the preview stays as it is.
        containerController.view.alphaValue = 1
        containerController.previewController.view.alphaValue = 0.5
    }
}

/// Where the widths of an inspector window's side panes are kept between windows and launches.
struct PaneWidths {
    /// The key the app keeps its inspector windows' widths under.
    static let inspectorKey = "Inspector pane widths"

    let key: String
    let defaults: UserDefaults

    func load() -> (sidebar: CGFloat, inspector: CGFloat)? {
        guard let widths = defaults.array(forKey: key) as? [Double], widths.count == 2 else {
            return nil
        }
        return (CGFloat(widths[0]), CGFloat(widths[1]))
    }

    func save(sidebar: CGFloat, inspector: CGFloat) {
        defaults.set([Double(sidebar), Double(inspector)], forKey: key)
    }
}
