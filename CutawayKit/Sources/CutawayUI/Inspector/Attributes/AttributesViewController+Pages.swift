import AppKit
import CutawayWire

/// A layer with very many attributes (C-SCALE-03): its parts are built page by page as the
/// list comes near them (`AttributePageArranger`). Only the rows built are in `attributeRows`,
/// `attributeCells` and `compoundRows`.
extension AttributesViewController {
    /// A part whose rows are built page by page.
    func pagedPart(_ items: [AttributeClusters.Item], heading: String?) -> AttributeGroupView.Part {
        let lazy = LazyRowsView(items: items) { [weak self] item in
            self?.makeListRow(item) ?? AttributeRowView(title: "", value: nil)
        }
        return AttributeGroupView.Part(heading: heading, rows: [], lazy: lazy)
    }

    /// Every part built page by page, in the order of the list.
    var lazyParts: [LazyRowsView] { sectionViews.flatMap(\.lazyParts) }

    /// A row that is typed in, or whose change is on its way or failed, is not taken down.
    func isPinned(_ row: any AttributeListRow) -> Bool {
        if let responder = view.window?.firstResponder as? NSView, responder.isDescendant(of: row) {
            return true
        }
        let attributes: [Attribute] = switch row {
        case let compound as CompoundRowView: compound.row.attributes
        case let single as AttributeRowView:
            attributeRows.first { $0.row === single }.map { [$0.attribute] } ?? []
        default: []
        }
        return attributes.contains { attribute in
            viewModel.key(of: attribute).flatMap { viewModel.store.edits[$0] } != nil
        }
    }
}
