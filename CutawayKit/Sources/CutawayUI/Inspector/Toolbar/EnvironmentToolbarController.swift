import AppKit
import Combine
import CutawayModel

/// The toolbar's Environment button and its popover (C-ENV-01, C-ENV-02). The button goes into
/// the toolbar, left of 2D / 3D, once the app's environment is known and it can override
/// something; it stays, unavailable, once disconnected, when the environment is no longer
/// known. A failed change shows the popover, which says why.
@MainActor
final class EnvironmentToolbarController: NSObject {
    static let item = NSToolbarItem.Identifier("inspector.environment")
    static let identifier = "inspector.environment"

    private let store: InspectionStore
    /// Puts the button's item into the window's toolbar.
    private let insertItem: @MainActor () -> Void
    /// The button and its popover, once there are. Read by tests.
    private(set) var button: NSButton?
    private(set) var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()

    init(store: InspectionStore, insertItem: @escaping @MainActor () -> Void) {
        self.store = store
        self.insertItem = insertItem
        super.init()
    }

    /// The button follows the app's environment. While an archive is saved it stays available:
    /// the popover shows the environment and turns its controls off itself.
    func follow() {
        store.$environment
            .sink { [weak self] state in self?.show(state) }
            .store(in: &cancellables)
    }

    /// Whether the popover can be shown: while the environment is known, which it is not once
    /// the connection is gone (C-WIN-03).
    private func canShow(_ state: EnvironmentState) -> Bool {
        state.controls != nil
    }

    private func show(_ state: EnvironmentState) {
        if state.controls != nil, button == nil { insertItem() }
        guard let button else { return }
        let names = EnvironmentNames.overrideNames(state.controls?.shown ?? .unspecified)
        button.contentTintColor = names.isEmpty ? nil : .controlAccentColor
        button.toolTip = names.isEmpty
            ? localized("toolbar.environment.tooltip")
            : localized("toolbar.environment.tooltipOverriding", names.joined(separator: ", "))
        button.isEnabled = canShow(state)
        if state.controls == nil { popover?.close() }
        if state.controls?.failure != nil, popover?.isShown != true {
            showPopover(nil)
        }
    }

    /// The toolbar's item, with the button.
    func makeItem() -> NSToolbarItem {
        let image = Theme.symbol(
            Theme.Symbol.environment, size: 14, description: localized("toolbar.environment.label"))
        let button = NSButton(image: image ?? NSImage(), target: self, action: #selector(showPopover(_:)))
        button.bezelStyle = .toolbar
        button.setAccessibilityIdentifier(Self.identifier)
        button.toolTip = localized("toolbar.environment.tooltip")
        self.button = button
        let item = NSToolbarItem(itemIdentifier: Self.item)
        item.view = button
        item.label = localized("toolbar.environment.label")
        return item
    }

    /// Shows the popover below the button, or closes it.
    @objc private func showPopover(_ sender: Any?) {
        guard let button, canShow(store.environment) else { return }
        if let popover, popover.isShown {
            // The button closes what it opened; a failure leaves it open.
            if sender != nil { popover.close() }
            return
        }
        let popover = popover ?? NSPopover()
        if self.popover == nil {
            popover.behavior = .transient
            popover.contentViewController = EnvironmentPopoverController(store: store)
            popover.delegate = self
            self.popover = popover
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

extension EnvironmentToolbarController: NSPopoverDelegate {
    /// What the popover said of a failure is forgotten once it closes (C-ENV-02).
    func popoverDidClose(_ notification: Notification) {
        store.dismissEnvironmentFailure()
    }
}
