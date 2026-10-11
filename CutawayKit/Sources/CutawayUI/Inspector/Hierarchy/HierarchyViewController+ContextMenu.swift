import AppKit

extension HierarchyViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        contextMenu(menu, forRow: outlineView.clickedRow)
    }

    /// The context menu for a row: the one for its layer (`LayerContextMenu`), or, off the
    /// rows, only what does not need a layer.
    func contextMenu(_ menu: NSMenu, forRow row: Int) {
        layerMenu.fill(menu, for: layerID(atRow: row))
    }
}
