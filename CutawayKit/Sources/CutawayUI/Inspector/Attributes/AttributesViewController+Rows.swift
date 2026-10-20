import AppKit
import CutawayWire

/// The rows of the attribute panel: an attribute's own, or a compound one (C-ATTR-19).
extension AttributesViewController {
    /// The rows of a part's items, kept in `attributeRows`, `attributeCells` and
    /// `compoundRows` in the order they are made.
    func rows(_ items: [AttributeClusters.Item]) -> [any AttributeListRow] {
        items.map { item -> any AttributeListRow in
            switch item {
            case .single(let attribute):
                let row = makeRow(attribute)
                attributeRows.append((attribute, row))
                attributeCells.append((attribute, row))
                return row
            case .cluster(let cluster):
                let row = makeCompound(cluster)
                compoundRows.append(row)
                attributeCells += row.cells
                return row
            }
        }
    }

    /// The row of one item, not kept anywhere: for a part built page by page (C-SCALE-03),
    /// whose rows the panel lists from the pages built.
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
        } else {
            row = AttributeRowView(
                title: title, value: attribute.value, kind: attribute.valueKind, unit: attribute.unit)
        }
        row.attributeID = attribute.id
        return row
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
            })
        return CompoundRowView(cluster, factory: factory)
    }
}
