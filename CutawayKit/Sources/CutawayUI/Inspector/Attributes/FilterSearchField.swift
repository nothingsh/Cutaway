import AppKit

/// The search field of the attribute panel's filter. Without its bezel the system's cell edits
/// over the whole field, so the caret and the placeholder sat under the magnifier while typing
/// (reported by the user); this cell edits where it draws the text, between the magnifier and
/// the clear button.
final class FilterSearchField: NSSearchField {
    override static var cellClass: AnyClass? {
        get { FilterSearchFieldCell.self }
        set {}
    }
}

final class FilterSearchFieldCell: NSSearchFieldCell {
    override func edit(
        withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj,
                   delegate: delegate, event: event)
    }

    override func select(
        withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?,
        start selStart: Int, length selLength: Int
    ) {
        super.select(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj,
                     delegate: delegate, start: selStart, length: selLength)
    }
}
