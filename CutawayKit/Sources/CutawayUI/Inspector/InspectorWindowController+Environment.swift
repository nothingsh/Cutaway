import AppKit
import Combine
import CutawayModel
import CutawayWire

// `environmentButton` and `environmentPopover` are internal only so that this file can set
// and read them.
extension InspectorWindowController {
    static let environmentItem = NSToolbarItem.Identifier("inspector.environment")
    static let environmentIdentifier = "inspector.environment"

    // MARK: - The toolbar's button (C-ENV-01)

    /// The button goes into the toolbar, left of 2D / 3D, once the app's environment is known
    /// and it can override something; it stays, unavailable, once disconnected. A failed
    /// change shows the popover, which says why (C-ENV-02).
    func followEnvironment() {
        store.$environment
            .sink { [weak self] state in self?.showEnvironment(state) }
            .store(in: &cancellables)
        store.$archiveSave
            .sink { [weak self] _ in
                guard let self else { return }
                self.environmentButton?.isEnabled = self.canShowEnvironment(self.store.environment)
            }
            .store(in: &cancellables)
    }

    /// Read from the state given: a publisher of the store sends it before the store holds it.
    private func canShowEnvironment(_ state: EnvironmentState) -> Bool {
        state.controls != nil && !isDisconnected
    }

    private func showEnvironment(_ state: EnvironmentState) {
        if state.controls != nil, environmentButton == nil, let toolbar = window?.toolbar {
            let index = toolbar.items.firstIndex { $0.itemIdentifier == Self.modeItem }
                ?? toolbar.items.count
            toolbar.insertItem(withItemIdentifier: Self.environmentItem, at: index)
        }
        guard let button = environmentButton else { return }
        let overrides = state.controls?.shown ?? .unspecified
        let names = EnvironmentNames.overrideNames(overrides)
        button.contentTintColor = names.isEmpty ? nil : .controlAccentColor
        button.toolTip = names.isEmpty
            ? localized("toolbar.environment.tooltip")
            : localized("toolbar.environment.tooltipOverriding", names.joined(separator: ", "))
        button.isEnabled = canShowEnvironment(state)
        if state.controls == nil { environmentPopover?.close() }
        if state.controls?.failure != nil, environmentPopover?.isShown != true {
            showEnvironmentPopover(nil)
        }
    }

    func makeEnvironmentItem() -> NSToolbarItem {
        let image = Theme.symbol(
            Theme.Symbol.environment, size: 14, description: localized("toolbar.environment.label"))
        let button = NSButton(
            image: image ?? NSImage(), target: self, action: #selector(showEnvironmentPopover(_:)))
        button.bezelStyle = .toolbar
        button.setAccessibilityIdentifier(Self.environmentIdentifier)
        button.toolTip = localized("toolbar.environment.tooltip")
        environmentButton = button
        let item = NSToolbarItem(itemIdentifier: Self.environmentItem)
        item.view = button
        item.label = localized("toolbar.environment.label")
        return item
    }

    /// Shows the popover below the button, or closes it.
    @objc func showEnvironmentPopover(_ sender: Any?) {
        guard let button = environmentButton, canShowEnvironment(store.environment) else { return }
        if let popover = environmentPopover, popover.isShown {
            // The button closes what it opened; a failure leaves it open.
            if sender != nil { popover.close() }
            return
        }
        let popover = environmentPopover ?? NSPopover()
        if environmentPopover == nil {
            popover.behavior = .transient
            popover.contentViewController = EnvironmentPopoverController(store: store)
            popover.delegate = self
            environmentPopover = popover
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    // MARK: - View › Environment (C-MENU-05)

    /// The tag of the menu item that chooses `value` for `kind`.
    static func environmentTag(_ kind: TraitKind, _ value: Traits.Value) -> Int {
        let kindIndex = TraitKind.allCases.firstIndex(of: kind) ?? 0
        let valueIndex = EnvironmentNames.choices(of: kind).firstIndex(of: value) ?? 0
        return kindIndex * 100 + valueIndex
    }

    /// The kind and value a menu item's tag stands for.
    static func environmentChoice(of tag: Int) -> (TraitKind, Traits.Value)? {
        let kinds = TraitKind.allCases
        guard tag >= 0, kinds.indices.contains(tag / 100) else { return nil }
        let kind = kinds[tag / 100]
        let choices = EnvironmentNames.choices(of: kind)
        guard choices.indices.contains(tag % 100) else { return nil }
        return (kind, choices[tag % 100])
    }

    @objc func chooseEnvironmentValue(_ sender: NSMenuItem) {
        guard let (kind, value) = Self.environmentChoice(of: sender.tag) else { return }
        store.setEnvironment(kind, to: value)
    }

    @objc func resetEnvironment(_ sender: Any?) {
        store.resetEnvironment()
    }

    @objc func toggleAppearance(_ sender: Any?) {
        store.toggleAppearance()
    }

    /// Whether an item of View › Environment can be used; a value's item is ticked when it is
    /// the one shown.
    func validateEnvironmentItem(_ item: NSMenuItem) -> Bool {
        guard !isDisconnected, store.canChangeEnvironment, let controls = store.environment.controls
        else {
            item.state = .off
            return false
        }
        switch item.action {
        case #selector(chooseEnvironmentValue(_:)):
            guard let (kind, value) = Self.environmentChoice(of: item.tag) else { return false }
            item.state = controls.shown[kind] == value ? .on : .off
            return controls.overridable.contains(kind)
        case #selector(toggleAppearance(_:)):
            return controls.overridable.contains(.userInterfaceStyle)
        case #selector(resetEnvironment(_:)):
            return controls.isOverriding
        default:
            return false
        }
    }
}

extension InspectorWindowController: NSPopoverDelegate {
    /// What the popover said of a failure is forgotten once it closes (C-ENV-02).
    public func popoverDidClose(_ notification: Notification) {
        store.dismissEnvironmentFailure()
    }
}
