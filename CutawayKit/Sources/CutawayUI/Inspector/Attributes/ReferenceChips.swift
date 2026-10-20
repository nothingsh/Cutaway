import CutawayModel
import CutawayWire

extension AttributesViewModel {
    /// The chips of the objects a value refers to (C-ATTR-28, P-ATTR-18), in its order: an
    /// object whose layer is in the hierarchy by its name and the hierarchy's icon for that
    /// layer, which for a view controller's root view is the controller's; any other by its
    /// name alone, grey, going nowhere.
    nonisolated static func chips(of references: [ObjectReference], in tree: LayerTree) -> [LayerChip] {
        references.map { reference in
            let className = reference.className ?? reference.displayClassName
            guard let id = reference.layerID, tree.contains(id) else {
                return LayerChip(
                    name: reference.displayClassName, icon: .none, layerID: nil, canHover: false, toolTip: className)
            }
            return LayerChip(
                name: reference.displayClassName, icon: .layer(LayerIcon(tree.node(id))), layerID: id,
                canHover: true, toolTip: className + " · " + localized("attributes.reference.layer", String(id)))
        }
    }

    /// The chips of a value's references in the hierarchy there is now.
    func chips(of references: [ObjectReference]) -> [LayerChip] {
        Self.chips(of: references, in: tree)
    }
}
