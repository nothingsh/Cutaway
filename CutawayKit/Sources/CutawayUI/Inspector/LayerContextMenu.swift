import AppKit
import CutawayModel

/// The context menu for a layer, the same on a row of the list and on the preview
/// (C-HIER-05, C-DET-07, C-ARCH-06, C-PREV-15): focus on the layer, refresh its subtree when
/// the server can send one, export its screenshot; and, while focused, show all layers.
/// Empty once the connection is gone.
@MainActor
final class LayerContextMenu: NSObject {
    private let store: InspectionStore

    init(store: InspectionStore) {
        self.store = store
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
            // The window's commands for this layer, checked by the window (C-ARCH-06).
            menu.addItem(.separator())
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
