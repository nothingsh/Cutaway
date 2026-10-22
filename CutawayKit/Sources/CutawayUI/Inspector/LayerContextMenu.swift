import AppKit
import CutawayModel

/// The context menu for a layer, the same on a row of the list and on the preview
/// (C-HIER-05, C-DET-07, C-ARCH-06, C-PREV-15): focus on the layer, refresh its subtree when
/// the server can send one, open its class in Xcode when the app's project folder declares it
/// (C-SRC-03), copy an LLDB command for it (C-SRC-06), export its screenshot; and, while
/// focused, show all layers. Empty once the connection is gone.
@MainActor
final class LayerContextMenu: NSObject {
    static let openInXcodeIdentifier = NSUserInterfaceItemIdentifier("layerMenu.openInXcode")

    private let store: InspectionStore
    /// The way to the app's project folder, or nil for none.
    private weak var project: ProjectLookup?

    init(store: InspectionStore, project: ProjectLookup?) {
        self.store = store
        self.project = project
    }

    /// Fills `menu` for `id`, or for no layer.
    func fill(_ menu: NSMenu, for id: UInt64?) {
        menu.removeAllItems()
        guard !store.connection.isLost else { return }
        if let id {
            menu.addItem(item(localized("hierarchy.menu.focusOnLayer"), #selector(focusOnMenuItem(_:)), id))
            if store.canRefreshSubtrees, !store.isSavingArchive {
                menu.addItem(
                    item(localized("hierarchy.menu.refreshSubtree"), #selector(refreshSubtreeMenuItem(_:)), id))
            }
            menu.addItem(.separator())
            if let project, let item = openInXcodeItem(for: id, project) {
                menu.addItem(item)
                menu.addItem(.separator())
            }
            // Only for a layer with an address (C-SRC-06).
            if let node = store.tree.node(id), LLDBCommands(node).isAvailable {
                menu.addItem(LLDBMenu.item(for: id))
                menu.addItem(.separator())
            }
            // The window's commands for this layer, checked by the window (C-ARCH-06).
            for (title, action) in [
                (localized("menu.file.exportLayerScreenshot"),
                 #selector(InspectorWindowController.exportLayerScreenshot(_:))),
                (localized("menu.file.exportScreenshotWithSublayers"),
                 #selector(InspectorWindowController.exportScreenshotWithSublayers(_:))),
            ] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.representedObject = id
                menu.addItem(item)
            }
        }
        if store.focusedLayerID != nil {
            menu.addItem(item(localized("hierarchy.showAllLayers"), #selector(leaveFocus(_:)), nil))
        }
    }

    /// Open in Xcode: the place itself, or a submenu of the places when there are several.
    /// None for a layer whose classes are all the system's or not found.
    private func openInXcodeItem(for id: UInt64, _ project: ProjectLookup) -> NSMenuItem? {
        let locations = project.openable(id, in: store.tree).first
        let choices = DeclarationChoices.items(
            for: locations, target: project, action: #selector(ProjectLookup.openChosenPlace(_:)))
        guard let first = choices.first else { return nil }
        let item: NSMenuItem
        if choices.count == 1 {
            item = first
            item.title = localized("source.openInXcode")
            if #available(macOS 14.4, *) { item.subtitle = nil }
        } else {
            item = NSMenuItem(title: localized("source.openInXcode"), action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: item.title)
            for choice in choices {
                submenu.addItem(choice)
            }
            item.submenu = submenu
        }
        item.identifier = Self.openInXcodeIdentifier
        return item
    }

    private func item(_ title: String, _ action: Selector, _ id: UInt64?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = id
        return item
    }

    @objc private func focusOnMenuItem(_ sender: NSMenuItem) {
        store.focus(on: sender.representedObject as? UInt64)
    }

    @objc private func refreshSubtreeMenuItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UInt64 else { return }
        store.refreshSubtree(of: id)
    }

    /// Not named after the View menu's Show All Layers: answering that selector would put
    /// this object in front of the window's controller, which checks whether the command is
    /// available.
    @objc private func leaveFocus(_ sender: Any?) {
        store.focus(on: nil)
    }
}
