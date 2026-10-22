import AppKit
import CutawayWire

/// The rows of the attribute panel: an attribute's own, or a compound one (C-ATTR-19).
extension AttributesViewController {
    /// The row of one item, not kept anywhere: the panel lists the rows it shows
    /// (`ShownAttributeRows`) once they are built.
    func makeListRow(_ item: AttributeClusters.Item) -> any AttributeListRow {
        switch item {
        case .single(let attribute): makeRow(attribute)
        case .cluster(let cluster): makeCompound(cluster)
        }
    }

    private func makeRow(_ attribute: Attribute) -> AttributeRowView {
        let title = AttributeText.title(attribute.title, id: attribute.id)
        let row: AttributeRowView
        if viewModel.hasEditor(attribute), let key = viewModel.key(of: attribute) {
            let editor = AttributeEditorView(
                attribute: attribute, onSet: viewModel.setValue(for: key),
                onFinish: viewModel.finish(for: key))
            row = AttributeRowView(title: title, value: attribute.value, editor: editor)
        } else if attribute.valueKind == .references {
            row = AttributeRowView(
                title: title, value: attribute.value, kind: .references, references: makeReferenceChips())
        } else {
            row = AttributeRowView(
                title: title, value: attribute.value, kind: attribute.valueKind, unit: attribute.unit)
        }
        row.attributeID = attribute.id
        return row
    }

    /// The chips of a value that refers to objects (C-ATTR-28): pointing at one hovers its
    /// layer and clicking selects it, as a constraint's chips do.
    private func makeReferenceChips() -> ReferenceChipsView {
        let viewModel = viewModel
        return ReferenceChipsView(
            chips: { [weak viewModel] in viewModel?.chips(of: $0) ?? [] }, onShowLayer: actions.showLayer,
            onHoverLayer: actions.hoverLayer)
    }

    /// A compound row whose parts edit their attributes as the attributes' own rows do.
    private func makeCompound(_ cluster: AttributeClusters.Row) -> CompoundRowView {
        let viewModel = viewModel
        let factory = CompoundFactory(
            editor: { attribute, options in
                guard viewModel.hasEditor(attribute), let key = viewModel.key(of: attribute) else {
                    return AttributeEditorView(attribute: attribute, isReadOnly: true, options: options)
                }
                return AttributeEditorView(
                    attribute: attribute, onSet: viewModel.setValue(for: key),
                    onFinish: viewModel.finish(for: key), options: options)
            },
            sender: { attribute in
                guard viewModel.hasEditor(attribute), let key = viewModel.key(of: attribute) else {
                    return nil
                }
                return AttributeSender(set: viewModel.setValue(for: key), finish: viewModel.finish(for: key))
            },
            words: viewModel.clusterWords)
        return CompoundRowView(cluster, factory: factory)
    }
}
