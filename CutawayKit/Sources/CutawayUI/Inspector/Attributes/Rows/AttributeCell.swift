import AppKit
import CutawayWire

/// What shows one attribute in the list and is updated in place (C-ATTR-06): a row of its own,
/// or a part of a compound row (C-ATTR-19).
@MainActor
protocol AttributeCell: AnyObject {
    func show(_ value: AttributeValue?, names: ValueNames)
    func show(sending: Bool, failure: String?)
    func showInactive(_ reason: String?)
    func show(layerSize: String?)
}

/// A row of the list that a filter keeps or hides (C-ATTR-14): an attribute's own row, or a
/// compound one.
@MainActor
protocol AttributeListRow: NSView {
    /// What it is called: the attribute's title, or the compound row's.
    var title: String { get }
    /// How many attributes it shows: what the counts add up.
    var attributeCount: Int { get }
    func matches(_ filter: String) -> Bool
    func highlight(_ filter: String?)
}

extension AttributeRowView: AttributeCell, AttributeListRow {
    var attributeCount: Int { 1 }
}

/// Changes an attribute: sends a value, as it goes or once, and ends a change that went on.
struct AttributeSender {
    var set: (AttributeValue?, _ continuous: Bool) -> Void
    var finish: () -> Void
}
